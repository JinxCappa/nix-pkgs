{
  stdenv,
  lib,
  buildGo127Module,
  fetchurl,
  go_1_27,
  installShellFiles,
  nixosTests,
  makeWrapper,
  gawk,
  glibc,
  sources,
}:

let
  # Vault 2.2.2 requires Go 1.27.4. Use nixpkgs again once it catches up.
  go =
    if lib.versionAtLeast go_1_27.version "1.27.4" then
      go_1_27
    else
      go_1_27.overrideAttrs (finalAttrs: _: {
        version = "1.27.4";
        src = fetchurl {
          url = "https://go.dev/dl/go${finalAttrs.version}.src.tar.gz";
          hash = "sha256-c8+4VxrsDAEXdofbhxY9Rqog6XeWcncokaoXZU2aYJk=";
        };
      });
in
(buildGo127Module.override { inherit go; }) rec {
  pname = "vault";
  version = lib.removePrefix "v" sources.vault.version;

  src = sources.vault.src;

  vendorHash = "sha256-SsrKAscgdaMGD8Xrau0+hHczIIZwxXG5NPB9Eeudco0=";

  proxyVendor = true;

  postPatch = ''
    # Remove defunct github.com/hashicorp/go-cmp dependency
    sed -i '/github\.com\/hashicorp\/go-cmp/d' go.mod
    sed -i '/github\.com\/hashicorp\/go-cmp/d' go.sum
  '';

  subPackages = [ "." ];

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];

  tags = [ "vault" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/hashicorp/vault/sdk/version.GitCommit=${sources.vault.version}"
    "-X github.com/hashicorp/vault/sdk/version.Version=${version}"
    "-X github.com/hashicorp/vault/sdk/version.VersionPrerelease="
  ];

  postInstall = ''
    echo "complete -C $out/bin/vault vault" > vault.bash
    installShellCompletion vault.bash
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    wrapProgram $out/bin/vault \
      --prefix PATH ${
        lib.makeBinPath [
          gawk
          glibc
        ]
      }
  '';

  passthru.tests = {
    inherit (nixosTests)
      vault
      vault-postgresql
      vault-dev
      vault-agent
      ;
  };

  meta = {
    homepage = "https://www.vaultproject.io/";
    description = "Tool for managing secrets";
    changelog = "https://github.com/hashicorp/vault/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.bsl11;
    mainProgram = "vault";
    maintainers = with lib.maintainers; [
      rushmorem
      lnl7
      offline
      Chili-Man
      techknowlogick
    ];
  };
}
