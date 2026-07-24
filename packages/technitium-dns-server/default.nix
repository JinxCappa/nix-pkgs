{
  buildDotnetModule,
  dotnetCorePackages,
  lib,
  libmsquic,
  sources,
}:

let
  serverSource = sources.technitium-dns-server;
  librarySource = sources.technitium-dns-server-library;

  technitium-dns-server-library = buildDotnetModule {
    pname = "technitium-dns-server-library";
    inherit (librarySource) version src;

    dotnet-sdk = dotnetCorePackages.sdk_10_0;
    dotnet-runtime = dotnetCorePackages.runtime_10_0;
    nugetDeps = ./nuget-deps-library.json;

    projectFile = [
      "TechnitiumLibrary.ByteTree/TechnitiumLibrary.ByteTree.csproj"
      "TechnitiumLibrary.Net/TechnitiumLibrary.Net.csproj"
      "TechnitiumLibrary.Security.OTP/TechnitiumLibrary.Security.OTP.csproj"
    ];

    meta = {
      description = "Libraries required by Technitium DNS Server";
      homepage = "https://github.com/TechnitiumSoftware/TechnitiumLibrary";
      license = lib.licenses.gpl3Only;
      platforms = lib.platforms.linux;
    };
  };

  technitium-dns-server = buildDotnetModule {
    pname = "technitium-dns-server";
    inherit (serverSource) version src;

    dotnet-sdk = dotnetCorePackages.sdk_10_0;
    dotnet-runtime = dotnetCorePackages.aspnetcore_10_0;
    nugetDeps = ./nuget-deps-server.json;

    projectFile = [ "DnsServerApp/DnsServerApp.csproj" ];

    preBuild = ''
      mkdir -p ../TechnitiumLibrary/bin
      cp -R \
        ${technitium-dns-server-library}/lib/technitium-dns-server-library/* \
        ../TechnitiumLibrary/bin/
    '';

    postFixup = ''
      mv "$out/bin/DnsServerApp" "$out/bin/technitium-dns-server"
    '';

    runtimeDeps = [ libmsquic ];

    passthru = {
      library = technitium-dns-server-library;
    };

    meta = {
      description = "Authoritative and recursive DNS server with a web console";
      homepage = "https://technitium.com/dns/";
      changelog = "https://github.com/TechnitiumSoftware/DnsServer/blob/v${serverSource.version}/CHANGELOG.md";
      license = lib.licenses.gpl3Only;
      mainProgram = "technitium-dns-server";
      platforms = lib.platforms.linux;
      sourceProvenance = with lib.sourceTypes; [ fromSource ];
    };
  };
in
assert serverSource.version == librarySource.version;
{
  inherit technitium-dns-server technitium-dns-server-library;

  technitium-dns-server-fetch-deps = technitium-dns-server.fetch-deps;
  technitium-dns-server-library-fetch-deps =
    technitium-dns-server-library.fetch-deps;
}
