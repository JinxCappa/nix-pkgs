{
  armbianBuild,
  lib,
  linux_6_18,
  linuxManualConfig,
  sources,
}:

let
  patchDirectory = "${armbianBuild}/patch/kernel/archive/cix-6.18";
  armbianConfig = "${armbianBuild}/config/kernel/linux-cix-p1-current.config";
  patchNames = lib.sort builtins.lessThan (
    lib.filter (name: lib.hasSuffix ".patch" name) (
      builtins.attrNames (builtins.readDir patchDirectory)
    )
  );

  # Armbian ships a defconfig, so it omits hidden values that Kconfig derives
  # during oldconfig. NixOS reads the input config directly when selecting the
  # maximum ASLR entropy, before the kernel has been built. Keep the resolved
  # ARM64 values visible to both consumers.
  kernelConfig = builtins.toFile "linux-cix-p1-current.config" ''
    ${builtins.readFile armbianConfig}
    CONFIG_ARCH_MMAP_RND_BITS_MAX=33
    CONFIG_ARCH_MMAP_RND_COMPAT_BITS_MAX=16
  '';

  kernel = linuxManualConfig {
    inherit (linux_6_18) modDirVersion src version;

    configfile = kernelConfig;
    # builtins.toFile returns a store-path string. linuxManualConfig only
    # parses string-valued configs when this is enabled; otherwise it treats
    # CONFIG_MODULES as unset and produces no modules output.
    allowImportFromDerivation = true;
    kernelPatches = map (name: {
      inherit name;
      patch = "${patchDirectory}/${name}";
    }) patchNames;

    extraMeta = {
      branch = "6.18";
      description = "Linux ${linux_6_18.version} with Armbian CIX P1 ACPI support";
      homepage = "https://github.com/armbian/build";
      license = lib.licenses.gpl2Only;
      platforms = [ "aarch64-linux" ];
    };
  };
in
{
  linux-armbian-cix-p1 = kernel;
  linux-armbian-cix-p1-dev = kernel.dev;
  linux-armbian-cix-p1-modules = kernel.modules;
}
