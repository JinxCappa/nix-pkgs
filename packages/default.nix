{ pkgs }:

let
  # Load nvfetcher-generated sources
  sources = pkgs.callPackage ../_sources/generated.nix { };

  # Get all entries in the current directory
  entries = builtins.readDir ./.;

  # Filter to only directories that contain a default.nix
  isPackageDir = name: type:
    type == "directory" &&
    builtins.pathExists (./. + "/${name}/default.nix");

  packageNames = builtins.attrNames (
    pkgs.lib.filterAttrs isPackageDir entries
  );

  # Use lib.fix to allow packages to reference each other
  packages = pkgs.lib.fix (self:
    let
      # Namespace aliases that nixpkgs normally exposes at top-level
      # These are lazily evaluated so unused ones have no cost
      namespaces = pkgs.xorg           # X11: libX11, libXcursor, libXrandr, etc.
               // pkgs.gst_all_1       # GStreamer: gstreamer, gst-plugins-base, etc.
               // pkgs.libsForQt5      # Qt5: qtbase, qtsvg, wrapQtAppsHook, etc.
               // pkgs.qt6Packages;    # Qt6: qtbase, qtsvg, wrapQtAppsHook, etc.

      callPackage = pkgs.lib.callPackageWith (pkgs // namespaces // self // { inherit sources; });
    in
    builtins.listToAttrs (map (name: {
      inherit name;
      value = callPackage (./. + "/${name}") { };
    }) packageNames)
  );
in
packages
