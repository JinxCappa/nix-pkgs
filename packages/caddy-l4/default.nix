{ caddy, sources, ... }:

caddy.withPlugins {
  plugins = [
    "github.com/mholt/caddy-l4@${sources.caddy-l4.version}"
  ];

  hash = "sha256-C+ksbA6ucY3GUsYHSUhkYoh1gTP8SIAJv0MLjhX8BQM=";
}
