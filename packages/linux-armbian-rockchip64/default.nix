{
  dpkg,
  fetchurl,
  lib,
  linuxPackages_6_18,
  sources,
  stdenvNoCC,
}:

let
  armbianRelease = "26.5.1";
  armbianKernelVersion = "6.18.35";
  armbianKernelModDirVersion = "${armbianKernelVersion}-current-rockchip64";
  armbianKernelBuild = "6.18.35-Sacb7-D05ae-P5e3c-Cf57c-H8200-HK01ba-Vc222-B4497-R448a";

  armbianKernelImageDeb = fetchurl {
    url = "https://apt.armbian.com/pool/main/l/linux-${armbianKernelVersion}/linux-image-current-rockchip64_${armbianRelease}_arm64__${armbianKernelBuild}.deb";
    hash = "sha256-OyaM7iqQhGbaX6O0J+1YH88PgcUuUKXrIwVj/PyBl4I=";
  };

  armbianKernelDtbDeb = fetchurl {
    url = "https://apt.armbian.com/pool/main/l/linux-dtb-current-rockchip64/linux-dtb-current-rockchip64_${armbianRelease}_arm64__${armbianKernelBuild}.deb";
    hash = "sha256-/st1YVLl9LfHJ5LYF8ST8jowry/ecN7Ik8gSZMFAKKI=";
  };

  kernel = lib.makeOverridable (
    _:
    stdenvNoCC.mkDerivation {
      pname = "linux-armbian-rockchip64";
      version = armbianKernelVersion;
      outputs = [
        "out"
        "modules"
      ];
      dontUnpack = true;
      nativeBuildInputs = [ dpkg ];

      installPhase = ''
        runHook preInstall

        dpkg-deb --extract ${armbianKernelImageDeb} ./image
        dpkg-deb --extract ${armbianKernelDtbDeb} ./dtb

        install -Dm0644 \
          ./image/boot/vmlinuz-${armbianKernelModDirVersion} \
          "$out/Image"
        install -Dm0644 \
          ./image/boot/config-${armbianKernelModDirVersion} \
          "$out/config"
        install -Dm0644 \
          ./image/boot/System.map-${armbianKernelModDirVersion} \
          "$out/System.map"

        mkdir -p "$out/dtbs" "$modules/lib/modules"
        cp -a \
          ./dtb/boot/dtb-${armbianKernelModDirVersion}/. \
          "$out/dtbs/"
        cp -a \
          ./image/lib/modules/${armbianKernelModDirVersion} \
          "$modules/lib/modules/"

        runHook postInstall
      '';

      passthru = {
        modDirVersion = armbianKernelModDirVersion;
        target = "Image";
        buildDTBs = true;

        # No out-of-tree modules are used on these boards. Reuse the matching
        # nixpkgs kernel metadata so linuxPackagesFor can construct its package set.
        inherit (linuxPackages_6_18.kernel)
          commonMakeFlags
          config
          configfile
          features
          isLTS
          isZen
          kernelAtLeast
          kernelOlder
          stdenv
          ;
      };

      meta = {
        description = "Armbian Rockchip64 kernel";
        homepage = "https://www.armbian.com/";
        license = lib.licenses.gpl2Only;
        platforms = [ "aarch64-linux" ];
      };
    }
  ) { };
in
{
  linux-armbian-rockchip64 = kernel;
  linux-armbian-rockchip64-modules = kernel.modules;
}
