{
  lib,
  stdenv,
  callPackage,
  sources,
}:

let
  agent2VendorHash = "sha256-nw5l5mu/nJD+QsbRtg9SjiZIq86CTAU5F9unrn9hDik=";
in
callPackage ../zabbix/common.nix {
  zabbixSource = sources.zabbix74;
  inherit agent2VendorHash;
  agent2PostPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Zabbix 7.4.15 added cancelAccept implementations for Linux and
    # Windows, but omitted Darwin. UnixListener supports the same deadline
    # cancellation used by the Linux implementation.
    cp src/go/plugins/external/connection_linux.go \
      src/go/plugins/external/connection_darwin.go
  '';
}
