#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(realpath "$0")")"

# Source shared functions
source ./lib.sh

# Cache current versions from generated.nix BEFORE nvfetcher runs
declare -A OLD_VERSIONS
SOURCE_CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$SOURCE_CACHE_DIR"' EXIT

cache_old_versions() {
  # Get package list dynamically from generated.json
  local packages
  packages=$(jq -r 'keys[]' _sources/generated.json 2>/dev/null || echo "")
  for pkg in $packages; do
    # Parse version from generated.nix (can't use nix eval - it's a function)
    OLD_VERSIONS[$pkg]=$(grep -A2 "$pkg = {" _sources/generated.nix | grep 'version' | sed 's/.*version = "\([^"]*\)".*/\1/' || echo "")
  done
}

cache_sources() {
  cp _sources/generated.nix "$SOURCE_CACHE_DIR/generated.nix"
  cp _sources/generated.json "$SOURCE_CACHE_DIR/generated.json"
  mkdir -p "$SOURCE_CACHE_DIR/source-versions"

  local pkg pkg_dir
  for pkg in $(jq -r 'keys[]' _sources/generated.json 2>/dev/null); do
    pkg_dir="packages/$pkg"
    if [ -f "$pkg_dir/.source-version" ]; then
      cp "$pkg_dir/.source-version" "$SOURCE_CACHE_DIR/source-versions/$pkg"
    fi
  done
}

# Restore one package's nvfetcher output from the pre-update cache.
# This is used when a source bump cannot be made buildable yet, while keeping
# unrelated package updates from the same nvfetcher run.
restore_cached_package_source() {
  local pkg="$1"
  local tmp_file

  if ! jq -e --arg pkg "$pkg" 'has($pkg)' "$SOURCE_CACHE_DIR/generated.json" >/dev/null; then
    echo "  $pkg: no cached source entry found, leaving generated sources unchanged"
    return 0
  fi

  tmp_file=$(mktemp)
  jq --arg pkg "$pkg" --slurpfile old "$SOURCE_CACHE_DIR/generated.json" \
    '.[$pkg] = $old[0][$pkg]' \
    _sources/generated.json > "$tmp_file"
  mv "$tmp_file" _sources/generated.json

  tmp_file=$(mktemp)
  awk -v pkg="$pkg" -v old_file="$SOURCE_CACHE_DIR/generated.nix" '
    BEGIN {
      pattern = "^  " pkg " = \\{"
      while ((getline line < old_file) > 0) {
        if (line ~ pattern) {
          in_old = 1
        }
        if (in_old) {
          old_block = old_block line "\n"
        }
        if (in_old && line ~ /^  \};/) {
          in_old = 0
        }
      }
    }
    $0 ~ pattern {
      if (old_block != "") {
        printf "%s", old_block
      }
      skip = 1
      next
    }
    skip && $0 ~ /^  \};/ {
      skip = 0
      next
    }
    !skip {
      print
    }
  ' _sources/generated.nix > "$tmp_file"
  mv "$tmp_file" _sources/generated.nix

  if [ -f "$SOURCE_CACHE_DIR/source-versions/$pkg" ]; then
    cp "$SOURCE_CACHE_DIR/source-versions/$pkg" "packages/$pkg/.source-version"
  else
    rm -f "packages/$pkg/.source-version"
  fi
}

is_toolchain_too_old() {
  local build_output="$1"

  echo "$build_output" | grep -qiE \
    'requires go >= [0-9]+\.[0-9]+(\.[0-9]+)? \(running go [0-9]+\.[0-9]+(\.[0-9]+)?; GOTOOLCHAIN=local\)|requires rustc [0-9]+\.[0-9]+(\.[0-9]+)? or newer|rustc [0-9]+\.[0-9]+(\.[0-9]+)? is not supported|EBADENGINE|Unsupported engine|The engine "node" is incompatible|Requires-Python[[:space:]]*[>=<~!]+[[:space:]]*[0-9]+\.[0-9]+|requires Python[[:space:]]*[>=<~!]+[[:space:]]*[0-9]+\.[0-9]+|requires Java[[:space:]]*[0-9]+|invalid source release:[[:space:]]*[0-9]+|Unsupported class file major version'
}

emit_github_warning() {
  local pkg="$1"
  local message="$2"
  local escaped_message

  if [ "${GITHUB_ACTIONS:-}" != "true" ]; then
    return 0
  fi

  escaped_message=${message//'%'/'%25'}
  escaped_message=${escaped_message//$'\r'/'%0D'}
  escaped_message=${escaped_message//$'\n'/'%0A'}

  echo "::warning title=Package update skipped::$escaped_message"

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### Package update skipped"
      echo ""
      echo "- Package: \`$pkg\`"
      echo "- Reason: $message"
      echo ""
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

skip_update_until_toolchain_updates() {
  local pkg="$1"
  local message="upstream requires a newer toolchain than nixpkgs currently provides; restored the previous source pin and skipped this update"

  echo "  $pkg: upstream requires a newer toolchain than nixpkgs currently provides"
  echo "  $pkg: restoring previous source pin and skipping this update for now"
  emit_github_warning "$pkg" "$message"
  restore_cached_package_source "$pkg"
}

# Check if package version changed (compares cached version with generated.json)
version_changed() {
  local pkg="$1"
  local old_ver="${OLD_VERSIONS[$pkg]:-}"
  local new_ver=$(jq -r ".[\"$pkg\"].version // empty" "_sources/generated.json")

  if [ -z "$old_ver" ]; then
    return 0  # No old version, assume changed
  fi

  [ "$old_ver" != "$new_ver" ]
}

# Cache versions before nvfetcher updates them
echo "=== Caching current versions ==="
cache_old_versions
cache_sources

echo "=== Refreshing remotepc-host download URLs ==="
# RemotePC's download URLs embed a release-specific path segment that nvfetcher
# can't template. Resolve the live URLs before nvfetcher so it hashes the
# current artifacts. Non-fatal: keep existing URLs if the site is unreachable.
./packages/remotepc-host/sync-urls.sh || echo "  warning: could not refresh remotepc-host URLs; keeping existing"

echo "=== Updating sources with nvfetcher ==="
ensure_nix_prefetch_git
nvfetcher

echo ""
# Auto-detect and fix packages that need fetchSubmodules
fix_all_submodules

echo ""
echo "=== Updating .source-version for changed packages ==="

# Update .source-version file for any package whose version changed
# This triggers the per-package GitHub workflow even if default.nix didn't change
for pkg in $(jq -r 'keys[]' _sources/generated.json 2>/dev/null); do
  pkg_dir="packages/$pkg"
  if [ -d "$pkg_dir" ] && version_changed "$pkg"; then
    new_ver=$(jq -r ".[\"$pkg\"].version // empty" "_sources/generated.json")
    echo "$new_ver" > "$pkg_dir/.source-version"
    echo "  $pkg: updated .source-version to $new_ver"
  fi
done

echo ""
echo "=== Initializing new npm packages ==="

# Find npm packages in nvfetcher.toml and initialize if missing package-lock.json
start_dir="$PWD"
while IFS= read -r pkg; do
  pkg_dir="packages/$pkg"

  # Skip if package-lock.json already exists
  if [ -f "$pkg_dir/package-lock.json" ]; then
    continue
  fi

  # Get npm package name from nvfetcher.toml (only if src.cmd contains "npm view")
  src_cmd=$(grep -A1 "^\[$pkg\]" nvfetcher.toml | grep "src.cmd" || echo "")
  if ! echo "$src_cmd" | grep -q "npm view"; then
    continue  # Not an npm package
  fi
  npm_pkg=$(echo "$src_cmd" | sed 's/.*npm view \([^ ]*\) version.*/\1/')

  if [ -z "$npm_pkg" ]; then
    continue  # Not an npm package
  fi

  # Get version from generated.json
  version=$(jq -r ".[\"$pkg\"].version // empty" "_sources/generated.json")

  if [ -z "$version" ]; then
    echo "  $pkg: no version in generated.json, run nvfetcher first"
    continue
  fi

  echo "  $pkg: initializing new npm package..."

  # Create package directory if needed
  mkdir -p "$pkg_dir"

  # Generate package-lock.json
  cd "$pkg_dir"
  echo '{}' > package.json
  npm install --package-lock-only "$npm_pkg@$version" >/dev/null 2>&1 || true
  rm -f package.json
  cd "$start_dir"

  # Calculate the hash
  hash=$(prefetch-npm-deps "$pkg_dir/package-lock.json" 2>&1 | tail -1)

  if [ -n "$hash" ] && [[ "$hash" == sha256-* ]]; then
    echo "  $pkg: package-lock.json created"
    echo "  $pkg: npmDepsHash = \"$hash\""

    # Auto-update default.nix if it exists and has npmDepsHash
    if [ -f "$pkg_dir/default.nix" ] && grep -q "npmDepsHash" "$pkg_dir/default.nix"; then
      sed -i "s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"$hash\"|" "$pkg_dir/default.nix"
      echo "  $pkg: updated npmDepsHash in default.nix"
    fi
  else
    echo "  $pkg: failed to generate package-lock.json"
  fi
done < <(sed -n 's/^\[\([^]]*\)\]/\1/p' nvfetcher.toml)

echo ""
echo "=== Checking for cargoHash updates ==="

# Function to update cargoHash for a Rust package
update_cargo_hash() {
  local pkg="$1"
  local pkg_file="packages/$pkg/default.nix"

  echo "  $pkg: version changed, updating cargoHash..."

  # Try to build and capture output
  local build_output
  if build_output=$(nix build --no-link ".#$pkg" 2>&1); then
    echo "  $pkg: cargoHash is up to date"
    return 0
  fi

  # Check if the failure was due to hash mismatch.
  # Keep this non-fatal: grep may return no matches for unrelated build failures.
  local new_hash
  new_hash=$(echo "$build_output" | sed -nE 's/^[[:space:]]*got:[[:space:]]*([^[:space:]]+).*$/\1/p' | head -1 || true)

  if [ -n "$new_hash" ]; then
    echo "  $pkg: updating cargoHash to $new_hash"
    sed -i -E "s#cargoHash = (\"sha256-[^\"]*\"|null)#cargoHash = \"$new_hash\"#" "$pkg_file"
  elif is_toolchain_too_old "$build_output"; then
    skip_update_until_toolchain_updates "$pkg"
    return 0
  else
    echo "  $pkg: build failed for unknown reason"
    echo "$build_output" | tail -20
    return 1
  fi
}

# Update Rust packages only if version changed
# Detect Rust packages by presence of cargoHash in default.nix
for pkg_dir in packages/*/; do
  pkg=$(basename "$pkg_dir")
  pkg_file="$pkg_dir/default.nix"
  if [ -f "$pkg_file" ] && grep -q "cargoHash" "$pkg_file"; then
    if version_changed "$pkg"; then
      update_cargo_hash "$pkg"
    else
      echo "  $pkg: version unchanged, skipping cargoHash check"
    fi
  fi
done

echo ""
echo "=== Checking for caddy.withPlugins hash updates ==="

for pkg_dir in packages/*/; do
  pkg=$(basename "$pkg_dir")
  pkg_file="$pkg_dir/default.nix"
  [ -f "$pkg_file" ] || continue
  grep -q "caddy.withPlugins" "$pkg_file" || continue

  if [ -x "$pkg_dir/update.sh" ]; then
    "$pkg_dir/update.sh"
  else
    echo "  $pkg: missing package updater for caddy.withPlugins hash"
    exit 1
  fi
done

echo ""
echo "=== Checking for vendorHash updates ==="

# Resolve the buildable flake attribute for a given Go hash variable.
# Standard packages name their hash `vendorHash` and expose `.#<pkg>`.
# Multi-derivation packages (e.g. zabbix74) are flattened by flake.nix to
# `.#<pkg>.<sub>` and name their hashes `<sub>VendorHash` (a callPackage arg).
vendor_hash_target() {
  local pkg="$1" var="$2"
  if [ "$var" = "vendorHash" ]; then
    printf '%s' "$pkg"
  else
    # agent2VendorHash -> sub-attr "agent2" -> ".#zabbix74.agent2"
    printf '%s.%s' "$pkg" "${var%VendorHash}"
  fi
}

# Update one Go vendor-hash variable, rewriting it in every .nix file of the
# package. Handles both `vendorHash = "..."` (attr) and `agent2VendorHash ? "..."`
# (function default) by preserving whichever assignment operator is present.
update_one_vendor_hash() {
  local pkg="$1" var="$2"
  local target
  target=$(vendor_hash_target "$pkg" "$var")

  echo "  $pkg: checking $var (build target .#\"$target\")"

  local build_output
  if build_output=$(nix build --no-link ".#\"$target\"" 2>&1); then
    echo "  $pkg: $var is up to date"
    return 0
  fi

  # Keep this non-fatal: grep may return no matches for unrelated build failures.
  local new_hash
  new_hash=$(echo "$build_output" | sed -nE 's/^[[:space:]]*got:[[:space:]]*([^[:space:]]+).*$/\1/p' | head -1 || true)

  if [ -n "$new_hash" ]; then
    echo "  $pkg: updating $var to $new_hash"
    local f
    for f in "packages/$pkg"/*.nix; do
      [ -f "$f" ] || continue
      grep -qE "(^|[^A-Za-z0-9_])${var}[[:space:]]*[?=]" "$f" || continue
      sed -i -E "s#((^|[[:space:]])${var}[[:space:]]*[?=][[:space:]]*)(\"sha256-[^\"]*\"|null)#\\1\"${new_hash}\"#g" "$f"
    done
  elif is_toolchain_too_old "$build_output"; then
    skip_update_until_toolchain_updates "$pkg"
  else
    echo "  $pkg: build failed for unknown reason while checking $var"
    echo "$build_output" | tail -20
  fi
}

# Update Go packages only if version changed.
# Detect Go hashes by any variable named `vendorHash` or `<name>VendorHash`.
# A single package may define several (one per sub-derivation).
for pkg_dir in packages/*/; do
  pkg=$(basename "$pkg_dir")
  pkg_file="$pkg_dir/default.nix"
  [ -f "$pkg_file" ] || continue
  grep -qE '[A-Za-z0-9_]*[Vv]endorHash' "$pkg_file" || continue

  if ! version_changed "$pkg"; then
    echo "  $pkg: version unchanged, skipping vendorHash check"
    continue
  fi

  while IFS= read -r var; do
    update_one_vendor_hash "$pkg" "$var"
  done < <(grep -oE '[A-Za-z0-9_]*[Vv]endorHash' "$pkg_file" | sort -u)
done

echo ""
echo "=== Checking for npmDepsHash updates ==="

# Function to update npmDepsHash for npm packages
update_npm_hash() {
  local pkg="$1"
  local pkg_dir="packages/$pkg"
  local pkg_file="$pkg_dir/default.nix"
  local start_dir="$PWD"
  local lock_backup
  lock_backup=$(mktemp)

  # Get the npm package name from nvfetcher.toml (extract from src.cmd line)
  local npm_pkg
  npm_pkg=$(grep -A1 "^\[$pkg\]" nvfetcher.toml | grep "src.cmd" | sed 's/.*npm view \([^ ]*\) version.*/\1/' || echo "")

  if [ -z "$npm_pkg" ]; then
    echo "  $pkg: could not determine npm package name from nvfetcher.toml"
    return 0
  fi

  # Get the version from generated.json
  local version
  version=$(jq -r ".[\"$pkg\"].version // empty" "_sources/generated.json")

  if [ -z "$version" ]; then
    echo "  $pkg: could not determine version"
    return 0
  fi

  echo "  $pkg: version changed, updating package-lock.json for version $version"

  # Update package-lock.json
  cd "$pkg_dir"
  if [ -f package-lock.json ]; then
    cp package-lock.json "$lock_backup"
  else
    rm -f "$lock_backup"
  fi
  rm -f package.json package-lock.json 2>/dev/null || true
  echo '{}' > package.json
  local npm_output
  npm_output=$(npm install --package-lock-only "$npm_pkg@$version" 2>&1) || true
  rm -f package.json

  # Get new hash (prefetch-npm-deps outputs hash on last line of stderr)
  local new_hash
  new_hash=""
  if [ -f package-lock.json ]; then
    new_hash=$(prefetch-npm-deps package-lock.json 2>&1 | tail -1)
  fi

  cd "$start_dir"

  if [ -n "$new_hash" ] && [[ "$new_hash" == sha256-* ]]; then
    echo "  $pkg: updating npmDepsHash to $new_hash"
    sed -i "s|npmDepsHash = \"sha256-.*\"|npmDepsHash = \"$new_hash\"|" "$pkg_file"
  elif is_toolchain_too_old "$npm_output"; then
    if [ -f "$lock_backup" ]; then
      cp "$lock_backup" "$pkg_dir/package-lock.json"
    else
      rm -f "$pkg_dir/package-lock.json"
    fi
    skip_update_until_toolchain_updates "$pkg"
  else
    if [ -f "$lock_backup" ]; then
      cp "$lock_backup" "$pkg_dir/package-lock.json"
    fi
    echo "  $pkg: could not determine npmDepsHash"
  fi

  rm -f "$lock_backup"
}

# Update npm packages only if version changed
# Detect npm packages by presence of npmDepsHash in default.nix
for pkg_dir in packages/*/; do
  pkg=$(basename "$pkg_dir")
  pkg_file="$pkg_dir/default.nix"
  if [ -f "$pkg_file" ] && grep -q "npmDepsHash" "$pkg_file"; then
    if version_changed "$pkg"; then
      update_npm_hash "$pkg"
    else
      echo "  $pkg: version unchanged, skipping npmDepsHash check"
    fi
  fi
done

echo ""
echo "=== Update complete ==="
echo "Review changes and test builds before committing."
