{
  lib,
  stdenvNoCC,
  nodejs_22,
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
    hash = "sha256-1xGtrzvB1mVh5kKxmANNcj9NJ7mIIEtKyvfunMuiiAM=";
  };

  nativeBuildInputs = [
    nodejs_22
    pnpmConfigHook
    pnpm_10
  ];

  pnpmInstallFlags = [
    "--ignore-scripts"
  ];

  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"node": "20"' '"node": "22"'
  '';

  postConfigure = ''
    substituteInPlace .ember-cli \
      --replace-fail "../internal/http/web_ui" "$out"
  '';

  buildPhase = ''
    runHook preBuild

    pnpm run build

    runHook postBuild
  '';

  dontInstall = true;
})
