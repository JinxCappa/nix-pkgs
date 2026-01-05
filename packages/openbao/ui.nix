{
  stdenvNoCC,
  yarn-berry_3,
  nodejs_20,
  version,
  src,
}:

let
  yarn = yarn-berry_3.override { nodejs = nodejs_20; };
in
stdenvNoCC.mkDerivation {
  pname = "openbao-ui";
  inherit version src;
  sourceRoot = "${src.name}/ui";

  offlineCache = yarn.fetchYarnBerryDeps {
    inherit src;
    sourceRoot = "${src.name}/ui";
    hash = "sha256-ZG/br4r2YzPPgsysx7MBy1WtUBkar1U84nkKecZ5bvU=";
  };

  nativeBuildInputs = [
    yarn.yarnBerryConfigHook
    nodejs_20
    yarn
  ];

  env.YARN_ENABLE_SCRIPTS = 0;

  postConfigure = ''
    substituteInPlace .ember-cli \
      --replace-fail "../http/web_ui" "$out"
  '';

  buildPhase = "yarn run ember build --environment=production";

  dontInstall = true;
}
