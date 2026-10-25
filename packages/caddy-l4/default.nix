{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-FwGmHobFqBkEI7LN/YaPsL0t+dJn8uZMhCp9asDEsYw=";
}
