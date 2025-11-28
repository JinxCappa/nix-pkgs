#!/usr/bin/env bash
set -eou pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
PACKAGES_DIR="${SCRIPT_DIR}/packages"

# List all packages (directories with default.nix)
list_packages() {
  for dir in "${PACKAGES_DIR}"/*/; do
    if [[ -f "${dir}default.nix" ]]; then
      basename "$dir"
    fi
  done
}

# Check if package needs unfree/impure flags
needs_unfree() {
  local package="$1"
  grep -q 'licenses\.unfree' "${PACKAGES_DIR}/${package}/default.nix" 2>/dev/null
}

# Build a single package
build_package() {
  local package="$1"
  local package_dir="${PACKAGES_DIR}/${package}"

  # Validate package exists
  if [[ ! -d "$package_dir" ]] || [[ ! -f "${package_dir}/default.nix" ]]; then
    echo "Error: Package '${package}' not found" >&2
    echo "Run './build.sh ls' to see available packages" >&2
    exit 1
  fi

  echo "Building ${package}..."

  # Build with appropriate flags
  if needs_unfree "$package"; then
    NIXPKGS_ALLOW_UNFREE=1 nix build --no-link --print-out-paths -L --fallback --impure "${SCRIPT_DIR}#${package}" | \
      xargs -I {} attic push "ci:$ATTIC_CACHE" {}
  else
    nix build --no-link --print-out-paths -L --fallback "${SCRIPT_DIR}#${package}" | \
      xargs -I {} attic push "ci:$ATTIC_CACHE" {}
  fi
}

# Build all packages
build_all() {
  for package in $(list_packages); do
    build_package "$package"
  done
}

# Show usage
usage() {
  cat <<EOF
Usage: ./build.sh <command>

Commands:
  <package>   Build a specific package
  ls          List available packages
  --all       Build all packages
  --help, -h  Show this help message

Examples:
  ./build.sh claude-code    # Build claude-code package
  ./build.sh --all          # Build all packages
  ./build.sh ls             # List available packages
EOF
}

# Main: Parse arguments and dispatch
case "${1:-}" in
  ls)
    list_packages
    ;;
  --all)
    build_all
    ;;
  --help|-h|"")
    usage
    ;;
  *)
    build_package "$1"
    ;;
esac
