{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-5qVQ6a5PeSa2NmU3Oa7GZhq7wWNB6pfqWSouU1vpgbg=";
}
