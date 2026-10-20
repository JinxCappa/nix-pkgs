{
  lib,
  stdenv,
  dpkg,
  autoPatchelfHook,
  asar,
  makeWrapper,
  bash,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  coreutils,
  cups,
  dbus,
  expat,
  gawk,
  getent,
  gdk-pixbuf,
  gnugrep,
  gnused,
  glib,
  gtk3,
  libdrm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libxcrypt-legacy,
  libxscrnsaver,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  linux-pam,
  procps,
  sudo,
  systemd,
  udev,
  util-linux,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxcb,
  libxshmfence,
  libxtst,
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

  runtimePath = "/run/wrappers/bin:" + lib.makeBinPath [
    bash
    coreutils
    dbus
    ethtool
    gawk
    getent
    gnugrep
    gnused
    hwinfo
    libnotify
    procps
    sudo
    systemd
    udev
    util-linux
    xdotool
    xinput
    xrandr
    xsel
  ];
  runtimeLibraryPath = lib.makeLibraryPath [
    # Also expose libraries to vendor helpers that load them dynamically.
    linux-pam
    stdenv.cc.cc.lib
    systemd
    dbus
    libx11
    libxrandr
    libxtst
    libxfixes
    libglvnd
    mesa
  ];
in

stdenv.mkDerivation (finalAttrs: {
  pname = "remotepc-host";
  version = source.version;

  src = source.src;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    asar
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
    # remotepc-audio links directly against libpulse.so.0.
    libpulseaudio
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
    udev
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    libxshmfence
    libxtst
    xinput
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

    # Session children do not reliably preserve LD_LIBRARY_PATH. Unpack native
    # modules so autoPatchelfHook can give each one its own library search path
    # and fail the build if a dependency is missing.
    asar extract "$out/opt/remotepc-host/resources/app.asar" remotepc-app
    asar pack remotepc-app "$out/opt/remotepc-host/resources/app.asar" \
      --unpack '*.node'
    rm -rf remotepc-app

    ${lib.optionalString (!isAarch64) ''
      # RemotePC's PipeWire configuration does not load these optional generic
      # modules. Drop unused RAOP and PulseAudio tunnel support, avoiding the
      # RAOP module's dependency on EOL OpenSSL 1.1.
      rm $out/opt/remotepc-host/pipewire-modules/libpipewire-module-raop-sink.so
      rm $out/opt/remotepc-host/pipewire-modules/libpipewire-module-pulse-tunnel.so
    ''}

    # The host bytecode spawns native helpers from /opt/<app>/bin even though
    # the Debian package ships them at the application root.
    mkdir -p $out/opt/remotepc-host/bin
    for helper in capture-screen capture-audio; do
      if [ -e "$out/opt/remotepc-host/$helper" ]; then
        ln -sfn "../$helper" "$out/opt/remotepc-host/bin/$helper"
      fi
    done

    makeWrapper $out/opt/remotepc-host/remotepc-host $out/bin/.remotepc-host-wrapped \
      --unset ELECTRON_RUN_AS_NODE \
      --prefix PATH : ${runtimePath} \
      --prefix LD_LIBRARY_PATH : ${runtimeLibraryPath} \
      --set-default APP remotepc-host \
      --set-default MESA_NO_WARNINGS 1 \
      --set-default NODE_NO_WARNINGS 1 \
      --add-flags "--no-sandbox" \
      --add-flags "--disable-gpu" \
      --add-flags "--disable-gpu-sandbox" \
      --add-flags "--disable-dev-shm-usage"

    makeWrapper $out/opt/remotepc-host/remotepc-host $out/bin/.remotepc-host-daemon \
      --prefix PATH : ${runtimePath} \
      --prefix LD_LIBRARY_PATH : ${runtimeLibraryPath} \
      --set ELECTRON_RUN_AS_NODE 1 \
      --set APP remotepc-host \
      --set-default MESA_NO_WARNINGS 1 \
      --set-default NODE_NO_WARNINGS 1 \
      --add-flags "$out/opt/remotepc-host/resources/app.asar/node_modules/daemon/"

    makeWrapper $out/opt/remotepc-host/remotepc-host $out/bin/.remotepc-host-cli \
      --prefix PATH : ${runtimePath} \
      --prefix LD_LIBRARY_PATH : ${runtimeLibraryPath} \
      --set ELECTRON_RUN_AS_NODE 1 \
      --set APP remotepc-cli \
      --set-default NODE_NO_WARNINGS 1 \
      --add-flags "$out/opt/remotepc-host/resources/app.asar"

    # The headless fallback must use the CLI wrapper rather than passing GUI
    # flags to Electron in Node mode. Patch it before rewriting GUI launches.
    substituteInPlace $out/opt/remotepc-host/bin/remotepc-host-setup \
      --replace-fail \
        'APP=remotepc-cli ELECTRON_RUN_AS_NODE=1 NODE_NO_WARNINGS=1 /opt/remotepc-host/remotepc-host /opt/remotepc-host/resources/app.asar $@' \
        '"@cli@" "$@"' \
      --replace-fail '@cli@' "$out/bin/.remotepc-host-cli"

    substituteInPlace $out/opt/remotepc-host/bin/remotepc-host-setup \
      --replace-fail "/opt/remotepc-host/remotepc-host" "$out/bin/.remotepc-host-wrapped"

    # Use APP=remotepc-cli for supported commands even on graphical hosts.
    # Keep the vendor session detection for desktop launches and setup.
    substituteInPlace $out/opt/remotepc-host/bin/remotepc-host-setup \
      --replace-fail 'launchApp $@' '
        case "$1" in
          --help|-h) shift; exec "@cli@" help "$@" ;;
          --version|-v) shift; exec "@cli@" version "$@" ;;
          login)
            if ! systemctl is-active --quiet remotepc-host.service; then
              echo "RemotePC service is not running. Check: journalctl -u remotepc-host -b" >&2
              exit 1
            fi
            exec "@cli@" "$@"
            ;;
          help|status|version|deploy|logout|enable|disable|rename|set-personal-key|remove-personal-key|change-personal-key|send-error-report|exit)
            exec "@cli@" "$@"
            ;;
          *) launchApp "$@" ;;
        esac' \
      --replace-fail '@cli@' "$out/bin/.remotepc-host-cli"

    makeWrapper $out/opt/remotepc-host/bin/remotepc-host-setup $out/bin/remotepc-host \
      --prefix PATH : ${runtimePath} \
      --prefix LD_LIBRARY_PATH : ${runtimeLibraryPath}

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
