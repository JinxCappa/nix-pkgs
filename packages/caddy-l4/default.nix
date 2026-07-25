{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-UIv8PxtJMlX7qClnPazFsSSl7G1BzsTT8VjrMIfB46Q=";
}
