#!/usr/bin/env bash
# Print the current RemotePC Linux download URL for a given package filename.
#
# RemotePC has no stable "latest" URL; the real download links live in a
# published JS file and contain a volatile "/rpc/<segment>/" path that changes
# between releases. We read that file rather than hardcoding the segment.
#
# Usage: resolve-url.sh remotepc-host.deb
set -euo pipefail

file="${1:?usage: resolve-url.sh <filename.deb>}"
js="https://www.remotepc.com/source/js/version-linux-e1.js"

# Match a download URL whose path ends with exactly this filename (dots escaped),
# so e.g. "remotepc-host.deb" does not also match "remotepc-host-pi64.deb".
pat="https://[a-z.]*remotepc\\.com/downloads/rpc/[0-9]+/${file//./\\.}\""
url="$(curl -sfL -A "Mozilla/5.0" "$js" | grep -oE "$pat" | tr -d '"' | head -1)"

[ -n "$url" ] || { echo "resolve-url: no URL for '$file' in $js" >&2; exit 1; }
echo "$url"
