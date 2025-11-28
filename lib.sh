#!/usr/bin/env bash
# Shared functions for nix-pkgs scripts

# Find a usable nix-prefetch-git executable path.
# Supports both classic "nix-prefetch-git" and version-suffixed binaries.
find_nix_prefetch_git_exe() {
  if command -v nix-prefetch-git >/dev/null 2>&1; then
    command -v nix-prefetch-git
    return 0
  fi

  local dir candidate
  local -a _path_dirs
  IFS=':' read -r -a _path_dirs <<< "${PATH:-}"
  for dir in "${_path_dirs[@]}"; do
    [ -d "$dir" ] || continue
    for candidate in "$dir"/nix-prefetch-git-*; do
      [ -x "$candidate" ] || continue
      echo "$candidate"
      return 0
    done
  done

  return 1
}

# Ensure "nix-prefetch-git" is callable, even when nixpkgs only ships a
# version-suffixed binary (e.g. nix-prefetch-git-26.05pre-git).
ensure_nix_prefetch_git() {
  local prefetch_exe out shim_dir

  prefetch_exe="$(find_nix_prefetch_git_exe || true)"
  if [ -z "$prefetch_exe" ]; then
    out="$(nix build --no-link --print-out-paths nixpkgs#nix-prefetch-git 2>/dev/null | tail -1 || true)"
    if [ -n "$out" ] && [ -d "$out/bin" ]; then
      for prefetch_exe in "$out/bin"/nix-prefetch-git "$out/bin"/nix-prefetch-git-*; do
        [ -x "$prefetch_exe" ] || continue
        break
      done
    fi
  fi

  if [ -z "${prefetch_exe:-}" ] || [ ! -x "$prefetch_exe" ]; then
    echo "Error: could not find a usable nix-prefetch-git executable" >&2
    return 1
  fi

  shim_dir="${TMPDIR:-/tmp}/nix-prefetch-git-shim-$$"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/nix-prefetch-git" <<EOF
#!/usr/bin/env bash
exec "$prefetch_exe" "\$@"
EOF
  chmod +x "$shim_dir/nix-prefetch-git"
  export PATH="$shim_dir:$PATH"
}

# Check if a GitHub repo has submodules by looking for .gitmodules file
# Usage: has_submodules "owner" "repo" "rev"
has_submodules() {
  local owner="$1"
  local repo="$2"
  local rev="$3"

  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://raw.githubusercontent.com/$owner/$repo/$rev/.gitmodules")

  [[ "$status_code" == "200" ]]
}

# Extract a single package block from generated.nix
# Usage: extract_pkg_block "package_name" "generated.nix"
extract_pkg_block() {
  local pkg="$1" file="$2"
  awk "/^  ${pkg} = \\{/,/^  \\};/" "$file"
}

# Extract GitHub owner/repo from a git URL
# Usage: parse_github_url "https://github.com/owner/repo.git"
# Returns: "owner repo" (space-separated)
parse_github_url() {
  local url="$1"
  echo "$url" | sed -E 's|.*github\.com[/:]([^/]+)/([^/.]+)(\.git)?.*|\1 \2|'
}

# Fix fetchSubmodules for a package in generated.nix
# Usage: fix_submodules_for_package "package_name"
fix_submodules_for_package() {
  local pkg="$1"
  local generated_nix="${2:-_sources/generated.nix}"

  # Check if package exists in generated.nix
  if ! grep -q "^  $pkg = {" "$generated_nix"; then
    echo "  $pkg: not found in generated.nix, skipping"
    return 0
  fi

  # Check if already has fetchSubmodules = true
  local pkg_block
  pkg_block=$(extract_pkg_block "$pkg" "$generated_nix")

  if echo "$pkg_block" | grep -q "fetchSubmodules = true"; then
    echo "  $pkg: fetchSubmodules already true"
    return 0
  fi

  # Extract info from generated.nix - handle both fetchgit and fetchFromGitHub
  local url rev owner repo

  rev=$(echo "$pkg_block" | grep -E "rev = " | head -1 | sed 's/.*rev = "\([^"]*\)".*/\1/')

  # Try to get URL directly (fetchgit style)
  url=$(echo "$pkg_block" | grep -E "url = " | head -1 | sed 's/.*url = "\([^"]*\)".*/\1/' || true)

  if [ -n "$url" ]; then
    # Parse owner/repo from URL
    read -r owner repo <<< "$(parse_github_url "$url")"
  else
    # Try fetchFromGitHub style (owner/repo fields)
    owner=$(echo "$pkg_block" | grep -E "owner = " | head -1 | sed 's/.*owner = "\([^"]*\)".*/\1/' || true)
    repo=$(echo "$pkg_block" | grep -E "repo = " | head -1 | sed 's/.*repo = "\([^"]*\)".*/\1/' || true)
    url="https://github.com/$owner/$repo.git"
  fi

  if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$rev" ]; then
    echo "  $pkg: could not extract GitHub info, skipping"
    return 0
  fi

  # Check if this repo actually has submodules
  if ! has_submodules "$owner" "$repo" "$rev"; then
    return 0  # No submodules, nothing to fix
  fi

  echo "  $pkg: detected submodules, fixing fetchSubmodules..."

  # Prefetch with submodules to get correct hash
  echo "  $pkg: prefetching with submodules (this may take a while)..."
  local prefetch_output
  ensure_nix_prefetch_git
  prefetch_output=$(nix-prefetch-git --url "$url" --rev "$rev" --fetch-submodules 2>/dev/null)

  local new_hash
  new_hash=$(echo "$prefetch_output" | jq -r '.hash // .sha256' 2>/dev/null)

  if [ -z "$new_hash" ] || [ "$new_hash" = "null" ]; then
    echo "  $pkg: failed to get hash with submodules"
    return 1
  fi

  echo "  $pkg: new hash = $new_hash"

  # Update generated.nix: change fetchSubmodules to true and update hash
  # Use perl for multi-line editing (use # as delimiter to avoid conflicts with / in hash)
  perl -i -p0e "s#($pkg = \\{.*?fetchSubmodules = )false#\${1}true#s" "$generated_nix"
  perl -i -p0e "s#($pkg = \\{.*?sha256 = \")sha256-[^\"]*#\${1}$new_hash#s" "$generated_nix"

  echo "  $pkg: fixed fetchSubmodules and updated hash"
}

# Auto-detect and fix submodules for all packages in generated.nix
# Usage: fix_all_submodules [generated_nix_path]
fix_all_submodules() {
  local generated_nix="${1:-_sources/generated.nix}"

  echo "=== Checking for packages with submodules ==="

  # Get list of packages from generated.nix
  local packages
  packages=$(grep -E "^  [a-zA-Z0-9_-]+ = \{" "$generated_nix" | sed 's/^  \([^ ]*\) = {.*/\1/')

  for pkg in $packages; do
    # Skip packages that don't use fetchgit/fetchFromGitHub
    if ! extract_pkg_block "$pkg" "$generated_nix" | grep -qE "(fetchgit|fetchFromGitHub)"; then
      continue
    fi

    fix_submodules_for_package "$pkg" "$generated_nix"
  done
}
