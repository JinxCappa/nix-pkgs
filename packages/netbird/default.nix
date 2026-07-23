{
  stdenv,
  lib,
  nixosTests,
  buildGoModule,
  fetchFromGitHub,
  fetchPnpmDeps,
  go,
  installShellFiles,
  writeShellScript,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  pkg-config,
  gtk3,
  gtk4,
  libayatana-appindicator,
  libX11,
  libXcursor,
  libXxf86vm,
  webkitgtk_6_0,
  versionCheckHook,
  sources,
  componentName ? "client",
}:
let
  # Strip the "v" prefix from version (e.g., "v0.60.2" -> "0.60.2")
  version = lib.removePrefix "v" sources.netbird.version;

  /*
    License tagging is based off:
    - https://github.com/netbirdio/netbird/blob/9e95841252c62b50ae93805c8dfd2b749ac95ea7/LICENSES/REUSE.toml
    - https://github.com/netbirdio/netbird/blob/9e95841252c62b50ae93805c8dfd2b749ac95ea7/LICENSE#L1-L2
  */
  availableComponents = {
    client = {
      module = "client";
      binaryName = "netbird";
      license = lib.licenses.bsd3;
      versionCheckProgramArg = "version";
      hasCompletion = true;
    };
    ui = {
      module = "client/ui";
      binaryName = "netbird-ui";
      license = lib.licenses.bsd3;
    };
  };
  component = availableComponents.${componentName};
  wails3 = buildGoModule {
    pname = "wails3";
    version = "3.0.0-alpha2.117";

    src = fetchFromGitHub {
      owner = "wailsapp";
      repo = "wails";
      tag = "v3.0.0-alpha2.117";
      hash = "sha256-lGMY+xlhclf+1YWJHiZI8/VVOz8e5bCOAw4XUDzecNI=";
    };

    modRoot = "v3";
    subPackages = [ "cmd/wails3" ];
    vendorHash = "sha256-50pbaGdwsZLZegeU423gAjoZtXoDAsSrSEWEQ9ivDdc=";
    proxyVendor = true;
    env.GOWORK = "off";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      gtk3
      gtk4
      webkitgtk_6_0
    ];
    doCheck = false;
  };
  darwinSystemClang = writeShellScript "netbird-system-clang" ''
    unset COMPILER_PATH LIBRARY_PATH
    export PATH=/Library/Developer/CommandLineTools/usr/bin:/usr/bin:/bin
    exec /Library/Developer/CommandLineTools/usr/bin/clang \
      -B/Library/Developer/CommandLineTools/usr/bin \
      -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk "$@"
  '';
in
buildGoModule (finalAttrs: {
  pname = "netbird-${componentName}";
  inherit version;

  src = sources.netbird.src;

  # vendorHash needs to be updated when source changes
  # Build will fail with correct hash if outdated
  vendorHash = "sha256-KVGCV89qGHrg2GQVw6MnftQswbdihcqozptjf5vs5BA=";
  # Wails v3's module zip omits Windows-only embedded DLLs. Avoid
  # `go mod vendor`, which resolves those embeds even on non-Windows hosts.
  proxyVendor = true;

  pnpmDeps =
    if componentName == "ui" then
      fetchPnpmDeps {
        inherit (finalAttrs)
          pname
          version
          src
          pnpmInstallFlags
          ;
        sourceRoot = "${finalAttrs.src.name}/client/ui/frontend";
        pnpm = pnpm_10;
        fetcherVersion = 3;
        hash = "sha256-014ngMpfGEchr+XWOp+pRpPkKzHxCcANfjlQpGW6fLQ=";
      }
    else
      null;

  pnpmRoot = "client/ui/frontend";
  pnpmInstallFlags = [
    "--network-concurrency=1"
    "--child-concurrency=1"
  ];

  nativeBuildInputs = [
    installShellFiles
  ] ++ lib.optionals (componentName == "ui") [
    nodejs
    pnpm_10
    pnpmConfigHook
    pkg-config
    wails3
  ];

  buildInputs = lib.optionals (stdenv.hostPlatform.isLinux && componentName == "ui") [
    gtk3
    gtk4
    libayatana-appindicator
    libX11
    libXcursor
    libXxf86vm
    webkitgtk_6_0
  ];

  subPackages = [ component.module ];
  tags = lib.optional (componentName == "ui") "production";

  overrideModAttrs = lib.optionalAttrs (componentName == "ui") {
    nativeBuildInputs = [
      go
      pkg-config
    ];
    preBuild = "";
  };

  # cctools ld crashes while linking the Darwin UI binary with the macOS 26.5
  # bootstrap SDK. Use Apple's linker until the nixpkgs toolchain is fixed;
  # Nix still strips the finished binary during fixupPhase.
  ldflags = lib.optionals (!(stdenv.hostPlatform.isDarwin && componentName == "ui")) [
    "-s"
    "-w"
  ] ++ [
    "-X github.com/netbirdio/netbird/version.version=${finalAttrs.version}"
    "-X main.builtBy=nix"
  ] ++ lib.optional (stdenv.hostPlatform.isDarwin && componentName == "ui") "-extld=${darwinSystemClang}";

  # needs network access
  doCheck = false;

  postPatch = ''
    # make it compatible with systemd's RuntimeDirectory
    substituteInPlace client/cmd/root.go \
      --replace-fail 'unix:///var/run/netbird.sock' 'unix:///var/run/netbird/sock'
    substituteInPlace client/ui/grpc.go \
      --replace-fail 'unix:///var/run/netbird.sock' 'unix:///var/run/netbird/sock'
  '';

  preBuild = lib.optionalString (componentName == "ui") ''
    pushd client/ui
    wails3 generate bindings -f '-tags production' -clean=true -ts
    pushd frontend
    pnpm run build
    popd
    popd
  '';

  postInstall =
    let
      builtBinaryName = lib.last (lib.splitString "/" component.module);
    in
    ''
      mv $out/bin/${builtBinaryName} $out/bin/${component.binaryName}
    ''
    +
      lib.optionalString
        (stdenv.buildPlatform.canExecute stdenv.hostPlatform && (component.hasCompletion or false))
        ''
          installShellCompletion --cmd ${component.binaryName} \
            --bash <($out/bin/${component.binaryName} completion bash) \
            --fish <($out/bin/${component.binaryName} completion fish) \
            --zsh <($out/bin/${component.binaryName} completion zsh)
        ''
    # assemble & adjust netbird.desktop files for the GUI
    + lib.optionalString (stdenv.hostPlatform.isLinux && componentName == "ui") ''
      install -Dm644 "$src/client/ui/assets/netbird-systemtray-connected.png" "$out/share/pixmaps/netbird.png"
      install -Dm644 "$src/client/ui/build/linux/netbird.desktop" "$out/share/applications/netbird.desktop"

      substituteInPlace $out/share/applications/netbird.desktop \
        --replace-fail "/usr/bin/netbird-ui" "$out/bin/${component.binaryName}"
    '';

  nativeInstallCheckInputs = lib.lists.optionals (component ? versionCheckProgramArg) [
    versionCheckHook
  ];
  versionCheckProgram = "${placeholder "out"}/bin/${component.binaryName}";
  versionCheckProgramArg = component.versionCheckProgramArg or "version";

  passthru = {
    tests = lib.attrsets.optionalAttrs (componentName == "client") {
      nixos = nixosTests.netbird;
    };
  };

  meta = {
    homepage = "https://netbird.io";
    changelog = "https://github.com/netbirdio/netbird/releases/tag/v${finalAttrs.version}";
    description = "Connect your devices into a single secure private WireGuard®-based mesh network with SSO/MFA and simple access controls";
    license = component.license;
    maintainers = with lib.maintainers; [
      nazarewk
      saturn745
      loc
    ];
    mainProgram = component.binaryName;
  };
})
