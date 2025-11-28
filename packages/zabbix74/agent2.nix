{
  lib,
  buildGoModule,
  autoconf,
  automake,
  perl,
  pkg-config,
  libiconv,
  openssl,
  pcre2,
  zlib,
  sources,
}:

buildGoModule {
  pname = "zabbix-agent2";
  inherit (sources.zabbix74) version src;

  modRoot = "src/go";

  vendorHash = "sha256-Csq6U2/i+wVPOsWPgK3BsGbLhlhAWHFInCGNgPcKlf8=";

  nativeBuildInputs = [
    autoconf
    automake
    perl
    pkg-config
  ];

  buildInputs = [
    libiconv
    openssl
    pcre2
    zlib
  ];

  # GitHub source has inconsistent vendor directory; also patch for reproducibility
  postPatch = ''
    rm -rf src/go/vendor
    patchShebangs create/bin/*.pl create/bin/*.sh
    substituteInPlace src/go/Makefile.am \
      --replace '`go env GOOS`' "$GOOS" \
      --replace '`go env GOARCH`' "$GOARCH" \
      --replace '`date +%H:%M:%S`' "00:00:00" \
      --replace '`date +"%b %_d %Y"`' "Jan 1 1970"
  '';

  # manually configure the c dependencies
  preConfigure = ''
    for i in $(find . -type f -name "*.m4"); do
      substituteInPlace $i \
        --replace 'test -x "$PKG_CONFIG"' 'type -P "$PKG_CONFIG" >/dev/null'
    done
    ./bootstrap.sh
    ./configure \
      --prefix=${placeholder "out"} \
      --enable-agent2 \
      --enable-ipv6 \
      --with-iconv \
      --with-libpcre \
      --with-openssl=${openssl.dev}
  '';

  # zabbix build process is complex to get right in nix...
  # use automake to build the go project ensuring proper access to the go vendor directory
  buildPhase = ''
    cd ../..
    make
  '';

  installPhase = ''
    mkdir -p $out/sbin

    install -Dm0644 src/go/conf/zabbix_agent2.conf $out/etc/zabbix_agent2.conf
    install -Dm0755 src/go/bin/zabbix_agent2 $out/bin/zabbix_agent2

    # create a symlink which is compatible with the zabbixAgent module
    ln -s $out/bin/zabbix_agent2 $out/sbin/zabbix_agentd
  '';

  meta = {
    description = "Enterprise-class open source distributed monitoring solution (client-side agent)";
    homepage = "https://www.zabbix.com/";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [
      aanderse
      bstanderline
    ];
    platforms = lib.platforms.unix;
  };
}
