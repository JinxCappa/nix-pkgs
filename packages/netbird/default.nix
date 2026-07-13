{
  stdenv,
  lib,
  nixosTests,
  buildGoModule,
  installShellFiles,
  writeShellScript,
  pkg-config,
  gtk3,
  libayatana-appindicator,
  libX11,
  libXcursor,
  libXxf86vm,
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
  vendorHash = "sha256-z/2+LUBocWQ06EfdJ4nujr4vb1e2zjmlufsGgGWN0ak=";

  nativeBuildInputs = [ installShellFiles ] ++ lib.optional (componentName == "ui") pkg-config;

  buildInputs = lib.optionals (stdenv.hostPlatform.isLinux && componentName == "ui") [
    gtk3
    libayatana-appindicator
    libX11
    libXcursor
    libXxf86vm
  ];

  subPackages = [ component.module ];

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
    substituteInPlace client/ui/client_ui.go \
      --replace-fail 'unix:///var/run/netbird.sock' 'unix:///var/run/netbird/sock'
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
      install -Dm644 "$src/client/ui/build/netbird.desktop" "$out/share/applications/netbird.desktop"

      substituteInPlace $out/share/applications/netbird.desktop \
        --replace-fail "Exec=/usr/bin/netbird-ui" "Exec=$out/bin/${component.binaryName}"
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
