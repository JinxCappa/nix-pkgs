{
  description = "Custom package derivations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      flake = rec {
        # Package directory names (for use in overlays)
        lib.packageNames = let
          entries = builtins.readDir ./packages;
          isPackageDir = name: type:
            type == "directory" &&
            builtins.pathExists (./packages + "/${name}/default.nix");
        in builtins.attrNames (builtins.listToAttrs
          (builtins.filter (x: x != null)
            (builtins.attrValues (builtins.mapAttrs
              (name: type: if isPackageDir name type then { inherit name; value = true; } else null)
              entries))));

        # Pre-evaluated packages using this flake's nixpkgs (for cache-friendly consumption)
        lib.packagesBySystem = builtins.listToAttrs (map (system: {
          name = system;
          value = let
            pkgs = import inputs.nixpkgs { inherit system; config.allowUnfree = true; };
          in import ./packages { lib = pkgs.lib; prev = pkgs; };
        }) [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ]);

        # Overlay that merges packages directly into pkgs
        # Usage: pkgs.claude-code, pkgs.zabbix74.server, etc.
        overlays.default = overlays.merged;

        overlays.merged = final: prev:
          import ./packages { lib = prev.lib; inherit prev; };

        lib.cachedTopLevelAliases = jinx: {
          "caddy-l4" = jinx."caddy-l4";
          "claude-code" = jinx."claude-code";
          "deploy-rs" = jinx."deploy-rs";
          netbird = jinx.netbird;
          "netbird-ui" = jinx."netbird-ui";
          "oh-my-zsh" = jinx."oh-my-zsh";
          openbao = jinx.openbao;
          "openbao-full" = jinx."openbao-full";
          "openbao-hsm" = jinx."openbao-hsm";
          "openbao-ui" = jinx."openbao-ui";
          "remotepc-host" = jinx."remotepc-host";
          rustdesk = jinx.rustdesk;
          "sops-install-secrets" = jinx."sops-install-secrets";
          vault = jinx.vault;
          vector = jinx.vector;
          "victoriametrics-cluster" = jinx."victoriametrics-cluster";
          zabbix74 = jinx.zabbix74;
          zabbix80pre = jinx.zabbix80pre;
        };

        # List of overlays that merge pre-built packages into pkgs, using this
        # flake input's nixpkgs as resolved by the consuming flake lock.
        # This is a list of two overlays that must be applied together:
        # 1. First puts packages under 'jinx' namespace (avoids alias conflicts)
        # 2. Second hoists selected aliases to top-level using explicit names
        # Usage: pkgs.claude-code, pkgs.vector, pkgs.zabbix74.server, etc.
        lib.overlays.cached = [
          # First: add packages under jinx namespace
          (final: prev: { jinx = lib.packagesBySystem.${prev.stdenv.hostPlatform.system} or {}; })
          # Second: hoist only the intentionally vendored top-level aliases
          (final: prev: lib.cachedTopLevelAliases prev.jinx)
        ];

        # Overlay that provides all packages under a 'jinx' namespace
        # Usage: pkgs.jinx.claude-code, pkgs.jinx.zabbix74.server, etc.
        overlays.namespaced = final: prev:
          { jinx = lib.packagesBySystem.${prev.stdenv.hostPlatform.system} or {}; };

        nixosModules = rec {
          remotepc-host = { lib, pkgs, ... }: {
            imports = [ ./modules/nixos/remotepc-host ];
            services.remotepc-host.package =
              lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.remotepc-host;
          };
          default = remotepc-host;
        };
      };

      perSystem = { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config = { allowUnfree = true; };
          };
          customPackages = import ./packages { lib = pkgs.lib; prev = pkgs; };

          # Helper to check if something is a derivation
          isDerivation = x: x ? type && x.type == "derivation";

          # Flatten nested packages for flake output (e.g., zabbix74.server -> zabbix74.server)
          # Keep top-level derivations as-is, expand attrsets with dot notation
          flattenedPackages = pkgs.lib.foldlAttrs (acc: name: value:
            if isDerivation value then
              acc // { ${name} = value; }
            else if builtins.isAttrs value then
              acc // pkgs.lib.mapAttrs' (subName: subPkg:
                { name = "${name}.${subName}"; value = subPkg; }
              ) (pkgs.lib.filterAttrs (_: isDerivation) value)
            else
              acc
          ) {} customPackages;

          # Collect all derivations for the default package
          allDerivations = builtins.filter isDerivation (builtins.attrValues flattenedPackages);
        in
        {
          packages = flattenedPackages // {
            default = pkgs.symlinkJoin {
              name = "all-custom-packages";
              paths = allDerivations;
            };
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nvfetcher
              nix-prefetch-git
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
