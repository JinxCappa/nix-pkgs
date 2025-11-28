{
  lib,
  stdenv,
  autoconf,
  automake,
  perl,
  pkg-config,
  curl,
  libevent,
  libiconv,
  openssl,
  pcre2,
  zlib,
  buildPackages,
  odbcSupport ? true,
  unixODBC,
  snmpSupport ? stdenv.buildPlatform == stdenv.hostPlatform,
  net-snmp,
  sshSupport ? true,
  libssh2,
  sqliteSupport ? false,
  sqlite,
  mysqlSupport ? false,
  libmysqlclient,
  postgresqlSupport ? true,
  libpq,
  sources,
}:

# ensure exactly one database type is selected
assert mysqlSupport -> !postgresqlSupport && !sqliteSupport;
assert postgresqlSupport -> !mysqlSupport && !sqliteSupport;
assert sqliteSupport -> !mysqlSupport && !postgresqlSupport;

let
  inherit (lib) optional optionalString;

  fake_mysql_config = buildPackages.writeShellScript "mysql_config" ''
    if [[ "$1" == "--version" ]]; then
      $PKG_CONFIG mysqlclient --modversion
    else
      $PKG_CONFIG mysqlclient $@
    fi
  '';
in
stdenv.mkDerivation {
  pname = "zabbix-proxy";
  inherit (sources.zabbix74) version src;

  enableParallelBuilding = true;

  nativeBuildInputs =
    [
      autoconf
      automake
      perl
      pkg-config
    ]
    ++ optional postgresqlSupport libpq.pg_config;

  buildInputs =
    [
      curl
      libevent
      libiconv
      openssl
      pcre2
      zlib
    ]
    ++ optional odbcSupport unixODBC
    ++ optional snmpSupport net-snmp
    ++ optional sqliteSupport sqlite
    ++ optional sshSupport libssh2
    ++ optional mysqlSupport libmysqlclient
    ++ optional postgresqlSupport libpq;

  configureFlags =
    [
      "--enable-ipv6"
      "--enable-proxy"
      "--with-iconv"
      "--with-libcurl"
      "--with-libevent"
      "--with-libpcre"
      "--with-openssl=${openssl.dev}"
      "--with-zlib=${zlib}"
    ]
    ++ optional odbcSupport "--with-unixodbc"
    ++ optional snmpSupport "--with-net-snmp"
    ++ optional sqliteSupport "--with-sqlite3=${sqlite.dev}"
    ++ optional sshSupport "--with-ssh2=${libssh2.dev}"
    ++ optional mysqlSupport "--with-mysql=${fake_mysql_config}"
    ++ optional postgresqlSupport "--with-postgresql";

  prePatch = ''
    find database -name data.sql -exec sed -i 's|/usr/bin/||g' {} +
    patchShebangs create/bin/*.pl create/bin/*.sh
  '';

  postBuild =
    optionalString sqliteSupport ''
      make -C database/sqlite3 schema.sql
    ''
    + optionalString postgresqlSupport ''
      make -C database/postgresql schema.sql
    ''
    + optionalString mysqlSupport ''
      make -C database/mysql schema.sql
    '';

  preConfigure = ''
    for i in $(find . -type f -name "*.m4"); do
      substituteInPlace $i \
        --replace 'test -x "$PKG_CONFIG"' 'type -P "$PKG_CONFIG" >/dev/null'
    done
    ./bootstrap.sh
  '';

  makeFlags = [
    "AR:=$(AR)"
    "RANLIB:=$(RANLIB)"
  ];

  postInstall =
    ''
      mkdir -p $out/share/zabbix/database/
    ''
    + optionalString sqliteSupport ''
      mkdir -p $out/share/zabbix/database/sqlite3
      cp -prvd database/sqlite3/*.sql $out/share/zabbix/database/sqlite3/
    ''
    + optionalString mysqlSupport ''
      mkdir -p $out/share/zabbix/database/mysql
      cp -prvd database/mysql/*.sql $out/share/zabbix/database/mysql/
    ''
    + optionalString postgresqlSupport ''
      mkdir -p $out/share/zabbix/database/postgresql
      cp -prvd database/postgresql/*.sql $out/share/zabbix/database/postgresql/
    '';

  meta = {
    description = "Enterprise-class open source distributed monitoring solution (client-server proxy)";
    homepage = "https://www.zabbix.com/";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [
      bstanderline
      mmahut
    ];
    platforms = lib.platforms.linux;
  };
}
