{
  lib,
  stdenv,
  writeText,
  sources,
}:

let
  phpConfig = writeText "zabbix.conf.php" ''
    <?php
      return require(getenv('ZABBIX_CONFIG'));
    ?>
  '';
in
stdenv.mkDerivation {
  pname = "zabbix-web";
  inherit (sources.zabbix74) version src;

  installPhase = ''
    mkdir -p $out/share/zabbix/
    cp -a ui/. $out/share/zabbix/
    cp ${phpConfig} $out/share/zabbix/conf/zabbix.conf.php
  '';

  meta = {
    description = "Enterprise-class open source distributed monitoring solution (web frontend)";
    homepage = "https://www.zabbix.com/";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [
      bstanderline
      mmahut
    ];
    platforms = lib.platforms.linux;
  };
}
