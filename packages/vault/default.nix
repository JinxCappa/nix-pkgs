{
  stdenv,
  lib,
  buildGoModule,
  go_1_26,
  installShellFiles,
  nixosTests,
  makeWrapper,
  gawk,
  glibc,
  sources,
}:

(buildGoModule.override { go = go_1_26; }) rec {
  pname = "vault";
  version = lib.removePrefix "v" sources.vault.version;

  src = sources.vault.src;

  vendorHash = "sha256-rU04+nNxa3h1hUTm6K4hZIB5aDLfjrhG4+WiZH+YZEg=";

  proxyVendor = true;

  postPatch = ''
    # Remove defunct github.com/hashicorp/go-cmp dependency
    sed -i '/github\.com\/hashicorp\/go-cmp/d' go.mod
    sed -i '/github\.com\/hashicorp\/go-cmp/d' go.sum

    # Keep Vault buildable when upstream bumps the patch-level Go requirement
    # before nixpkgs' go_1_26 has caught up.
    sed -i -E 's/^(go[[:space:]]+)[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$/\1${go_1_26.version}/' go.mod
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
