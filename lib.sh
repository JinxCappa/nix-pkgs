#!/usr/bin/env bash
# Shared functions for nix-pkgs scripts

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
  if grep -A20 "^  $pkg = {" "$generated_nix" | grep -q "fetchSubmodules = true"; then
    echo "  $pkg: fetchSubmodules already true"
    return 0
  fi

  # Extract info from generated.nix - handle both fetchgit and fetchFromGitHub
  local pkg_block url rev owner repo
  pkg_block=$(grep -A20 "^  $pkg = {" "$generated_nix")

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
  prefetch_output=$(nix shell nixpkgs#nix-prefetch-git -c nix-prefetch-git --url "$url" --rev "$rev" --fetch-submodules 2>/dev/null)

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
    if ! grep -A20 "^  $pkg = {" "$generated_nix" | grep -qE "(fetchgit|fetchFromGitHub)"; then
      continue
    fi

    fix_submodules_for_package "$pkg" "$generated_nix"
  done
}
