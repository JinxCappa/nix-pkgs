#!/usr/bin/env bash
set -euo pipefail

server_versions=$(mktemp)
library_versions=$(mktemp)
trap 'rm -f "$server_versions" "$library_versions"' EXIT

git ls-remote --tags https://github.com/TechnitiumSoftware/DnsServer.git \
  | sed -n 's|.*refs/tags/v\([0-9]*\.[0-9]*\.[0-9]*\)$|\1|p' \
  | sort -Vu > "$server_versions"

git ls-remote --tags https://github.com/TechnitiumSoftware/TechnitiumLibrary.git \
  | sed -n 's|.*refs/tags/dns-server-v\([0-9]*\.[0-9]*\.[0-9]*\)$|\1|p' \
  | sort -Vu > "$library_versions"

comm -12 "$server_versions" "$library_versions" | sort -V | tail -1
