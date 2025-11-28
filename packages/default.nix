{ lib, prev }:

let
  # Load nvfetcher-generated sources
  sources = prev.callPackage ../_sources/generated.nix { };

  # Get all entries in the current directory
  entries = builtins.readDir ./.;

  # Filter to only directories that contain a default.nix
  isPackageDir = name: type:
    type == "directory" &&
    builtins.pathExists (./. + "/${name}/default.nix");

  packageNames = builtins.attrNames (
    lib.filterAttrs isPackageDir entries
  );

  # Build packages (may be derivations or attrsets of derivations like zabbix74.server)
  packages = builtins.listToAttrs (map (name: {
    inherit name;
    value = prev.callPackage (./. + "/${name}") { inherit sources; };
  }) packageNames);
in
packages
