{ sources, lib, callPackage, ... }:

let
  netbird = callPackage ../netbird { inherit sources; };
in
netbird.override {
  componentName = "ui";
}
