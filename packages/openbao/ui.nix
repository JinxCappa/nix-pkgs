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
    hash = "sha256-XK3ZVnzOTbFzrpPgaz1cx7okTycLhrvBHk9P2Nwv1cg=";
    # Workaround: nixpkgs-unstable nix-prefetch-git ships a versioned binary name
    preBuild = ''
      if ! command -v nix-prefetch-git &>/dev/null; then
        mkdir -p "$TMPDIR/compat-bin"
        for dir in $(echo "$PATH" | tr ':' '\n'); do
          for bin in "$dir"/nix-prefetch-git-*; do
            if [ -x "$bin" ]; then
              ln -s "$bin" "$TMPDIR/compat-bin/nix-prefetch-git"
              export PATH="$TMPDIR/compat-bin:$PATH"
              break 2
            fi
          done
        done
      fi
    '';
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
