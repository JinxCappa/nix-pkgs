{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-O6GuC2q1mA/Fa0utb2Yg7ZE73iq13oVYhJI1IVyOvog=";
}
