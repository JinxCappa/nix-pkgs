{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-lgeo9zTTTx0S2CI8f4LgfoDngdvmlwiNM5QwS5e4ozw=";
}
