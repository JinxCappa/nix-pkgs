args@{
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

import ../zabbix74 (args // {
  zabbixSource = sources.zabbix80pre;
  agent2VendorHash = "sha256-nyGklNLZVJeIGq4d0iATfP7k+zI56a7GdOmHksemFpA=";
  agent2PostPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace src/libs/zbxsysinfo/osx/Makefile.am \
      --replace 'noinst_LIBRARIES = libfunclistsysinfo.a libspecsysinfo.a libspechostnamesysinfo.a' \
        'noinst_LIBRARIES = libfunclistsysinfo.a libspecsysinfo.a libzbxagent2specsysinfo.a libspechostnamesysinfo.a'
    cat >> src/libs/zbxsysinfo/osx/Makefile.am <<'EOF'

libzbxagent2specsysinfo_a_CFLAGS = \
	-I$(top_srcdir)/src/zabbix_agent \
	-DWITH_AGENT2_METRICS

libzbxagent2specsysinfo_a_SOURCES = \
	boottime.c \
	cpu.c \
	diskio.c \
	diskspace.c \
	inodes.c inodes.h \
	kernel.c \
	memory.c \
	net.c \
	software.c \
	system.c \
	uptime.c
EOF
  '';
})
