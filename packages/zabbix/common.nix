{
  lib,
  callPackage,
  zabbixSource,
  agent2VendorHash,
  agent2Platforms ? lib.platforms.unix,
  agent2PostPatch ? "",
}:

{
  server = callPackage ./server.nix { inherit zabbixSource; };
  proxy-sqlite = callPackage ./proxy-sqlite.nix { inherit zabbixSource; };
  proxy-pgsql = callPackage ./proxy-pgsql.nix { inherit zabbixSource; };
  agent2 = callPackage ./agent2.nix {
    inherit
      zabbixSource
      agent2VendorHash
      agent2Platforms
      agent2PostPatch
      ;
  };
  web = callPackage ./web.nix { inherit zabbixSource; };
}
