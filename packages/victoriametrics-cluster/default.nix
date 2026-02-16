{
  lib,
  buildGoModule,
  go_1_26,
  sources,
}:

let
  # Extract version number from tag (v1.132.0-cluster -> 1.132.0)
  version = lib.removePrefix "v" (lib.removeSuffix "-cluster" sources.victoriametrics-cluster.version);
in
(buildGoModule.override { go = go_1_26; }) {
  pname = "victoriametrics-cluster";
  inherit version;
  src = sources.victoriametrics-cluster.src;

  vendorHash = null;
  env.CGO_ENABLED = 0;

  # Cluster branch only builds these three components
  # Utilities (vmagent, vmalert, etc.) come from the single/master branch
  subPackages = [
    "app/vminsert"
    "app/vmselect"
    "app/vmstorage"
  ];

  postPatch = ''
    # main module (github.com/VictoriaMetrics/VictoriaMetrics) does not contain package
    # github.com/VictoriaMetrics/VictoriaMetrics/app/vmui/packages/vmui/web
    #
    # This appears to be some kind of test server for development purposes only.
    rm -f app/vmui/packages/vmui/web/{go.mod,main.go}

    # Relax go version to major.minor
    sed -i -E 's/^(go[[:space:]]+[[:digit:]]+\.[[:digit:]]+)\.[[:digit:]]+$/\1/' go.mod
    sed -i -E 's/^(## explicit; go[[:space:]]+[[:digit:]]+\.[[:digit:]]+)\.[[:digit:]]+$/\1/' vendor/modules.txt

    # Increase timeouts in tests to prevent failure on heavily loaded builders
    substituteInPlace lib/storage/storage_test.go \
      --replace-fail "time.After(10 " "time.After(120 " \
      --replace-fail "time.NewTimer(30 " "time.NewTimer(120 " \
      --replace-fail "time.NewTimer(time.Second * 10)" "time.NewTimer(time.Second * 120)" \
  '';

  ldflags = [
    "-s"
    "-w"
    "-X github.com/VictoriaMetrics/VictoriaMetrics/lib/buildinfo.Version=${version}"
  ];

  preCheck = ''
    # `lib/querytracer/tracer_test.go` expects `buildinfo.Version` to be unset
    export ldflags=''${ldflags//=${version}/=}
  '';

  __darwinAllowLocalNetworking = true;

  meta = {
    homepage = "https://victoriametrics.com/";
    description = "VictoriaMetrics cluster version - horizontally scalable time series database";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [
      yorickvp
      ivan
      leona
      shawn8901
      ryan4yin
    ];
    changelog = "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/tag/v${version}-cluster";
    mainProgram = "vminsert";
  };
}
