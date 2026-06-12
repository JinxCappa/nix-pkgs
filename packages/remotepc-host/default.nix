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
  libglvnd,
  libnotify,
  libxcrypt-legacy,
  libxscrnsaver,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  linux-pam,
  systemd,
  xorg,
  ethtool,
  hwinfo,
  xdotool,
  xinput,
  xrandr,
  xsel,
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
    libglvnd
    libnotify
    # libcrypt.so.1 for the vendored node-gyp python3 helpers (arm64 deb).
    libxcrypt-legacy
    libxscrnsaver
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

    makeWrapper $out/opt/remotepc-host/remotepc-host $out/bin/.remotepc-host-wrapped \
      --prefix PATH : ${lib.makeBinPath [
        ethtool
        hwinfo
        libnotify
        xdotool
        xinput
        xrandr
        xsel
      ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libglvnd mesa ]} \
      --set-default APP remotepc-host \
      --set-default MESA_NO_WARNINGS 1 \
      --set-default NODE_NO_WARNINGS 1 \
      --add-flags "--no-sandbox"

    makeWrapper $out/opt/remotepc-host/remotepc-host $out/bin/.remotepc-host-cli \
      --prefix PATH : ${lib.makeBinPath [
        ethtool
        hwinfo
        libnotify
        xdotool
        xinput
        xrandr
        xsel
      ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libglvnd mesa ]} \
      --set ELECTRON_RUN_AS_NODE 1 \
      --set APP remotepc-cli \
      --set-default NODE_NO_WARNINGS 1 \
      --add-flags "$out/opt/remotepc-host/resources/app.asar"

    cat > $out/bin/remotepc-host <<EOF
    #!${stdenv.shell}
    case "\''${1-}" in
      ""|-*) exec "$out/bin/.remotepc-host-wrapped" "\$@" ;;
      *) exec "$out/bin/.remotepc-host-cli" "\$@" ;;
    esac
    EOF
    chmod +x $out/bin/remotepc-host

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
