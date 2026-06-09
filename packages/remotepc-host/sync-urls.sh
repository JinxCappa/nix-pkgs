#!/usr/bin/env bash
# Refresh the remotepc-host download URLs in nvfetcher.toml with the live ones.
#
# The "/rpc/<segment>/" path in RemotePC's URLs changes between releases, so the
# fetch.url entries can go stale. Run this before nvfetcher so it fetches and
# hashes the current artifacts. nvfetcher itself only templates $ver, which the
# segment is unrelated to, hence this pre-step.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
toml="$(cd "$here/../.." && pwd)/nvfetcher.toml"

update_url() {
  local file="$1" url
  url="$("$here/resolve-url.sh" "$file")"
  # Rewrite only the fetch.url line whose value ends with exactly this filename.
  sed -i -E "s#^(fetch\\.url = \").*/${file//./\\.}\"#\\1${url}\"#" "$toml"
  echo "  remotepc: $file -> $url"
}

update_url remotepc-host.deb
update_url remotepc-host-pi64.deb
