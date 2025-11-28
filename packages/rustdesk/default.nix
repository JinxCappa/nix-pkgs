{
  lib,
  sources,
  rustPlatform,
  pkg-config,
  perl,
  wrapGAppsHook3,
  atk,
  bzip2,
  cairo,
  dbus,
  gdk-pixbuf,
  glib,
  gst_all_1,
  gtk3,
  libayatana-appindicator,
  libgit2,
  libpulseaudio,
  libsodium,
  libXtst,
  libvpx,
  libyuv,
  libopus,
  libaom,
  libxkbcommon,
  libsciter,
  openssl,
  xdotool,
  pam,
  pango,
  zlib,
  zstd,
  stdenv,
  alsa-lib,
  makeDesktopItem,
  copyDesktopItems,
  nix-prefetch-git,
  writeShellScriptBin,
}:

let
  nixPrefetchGitCompat = writeShellScriptBin "nix-prefetch-git" ''
    for candidate in \
      ${nix-prefetch-git}/bin/nix-prefetch-git \
      ${nix-prefetch-git}/bin/nix-prefetch-git-*; do
      if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
      fi
    done
    echo "nix-prefetch-git executable not found in ${nix-prefetch-git}/bin" >&2
    exit 127
  '';
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rustdesk";
  version = sources.rustdesk.version;

  inherit (sources.rustdesk) src;

  cargoHash = "sha256-mEtTo1ony5w/dzJcHieG9WywHirBoQ/C0WpiAr7pUVc=";

  depsExtraArgs = {
    nativeBuildInputs = [ nixPrefetchGitCompat ];
  };

  # Make build reproducible by replacing dynamic build date with fixed value
  postPatch = ''
    sed -i 's|let build_date = format!.*chrono::Local::now().*);|let build_date = "1970-01-01 00:00";|' libs/hbb_common/src/lib.rs
    sed -e '1i #include <cstdint>' -i $cargoDepsCopy/webm-1.1.0/src/sys/libwebm/mkvparser/mkvparser.cc
    sed -e '1i #include <cstdint>' -i $cargoDepsCopy/webm-sys-1.0.4/libwebm/mkvparser/mkvparser.cc
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "rustdesk";
      exec = finalAttrs.meta.mainProgram;
      icon = "rustdesk";
      desktopName = "RustDesk";
      comment = finalAttrs.meta.description;
      genericName = "Remote Desktop";
      categories = [ "Network" ];
      mimeTypes = [ "x-scheme-handler/rustdesk" ];
    })
  ];

  nativeBuildInputs = [
    copyDesktopItems
    perl
    pkg-config
    rustPlatform.bindgenHook
    wrapGAppsHook3
  ];

  buildFeatures = lib.optionals stdenv.hostPlatform.isLinux [ "linux-pkg-config" ];

  # Checks require an active X server
  doCheck = false;

  buildInputs = [
    atk
    bzip2
    cairo
    dbus
    gdk-pixbuf
    glib
    gst_all_1.gst-plugins-base
    gst_all_1.gstreamer
    gtk3
    libgit2
    libpulseaudio
    libsodium
    libXtst
    libvpx
    libyuv
    libopus
    libaom
    libxkbcommon
    openssl
    pam
    pango
    zlib
    zstd
  ]

  ++ lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    xdotool
  ];

  # Add static ui resources and libsciter to same folder as binary so that it
  # can find them.
  postInstall = ''
    mkdir -p $out/{share/src,lib/rustdesk}

    # .so needs to be next to the executable
    mv $out/bin/rustdesk $out/lib/rustdesk
    ${lib.optionalString stdenv.hostPlatform.isLinux "ln -s ${libsciter}/lib/libsciter-gtk.so $out/lib/rustdesk"}

    makeWrapper $out/lib/rustdesk/rustdesk $out/bin/rustdesk \
      --chdir "$out/share"

    cp -a $src/src/ui $out/share/src

    install -Dm0644 $src/res/logo.svg $out/share/icons/hicolor/scalable/apps/rustdesk.svg
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --add-rpath "${libayatana-appindicator}/lib" "$out/lib/rustdesk/rustdesk"
  '';

  env = {
    SODIUM_USE_PKG_CONFIG = true;
    ZSTD_SYS_USE_PKG_CONFIG = true;
  };

  meta = {
    description = "Virtual / remote desktop infrastructure for everyone! Open source TeamViewer / Citrix alternative";
    homepage = "https://rustdesk.com";
    changelog = "https://github.com/rustdesk/rustdesk/releases/tag/${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [
      ocfox
      leixb
    ];
    mainProgram = "rustdesk";
    badPlatforms = lib.platforms.darwin;
  };
})
