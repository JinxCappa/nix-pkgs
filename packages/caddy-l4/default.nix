{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-wZNe8M044n4POa5LhvzsvZiQ7A0uhI49bdvEtKj1IyE=";
}
