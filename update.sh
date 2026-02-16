#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(realpath "$0")")"

# Source shared functions
source ./lib.sh

# Cache current versions from generated.nix BEFORE nvfetcher runs
declare -A OLD_VERSIONS
cache_old_versions() {
  # Get package list dynamically from generated.json
  local packages
  packages=$(jq -r 'keys[]' _sources/generated.json 2>/dev/null || echo "")
  for pkg in $packages; do
    # Parse version from generated.nix (can't use nix eval - it's a function)
    OLD_VERSIONS[$pkg]=$(grep -A2 "$pkg = {" _sources/generated.nix | grep 'version' | sed 's/.*version = "\([^"]*\)".*/\1/' || echo "")
  done
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
  if build_output=$(nix build ".#$pkg" 2>&1); then
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
echo "=== Checking for vendorHash updates ==="

# Function to update vendorHash for a Go package
update_vendor_hash() {
  local pkg="$1"
  local pkg_file="packages/$pkg/default.nix"

  echo "  $pkg: version changed, updating vendorHash..."

  # Try to build and capture output
  local build_output
  if build_output=$(nix build ".#$pkg" 2>&1); then
    echo "  $pkg: vendorHash is up to date"
    return 0
  fi

  # Check if the failure was due to hash mismatch.
  # Keep this non-fatal: grep may return no matches for unrelated build failures.
  local new_hash
  new_hash=$(echo "$build_output" | sed -nE 's/^[[:space:]]*got:[[:space:]]*([^[:space:]]+).*$/\1/p' | head -1 || true)

  if [ -n "$new_hash" ]; then
    echo "  $pkg: updating vendorHash to $new_hash"
    sed -i -E "s#vendorHash = (\"sha256-[^\"]*\"|null)#vendorHash = \"$new_hash\"#" "$pkg_file"
  else
    echo "  $pkg: build failed for unknown reason"
    echo "$build_output" | tail -20
    return 1
  fi
}

# Update Go packages only if version changed
# Detect Go packages by presence of vendorHash in default.nix
for pkg_dir in packages/*/; do
  pkg=$(basename "$pkg_dir")
  pkg_file="$pkg_dir/default.nix"
  if [ -f "$pkg_file" ] && grep -q "vendorHash" "$pkg_file"; then
    if version_changed "$pkg"; then
      update_vendor_hash "$pkg"
    else
      echo "  $pkg: version unchanged, skipping vendorHash check"
    fi
  fi
done

echo ""
echo "=== Checking for npmDepsHash updates ==="

# Function to update npmDepsHash for npm packages
update_npm_hash() {
  local pkg="$1"
  local pkg_dir="packages/$pkg"
  local pkg_file="$pkg_dir/default.nix"
  local start_dir="$PWD"

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
  rm -f package.json package-lock.json 2>/dev/null || true
  echo '{}' > package.json
  npm install --package-lock-only "$npm_pkg@$version" >/dev/null 2>&1 || true
  rm -f package.json

  # Get new hash (prefetch-npm-deps outputs hash on last line of stderr)
  local new_hash
  new_hash=$(prefetch-npm-deps package-lock.json 2>&1 | tail -1)

  cd "$start_dir"

  if [ -n "$new_hash" ] && [[ "$new_hash" == sha256-* ]]; then
    echo "  $pkg: updating npmDepsHash to $new_hash"
    sed -i "s|npmDepsHash = \"sha256-.*\"|npmDepsHash = \"$new_hash\"|" "$pkg_file"
  else
    echo "  $pkg: could not determine npmDepsHash"
  fi
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
