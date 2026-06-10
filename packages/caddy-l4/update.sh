#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(realpath "$0")")/../.."

pkg="caddy-l4"
pkg_file="packages/$pkg/default.nix"
source_version_file="packages/$pkg/.source-version"

caddy_version=$(nix eval --raw ".#$pkg.version")
caddy_l4_version=$(jq -r '."caddy-l4".version' _sources/generated.json)

echo "  $pkg: caddy version is $caddy_version"
echo "  $pkg: caddy-l4 version is $caddy_l4_version"

build_output=""
if ! build_output=$(nix build --no-link ".#$pkg" 2>&1); then
  new_hash=$(echo "$build_output" | sed -nE 's/^[[:space:]]*got:[[:space:]]*([^[:space:]]+).*$/\1/p' | head -1 || true)

  if [ -z "$new_hash" ]; then
    echo "  $pkg: build failed for unknown reason while checking caddy.withPlugins hash"
    echo "$build_output" | tail -20
    exit 1
  fi

  echo "  $pkg: updating caddy.withPlugins hash to $new_hash"
  sed -i -E "s#hash = (\"sha256-[^\"]*\"|lib\\.fakeHash|null)#hash = \"$new_hash\"#" "$pkg_file"

  echo "  $pkg: verifying updated hash"
  nix build --no-link ".#$pkg" >/dev/null
else
  echo "  $pkg: caddy.withPlugins hash is up to date"
fi

cat > "$source_version_file" <<EOF
caddy=$caddy_version
caddy-l4=$caddy_l4_version
EOF
