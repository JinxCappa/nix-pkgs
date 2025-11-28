#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

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

# Step 3: Detect unfree license
echo "=== Checking license ==="
IS_FREE=$(nix eval "nixpkgs#$PACKAGE.meta.license.free" 2>/dev/null || echo "true")
if [[ "$IS_FREE" == "false" ]]; then
  echo "  Package is unfree - will add special flags to workflow"
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
   - Keep any hash fields (cargoHash, vendorHash, npmDepsHash) as they are
   - Remove unused fetch function imports (fetchFromGitHub, fetchurl, etc.)
   - Remove any nix-update-script if present
4. If there are patches or other files, ensure they're still referenced correctly
5. After making changes, show me what nvfetcher entry you added

Important: If this package seems too complex (multiple outputs, complex callPackage chains, platform-specific overrides), warn me and explain what manual review is needed.
"

# Step 6: Create GitHub workflow
echo "=== Creating GitHub workflow ==="

if [[ "$UNFREE" == "true" ]]; then
  BUILD_CMD='nix build --no-link --print-out-paths -L --fallback --impure .#'"$PACKAGE"' | xargs -I {} attic push "ci:$ATTIC_CACHE" {};'
  BUILD_ENV="
        env:
          NIXPKGS_ALLOW_UNFREE: 1"
else
  BUILD_CMD='nix build --no-link --print-out-paths -L --fallback .#'"$PACKAGE"' | xargs -I {} attic push "ci:$ATTIC_CACHE" {};'
  BUILD_ENV=""
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
          - ubuntu-24.04
          - ubuntu-22.04-arm
          - macos-15
          - macos-15-intel
    permissions:
      contents: write
    runs-on: \${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4.2.2

      - name: Install current Bash on macOS
        if: runner.os == 'macOS'
        run: |
          command -v brew && brew install bash || true

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
          export PATH=\$HOME/.nix-profile/bin:\$PATH
          $BUILD_CMD$BUILD_ENV
EOF

echo "  Created .github/workflows/$PACKAGE.yaml"

# Step 7: Run nvfetcher to generate sources
echo "=== Running nvfetcher ==="
nvfetcher

# Step 8: Optionally commit changes
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
