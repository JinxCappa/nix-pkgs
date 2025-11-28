#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Source shared functions
source "$SCRIPT_DIR/lib.sh"

# Cleanup function to reset repo on failure
cleanup() {
  echo ""
  echo "=== Resetting repository ==="
  git checkout -- . 2>/dev/null || true
  git clean -fd 2>/dev/null || true
  echo "Repository has been reset to clean state."
}
trap 'cleanup' ERR

# Check if package is available on a specific system using lib.meta.availableOn
is_available_on() {
  local pkg=$1
  local system=$2
  nix eval --impure --expr "let pkgs = import <nixpkgs> {}; in pkgs.lib.meta.availableOn { system = \"$system\"; } pkgs.$pkg" 2>/dev/null || echo "false"
}

# Get list of supported GitHub runners for a package
get_supported_runners() {
  local pkg=$1
  local runners=()
  local available

  for system in x86_64-linux aarch64-linux x86_64-darwin aarch64-darwin; do
    available=$(is_available_on "$pkg" "$system")

    if [[ "$available" == "true" ]]; then
      case "$system" in
        x86_64-linux) runners+=("ubuntu-24.04") ;;
        aarch64-linux) runners+=("ubuntu-22.04-arm") ;;
        x86_64-darwin) runners+=("macos-15-intel") ;;
        aarch64-darwin) runners+=("macos-15") ;;
      esac
    fi
  done

  # Fallback to Linux runners if none detected
  if [[ ${#runners[@]} -eq 0 ]]; then
    runners=("ubuntu-24.04" "ubuntu-22.04-arm")
  fi

  echo "${runners[@]}"
}

# Parse arguments
PACKAGE=""
DO_COMMIT=false
COMMIT_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --commit)
      DO_COMMIT=true
      ;;
    --commit-only)
      COMMIT_ONLY=true
      ;;
    -*)
      echo "Unknown option: $arg"
      exit 1
      ;;
    *)
      PACKAGE="$arg"
      ;;
  esac
done

PKG_DIR="$SCRIPT_DIR/packages/$PACKAGE"

if [[ -z "$PACKAGE" ]]; then
  echo "Usage: ./add-package.sh <package-name> [--commit]"
  echo "       ./add-package.sh --commit-only <package-name>"
  echo ""
  echo "Options:"
  echo "  --commit       Automatically commit changes after adding package"
  echo "  --commit-only  Only commit changes for an existing package (skip add)"
  echo ""
  echo "Examples:"
  echo "  ./add-package.sh ripgrep --commit"
  echo "  ./add-package.sh --commit-only ripgrep"
  exit 1
fi

# Check for clean repo state (skip for --commit-only mode)
if [[ "$COMMIT_ONLY" != "true" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: Repository has uncommitted changes."
    echo "Please commit or stash your changes before adding a new package."
    echo ""
    echo "Uncommitted files:"
    git status --short
    exit 1
  fi

  # Pull latest changes (flake may have been updated by CI)
  echo "=== Pulling latest changes ==="
  git pull --ff-only
fi

# Handle --commit-only mode
if [[ "$COMMIT_ONLY" == "true" ]]; then
  if [[ ! -d "$PKG_DIR" ]]; then
    echo "Error: Package '$PACKAGE' does not exist at $PKG_DIR"
    exit 1
  fi

  echo "=== Generating commit for $PACKAGE ==="
  git add "packages/$PACKAGE/" "nvfetcher.toml" "_sources/" ".github/workflows/$PACKAGE.yaml" 2>/dev/null || true

  COMMIT_MSG=$(claude --dangerously-skip-permissions --print "
Generate a concise git commit message for adding the package '$PACKAGE' to this nix-pkgs repository.

The commit should:
- Be in conventional commit format (e.g., 'feat: add ripgrep package')
- Include a brief description of what was added
- NOT mention Claude, Claude Code, Anthropic, AI, or LLM anywhere
- Be professional and match typical open source commit style

Output ONLY the commit message, nothing else.
")

  git commit -m "$COMMIT_MSG"
  echo "Committed: $COMMIT_MSG"
  exit 0
fi

if [[ -d "$PKG_DIR" ]]; then
  echo "Error: Package '$PACKAGE' already exists at $PKG_DIR"
  exit 1
fi

# Step 1: Locate package in nixpkgs
echo "=== Locating $PACKAGE in nixpkgs ==="

# Try pkgs-by-name direct path first (handles wrapper packages correctly)
PREFIX="${PACKAGE:0:2}"
DIRECT_PATH="pkgs/by-name/$PREFIX/$PACKAGE"

if gh api "repos/NixOS/nixpkgs/contents/$DIRECT_PATH" &>/dev/null; then
  echo "  Found at: $DIRECT_PATH (pkgs-by-name)"
  NIXPKGS_REL_PATH="$DIRECT_PATH"
else
  # Fall back to meta.position for legacy package locations
  PKG_PATH=$(nix eval --raw "nixpkgs#$PACKAGE.meta.position" 2>/dev/null | cut -d: -f1) || true

  if [[ -z "$PKG_PATH" ]]; then
    echo "Error: Could not locate $PACKAGE in nixpkgs"
    exit 1
  fi

  NIXPKGS_REL_PATH=$(echo "$PKG_PATH" | grep -o 'pkgs/.*' | xargs dirname)
  echo "  Found at: $NIXPKGS_REL_PATH (via meta.position)"
fi

# Step 2: Download entire package directory from GitHub
echo "=== Downloading package files from nixpkgs ==="
mkdir -p "$PKG_DIR"
echo "  nixpkgs path: $NIXPKGS_REL_PATH"

# Fetch all files in the package directory
gh api "repos/NixOS/nixpkgs/contents/$NIXPKGS_REL_PATH" --jq '.[] | select(.type == "file") | .download_url' | while read -r url; do
  filename=$(basename "$url")
  echo "  Downloading $filename..."
  curl -sL "$url" -o "$PKG_DIR/$filename"
done

# Rename package.nix to default.nix if needed (pkgs-by-name convention)
if [[ -f "$PKG_DIR/package.nix" && ! -f "$PKG_DIR/default.nix" ]]; then
  echo "  Renaming package.nix to default.nix (pkgs-by-name convention)"
  mv "$PKG_DIR/package.nix" "$PKG_DIR/default.nix"
fi

# Step 3: Detect unfree license (check package AND dependencies)
echo "=== Checking license ==="
# Try a dry-run build on x86_64-linux to check for unfree deps
# We use x86_64-linux with --system since the package might not support the current platform
# The dry-run will fail with "unfree license" if any dependency is unfree
BUILD_CHECK=$(nix build --dry-run --no-link --system x86_64-linux "nixpkgs#$PACKAGE" 2>&1 || true)
if echo "$BUILD_CHECK" | grep -q "unfree license"; then
  echo "  Package or dependencies require unfree license - will add special flags to workflow"
  UNFREE=true
else
  echo "  Package is free/open source"
  UNFREE=false
fi

# Step 4 & 5: Use Claude to configure nvfetcher and adapt the nix file
echo "=== Using Claude to configure package ==="
claude --dangerously-skip-permissions --print "
I'm adding the package '$PACKAGE' to this nix-pkgs repository.

The package files are now in: packages/$PACKAGE/
The main derivation is: packages/$PACKAGE/default.nix

Please do the following:
1. Read the derivation and understand its source (fetchFromGitHub, fetchurl, etc.)
2. Add an appropriate entry to nvfetcher.toml (keep alphabetical order) for tracking the package source
3. Modify packages/$PACKAGE/default.nix to:
   - Add 'sources' parameter
   - Use sources.$PACKAGE.src instead of the fetch function
   - Use sources.$PACKAGE.version (strip 'v' prefix if needed with lib.removePrefix)
   - Replace any hash fields (cargoHash, vendorHash, npmDepsHash) with lib.fakeHash (the script will auto-fix these)
   - Remove unused fetch function imports (fetchFromGitHub, fetchurl, etc.)
   - Remove any nix-update-script if present
4. If there are patches or other files, ensure they're still referenced correctly
5. After making changes, show me what nvfetcher entry you added

Important: If this package seems too complex (multiple outputs, complex callPackage chains, platform-specific overrides), warn me and explain what manual review is needed.
"

# Step 6: Create GitHub workflow
echo "=== Creating GitHub workflow ==="

# Determine supported platforms
echo "  Checking platform support..."
SUPPORTED_RUNNERS=($(get_supported_runners "$PACKAGE"))
echo "  Supported runners: ${SUPPORTED_RUNNERS[*]}"

# Check if macOS is supported (for conditional bash install step)
HAS_MACOS=false
for runner in "${SUPPORTED_RUNNERS[@]}"; do
  if [[ "$runner" == macos-* ]]; then
    HAS_MACOS=true
    break
  fi
done

if [[ "$UNFREE" == "true" ]]; then
  BUILD_CMD='nix build --no-link --print-out-paths -L --fallback --impure .#'"$PACKAGE"' | xargs -I {} attic push "ci:$ATTIC_CACHE" {};'
  BUILD_ENV="
        env:
          NIXPKGS_ALLOW_UNFREE: 1"
else
  BUILD_CMD='nix build --no-link --print-out-paths -L --fallback .#'"$PACKAGE"' | xargs -I {} attic push "ci:$ATTIC_CACHE" {};'
  BUILD_ENV=""
fi

# Generate the matrix os list
MATRIX_OS=""
for runner in "${SUPPORTED_RUNNERS[@]}"; do
  MATRIX_OS+="          - $runner
"
done

# Only include macOS bash install step if macOS is a supported platform
if [[ "$HAS_MACOS" == "true" ]]; then
  MACOS_BASH_STEP="
      - name: Install current Bash on macOS
        if: runner.os == 'macOS'
        run: |
          command -v brew && brew install bash || true"
else
  MACOS_BASH_STEP=""
fi

cat > "$SCRIPT_DIR/.github/workflows/$PACKAGE.yaml" << EOF
name: $PACKAGE
on:
  push:
    branches:
      - main
    paths:
      - packages/$PACKAGE/**
env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ghcr.io/\${{ github.repository }}
jobs:
  build:
    strategy:
      matrix:
        os:
$MATRIX_OS    permissions:
      contents: write
    runs-on: \${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4.2.2$MACOS_BASH_STEP

      - uses: nixbuild/nix-quick-install-action@v30

      - name: Install Attic client
        run: |
          nix profile install "nixpkgs#attic-client"
          echo "\$HOME/.nix-profile/bin" >> "\$GITHUB_PATH"

      - name: Configure Attic
        continue-on-error: true
        run: |
          export PATH=\$HOME/.nix-profile/bin:\$PATH
          attic login --set-default ci "\$ATTIC_SERVER" "\$ATTIC_TOKEN"
          attic use "\$ATTIC_CACHE"
          if [ -n "\$ATTIC_TOKEN" ]; then
            echo ATTIC_CACHE=\$ATTIC_CACHE >>\$GITHUB_ENV
          fi
        env:
          ATTIC_SERVER: \${{ secrets.ATTIC_SERVER }}
          ATTIC_CACHE: \${{ secrets.ATTIC_CACHE }}
          ATTIC_TOKEN: \${{ secrets.ATTIC_TOKEN }}

      - name: Build packages
        run: |
          set -euo pipefail
          export PATH=\$HOME/.nix-profile/bin:\$PATH
          $BUILD_CMD$BUILD_ENV
EOF

echo "  Created .github/workflows/$PACKAGE.yaml"

# Step 7: Run nvfetcher to generate sources
echo "=== Running nvfetcher ==="
ensure_nix_prefetch_git
nvfetcher

# Step 7.5: Auto-detect and fix submodules if needed
fix_submodules_for_package "$PACKAGE"

# Step 7.6: Create .source-version file to track source version
VERSION=$(jq -r ".[\"$PACKAGE\"].version // empty" "_sources/generated.json")
if [ -n "$VERSION" ]; then
  echo "$VERSION" > "$PKG_DIR/.source-version"
  echo "  Created .source-version with $VERSION"
fi

# Step 8: Verify build and auto-fix hash mismatches
echo "=== Verifying package builds ==="

# Check if package is available on current system
CURRENT_SYSTEM=$(nix config show system)
AVAILABLE_ON_CURRENT=$(is_available_on "$PACKAGE" "$CURRENT_SYSTEM")

BUILD_FLAGS="--no-link"
if [[ "$UNFREE" == "true" ]]; then
  BUILD_FLAGS="$BUILD_FLAGS --impure"
  export NIXPKGS_ALLOW_UNFREE=1
fi

# If package doesn't support current system, find an alternative build target
if [[ "$AVAILABLE_ON_CURRENT" == "false" ]]; then
  echo "  Package '$PACKAGE' is not available on $CURRENT_SYSTEM"

  # On aarch64-darwin, prefer aarch64-linux (linux-builder native) over x86_64-linux (requires Rosetta)
  if [[ "$CURRENT_SYSTEM" == "aarch64-darwin" ]]; then
    AVAILABLE_ON_AARCH64_LINUX=$(is_available_on "$PACKAGE" "aarch64-linux")
    if [[ "$AVAILABLE_ON_AARCH64_LINUX" == "true" ]]; then
      echo "  Building for aarch64-linux to verify hashes..."
      BUILD_TARGET="path:.#packages.aarch64-linux.$PACKAGE"
    else
      echo "  Building for x86_64-linux to verify hashes (requires Rosetta)..."
      BUILD_TARGET="path:.#packages.x86_64-linux.$PACKAGE"
    fi
  else
    echo "  Building for x86_64-linux to verify hashes..."
    BUILD_TARGET="path:.#packages.x86_64-linux.$PACKAGE"
  fi
else
  BUILD_TARGET=".#$PACKAGE"
fi

MAX_HASH_RETRIES=5
RETRY_COUNT=0

while true; do
  echo "  Attempting build (attempt $((RETRY_COUNT + 1))/$MAX_HASH_RETRIES)..."
  BUILD_OUTPUT=$(nix build $BUILD_FLAGS "$BUILD_TARGET" 2>&1) && break

  # Check if it's a hash mismatch error
  if echo "$BUILD_OUTPUT" | grep -q "hash mismatch in fixed-output derivation"; then
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [[ $RETRY_COUNT -ge $MAX_HASH_RETRIES ]]; then
      echo ""
      echo "=== BUILD FAILED after $MAX_HASH_RETRIES hash fix attempts ==="
      echo "$BUILD_OUTPUT"
      cleanup
      exit 1
    fi

    # Extract the correct hash from the error message
    CORRECT_HASH=$(echo "$BUILD_OUTPUT" | grep -o "got:.*" | head -1 | sed 's/got:[[:space:]]*//')
    # Extract the wrong hash that needs to be replaced
    WRONG_HASH=$(echo "$BUILD_OUTPUT" | grep -o "specified:.*" | head -1 | sed 's/specified:[[:space:]]*//')

    if [[ -n "$CORRECT_HASH" && -n "$WRONG_HASH" ]]; then
      echo "  Hash mismatch detected, auto-fixing..."
      echo "    Old: $WRONG_HASH"
      echo "    New: $CORRECT_HASH"

      # Check if the file uses lib.fakeHash (which evaluates to the fake hash value)
      FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
      if [[ "$WRONG_HASH" == "$FAKE_HASH" ]] && grep -q "lib.fakeHash" "$PKG_DIR/default.nix"; then
        # Replace lib.fakeHash with the actual hash string
        sed -i '' "s|lib.fakeHash|\"$CORRECT_HASH\"|g" "$PKG_DIR/default.nix"
      else
        # Replace the hash string directly
        sed -i '' "s|$WRONG_HASH|$CORRECT_HASH|g" "$PKG_DIR/default.nix"
      fi

      # Check if there are any more fake hashes to fix
      if ! grep -q "lib.fakeHash" "$PKG_DIR/default.nix"; then
        echo "  All hashes fixed - skipping full build (will be verified by GitHub Actions)"
        break
      fi
      continue
    fi
  fi

  # Not a hash mismatch error - check if it's a build error we can ignore
  # (package successfully fetched sources but can't compile on this system)
  if [[ "$AVAILABLE_ON_CURRENT" == "false" ]]; then
    # For cross-system builds, we only care about hash verification
    # If we got past hash mismatches, the hashes are correct
    if ! grep -q "lib.fakeHash" "$PKG_DIR/default.nix"; then
      echo "  Hashes verified - skipping full build (will be verified by GitHub Actions)"
      break
    fi
  fi

  # Real failure
  echo ""
  echo "=== BUILD FAILED ==="
  echo "$BUILD_OUTPUT"
  echo ""
  echo "The package '$PACKAGE' could not be added due to build errors."
  cleanup
  exit 1
done

echo "  Build verification passed"

# Step 9: Optionally commit changes
if [[ "$DO_COMMIT" == "true" ]]; then
  echo "=== Generating commit ==="
  git add "packages/$PACKAGE/" "nvfetcher.toml" "_sources/" ".github/workflows/$PACKAGE.yaml"

  COMMIT_MSG=$(claude --dangerously-skip-permissions --print "
Generate a concise git commit message for adding the package '$PACKAGE' to this nix-pkgs repository.

The commit should:
- Be in conventional commit format (e.g., 'feat: add ripgrep package')
- Include a brief description of what was added
- NOT mention Claude, Claude Code, Anthropic, AI, or LLM anywhere
- Be professional and match typical open source commit style

Output ONLY the commit message, nothing else.
")

  git commit -m "$COMMIT_MSG"
  echo "  Committed: $COMMIT_MSG"
fi

echo ""
echo "=== Package $PACKAGE added ==="
if [[ "$DO_COMMIT" == "true" ]]; then
  echo "Changes have been committed."
else
  echo "Review the changes and test with: nix build .#$PACKAGE"
fi
