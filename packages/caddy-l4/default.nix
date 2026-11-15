{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-N4LqqEcmChyzsTBSC0/6htPYyLoAi15mMaTm7djgEYs=";
}
