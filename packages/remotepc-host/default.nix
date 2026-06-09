{
  lib,
  stdenv,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libnotify,
  libxcrypt-legacy,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  linux-pam,
  systemd,
  xorg,
  ethtool,
  xdotool,
  sources,
  pipewire,
}:

let
  # RemotePC ships per-architecture .deb packages that version independently:
  # the amd64 build tracks the public release notes, while the arm64 (Raspberry
  # Pi 64-bit) build lags behind. Each is fetched as its own nvfetcher source.
  isAarch64 = stdenv.hostPlatform.isAarch64;
  source = if isAarch64 then sources.remotepc-host-pi64 else sources.remotepc-host;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "remotepc-host";
  version = source.version;

  src = source.src;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libnotify
    # libcrypt.so.1 for the vendored node-gyp python3 helpers (arm64 deb).
    libxcrypt-legacy
    libxkbcommon
    linux-pam
    mesa
    nspr
    nss
    pango
    systemd
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    xorg.libxshmfence
    xorg.libXtst
    xorg.xinput
  ]
  # The amd64 capture-screen binary captures via PipeWire; the arm64 build
  # uses an X11-based capture path and does not link PipeWire.
  ++ lib.optional (!isAarch64) pipewire;

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt $out/bin $out/share

    cp -r opt/remotepc-host $out/opt/remotepc-host

    # wrap the main binary with required runtime tools on PATH
    makeWrapper $out/opt/remotepc-host/remotepc-host $out/bin/remotepc-host \
      --prefix PATH : ${lib.makeBinPath [ ethtool xdotool ]} \
      --add-flags "--no-sandbox"

    # desktop file and icons
    cp -r usr/share/applications $out/share/
    cp -r usr/share/icons $out/share/
    # Point the launcher at the wrapped binary. The amd64 .desktop passes
    # "--no-sandbox" in Exec while the arm64 one does not; strip it if present
    # (the wrapper re-adds it) so the path rewrite works on both.
    substituteInPlace $out/share/applications/remotepc-host.desktop \
      --replace-quiet "/opt/remotepc-host/remotepc-host --no-sandbox" "/opt/remotepc-host/remotepc-host" \
      --replace-fail "/opt/remotepc-host/remotepc-host" "$out/bin/remotepc-host"

    runHook postInstall
  '';

  meta = {
    homepage = "https://www.remotepc.com";
    description = "RemotePC Host - remote access solution for Linux machines and headless servers";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "remotepc-host";
  };
})
