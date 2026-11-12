{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-8jrb0Ec1OZS+ymHSBStlILnwTr+98XayLx4lB96wCzA=";
}
