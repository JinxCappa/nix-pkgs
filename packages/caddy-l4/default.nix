{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-5rSXcltiRaAG253V1ytKF/UBXWWIHAPRK2KPHdRnJrA=";
}
