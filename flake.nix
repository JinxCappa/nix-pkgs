{
  description = "Custom package derivations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      flake = {
        overlays.default = final: prev: import ./packages { pkgs = final; };
      };

      perSystem = { pkgs, ... }:
        let
          customPackages = import ./packages { inherit pkgs; };
        in
        {
          packages = customPackages // {
            default = pkgs.symlinkJoin {
              name = "all-custom-packages";
              paths = builtins.attrValues customPackages;
            };
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nvfetcher
              nodejs
              prefetch-npm-deps
              coreutils
              gnused
              gnugrep
              gawk
              jq
            ];
          };
        };
    };
}
