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
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  xorg,
  ethtool,
  xdotool,
  sources,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "remotepc-host";
  version = sources.remotepc-host.version;

  src = sources.remotepc-host.src;

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
    libxkbcommon
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
  ];

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
    substituteInPlace $out/share/applications/remotepc-host.desktop \
      --replace-fail "/opt/remotepc-host/remotepc-host --no-sandbox" "$out/bin/remotepc-host"

    runHook postInstall
  '';

  meta = {
    homepage = "https://www.remotepc.com";
    description = "RemotePC Host - remote access solution for Linux machines and headless servers";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "remotepc-host";
  };
})
