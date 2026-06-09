#!/usr/bin/env bash
# Resolve the arm64 (Raspberry Pi 64-bit) remotepc-host version for nvfetcher.
#
# RemotePC publishes a single release-notes feed, and it tracks the amd64 build
# (currently ahead of the arm64 one). The pi64 .deb versions independently, so
# we read the version straight from the package's own control file instead.
#
# A .deb is an `ar` archive laid out as: debian-binary, control.tar.xz, then the
# large data.tar.xz last. A small ranged fetch is enough to grab the control
# member without downloading the whole ~100 MB package.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
url="$("$here/resolve-url.sh" remotepc-host-pi64.deb)"

nix shell nixpkgs#curl nixpkgs#gnutar nixpkgs#xz nixpkgs#binutils \
  --command bash -c '
    set -euo pipefail
    tmp=$(mktemp)
    trap "rm -f \"$tmp\"" EXIT
    curl -sf --range 0-262144 "'"$url"'" -o "$tmp"
    ar p "$tmp" control.tar.xz | tar -xJO ./control | sed -n "s/^Version: //p"
  '
