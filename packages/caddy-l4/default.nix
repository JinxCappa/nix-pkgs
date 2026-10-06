{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-Dz510teYCUvEA7MR8ERpaKsDHS5dBCDO+AjszV96si4=";
}
