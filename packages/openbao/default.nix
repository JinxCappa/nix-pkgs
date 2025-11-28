{
  lib,
  buildGoModule,
  installShellFiles,
  callPackage,
  yarn-berry_3,
  nodejs_20,
  stdenvNoCC,
  sources,
}:

let
  source = sources.openbao;
  version = lib.removePrefix "v" source.version;

  mkOpenbao = { withUi ? false, withHsm ? false }:
    buildGoModule {
      pname = "openbao" + lib.optionalString withUi "-ui" + lib.optionalString withHsm "-hsm";
      inherit version;
      inherit (source) src;

      vendorHash = "sha256-3QNiw3q0dhgWeGFBq4a5GCE3bIIa4YiJRKMU+Hakvx0=";

      proxyVendor = true;

      subPackages = [ "." ];

      tags = lib.optional withHsm "hsm" ++ lib.optional withUi "ui";

      ldflags = [
        "-s"
        "-X github.com/openbao/openbao/version.GitCommit=${source.src.rev}"
        "-X github.com/openbao/openbao/version.fullVersion=${version}"
        "-X github.com/openbao/openbao/version.buildDate=1970-01-01T00:00:00Z"
      ];

      postConfigure = lib.optionalString withUi ''
        cp -r --no-preserve=mode ${callPackage ./ui.nix { inherit version; inherit (source) src; }} http/web_ui
      '';

      nativeBuildInputs = [
        installShellFiles
      ];

      postInstall = ''
        mv $out/bin/openbao $out/bin/bao

        # https://github.com/posener/complete/blob/9a4745ac49b29530e07dc2581745a218b646b7a3/cmd/install/bash.go#L8
        installShellCompletion --bash --name bao <(echo complete -C "$out/bin/bao" bao)
      '';

      doInstallCheck = false;

      meta = {
        homepage = "https://www.openbao.org/";
        description = "Open source, community-driven fork of Vault managed by the Linux Foundation"
          + lib.optionalString withUi " (with web UI)"
          + lib.optionalString withHsm " (with HSM support)";
        changelog = "https://github.com/openbao/openbao/blob/v${version}/CHANGELOG.md";
        license = lib.licenses.mpl20;
        mainProgram = "bao";
        maintainers = with lib.maintainers; [
          brianmay
          emilylange
        ];
      };
    };
in
{
  # Base variant (no UI, no HSM)
  openbao = mkOpenbao { };

  # With web UI
  openbao-ui = mkOpenbao { withUi = true; };

  # With HSM support (Linux only)
  openbao-hsm = mkOpenbao { withHsm = true; };

  # With both UI and HSM (Linux only)
  openbao-full = mkOpenbao { withUi = true; withHsm = true; };
}
