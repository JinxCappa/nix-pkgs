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
