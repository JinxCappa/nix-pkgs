{
  lib,
  stdenv,
  buildGoModule,
  buildPackages,
  autoconf,
  automake,
  perl,
  pkg-config,
  writeText,
  curl,
  libevent,
  libiconv,
  libxml2,
  openssl,
  pcre2,
  zlib,
  iksemel,
  openldap,
  unixODBC,
  net-snmp,
  libssh2,
  libmysqlclient,
  libpq,
  openipmi,
  sqlite,
  sources,
  zabbixSource ? sources.zabbix74,
  agent2VendorHash ? "sha256-59Q6dnpQTYZ7oYPz56ukew8BU7Bo7gfcDvIXD9KvkME=",
  agent2Platforms ? lib.platforms.unix,
  agent2PostPatch ? "",
}:

let
  callPackage = lib.callPackageWith {
    inherit
      lib
      stdenv
      buildGoModule
      buildPackages
      autoconf
      automake
      perl
      pkg-config
      writeText
      curl
      libevent
      libiconv
      libxml2
      openssl
      pcre2
      zlib
      iksemel
      openldap
      unixODBC
      net-snmp
      libssh2
      libmysqlclient
      libpq
      openipmi
      sqlite
      sources
      zabbixSource
      agent2VendorHash
      agent2Platforms
      agent2PostPatch
      ;
  };
in
{
  server = callPackage ./server.nix { };
  proxy-sqlite = callPackage ./proxy-sqlite.nix { };
  proxy-pgsql = callPackage ./proxy-pgsql.nix { };
  agent2 = callPackage ./agent2.nix { };
  web = callPackage ./web.nix { };
}
