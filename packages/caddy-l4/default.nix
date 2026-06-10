{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-/ebF+f235CR36VKfCITtQWXr9wojpgsszxxnZ8HeCd0=";
}
