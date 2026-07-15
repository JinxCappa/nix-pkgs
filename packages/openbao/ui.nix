{
  lib,
  stdenvNoCC,
  nodejs_20,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  version,
  src,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "openbao-ui";
  inherit version src;
  sourceRoot = "${src.name}/ui";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src sourceRoot;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-9Q5celZSwMgSS8qcj8sDH/JLv48lgDMOylANvXSnhsU=";
  };

  nativeBuildInputs = [
    nodejs_20
    pnpmConfigHook
    pnpm_10
  ];

  pnpmInstallFlags = [
    "--ignore-scripts"
  ];

  postConfigure = ''
    substituteInPlace .ember-cli \
      --replace-fail "../http/web_ui" "$out"
  '';

  buildPhase = ''
    runHook preBuild

    pnpm run build

    runHook postBuild
  '';

  dontInstall = true;
})
