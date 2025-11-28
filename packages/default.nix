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

  # Helper to check if something is a derivation
  isDerivation = x: x ? type && x.type == "derivation";

  # Build packages (may be derivations or attrsets of derivations)
  # If a package returns an attrset where all derivation keys are prefixed with the package name,
  # merge directly (e.g., openbao -> { openbao, openbao-ui, ... })
  # Otherwise nest under the directory name (e.g., zabbix74 -> { zabbix74.server, ... })
  packages = lib.foldl' (acc: name:
    let
      pkg = prev.callPackage (./. + "/${name}") { inherit sources; };
    in
    if isDerivation pkg then
      acc // { ${name} = pkg; }
    else if builtins.isAttrs pkg then
      let
        # Only check derivation keys (ignore override, overrideDerivation, etc.)
        derivationAttrs = lib.filterAttrs (_: isDerivation) pkg;
        keys = builtins.attrNames derivationAttrs;
        # Check if all derivation keys start with the directory name (merge pattern)
        shouldMerge = keys != [] && builtins.all (k: lib.hasPrefix name k) keys;
      in
      if shouldMerge then
        acc // derivationAttrs  # Merge derivations directly
      else
        acc // { ${name} = pkg; }  # Nest under directory name
    else
      acc
  ) {} packageNames;
in
packages
