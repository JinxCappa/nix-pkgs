{
  lib,
  stdenv,
  callPackage,
  sources,
}:

let
  agent2VendorHash = "sha256-82jEV6IVRsI1163PaAoVJAN+f+yP+T1nwCEqbH7CbEU=";
in
callPackage ../zabbix/common.nix {
  zabbixSource = sources.zabbix80pre;
  inherit agent2VendorHash;
  agent2PostPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Zabbix 8.0's Darwin CGO flags still reference the Agent 1 variants of
    # libraries that an --enable-agent2-only build does not produce.
    substituteInPlace src/go/pkg/zbxlib/globals_darwin.go \
      --replace-fail 'libzbxlogfiles.a' 'libzbxagent2logfiles.a' \
      --replace-fail 'libzbxagentsysinfo.a' 'libzbxagent2sysinfo.a' \
      --replace-fail 'libspecsysinfo.a' 'libzbxagent2specsysinfo.a'

    # The remaining Darwin CGO dependencies are otherwise only built for the
    # classic agent, even though Agent 2 links them as well.
    substituteInPlace src/libs/Makefile.am \
      --replace-fail \
        'if AGENT
AGENT_SUBDIRS = \
	zbxcrypto \
	zbxexec \
	zbxthreads
endif' \
        'if AGENT
AGENT_SUBDIRS = \
	zbxcrypto \
	zbxexec \
	zbxthreads
endif

if AGENT2
AGENT_SUBDIRS = \
	zbxcrypto \
	zbxexec \
	zbxthreads
endif'

    substituteInPlace src/libs/zbxsysinfo/osx/Makefile.am \
      --replace-fail 'noinst_LIBRARIES = libfunclistsysinfo.a libspecsysinfo.a libspechostnamesysinfo.a' \
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
}
