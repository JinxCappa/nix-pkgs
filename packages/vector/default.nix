{
  stdenv,
  lib,
  rustPlatform,
  pkg-config,
  openssl,
  protobuf,
  rdkafka,
  oniguruma,
  zstd,
  rust-jemalloc-sys,
  rust-jemalloc-sys-unprefixed,
  libiconv,
  coreutils,
  tzdata,
  cmake,
  perl,
  git,
  nixosTests,
  darwin,
  zlib,
  sources,
}:

let
  # Strip the "v" prefix from version (e.g., "v0.51.1" -> "0.51.1") 
  version = lib.removePrefix "v" sources.vector.version;
in
rustPlatform.buildRustPackage {
  pname = sources.vector.pname;
  inherit version;
  src = sources.vector.src;

  # cargoHash needs to be updated when source changes
  # Build will fail with correct hash if outdated
  cargoHash = "sha256-PHwgWQE59CIuF4eXqX7JVpPExu/OUj88llcFeXzDGOM=";

  nativeBuildInputs =
    [
      pkg-config
      cmake
      perl
      git
      rustPlatform.bindgenHook
    ]
    # Provides the mig command used by the build scripts
    ++ lib.optional stdenv.hostPlatform.isDarwin darwin.bootstrap_cmds;
  buildInputs =
    [
      oniguruma
      openssl
      protobuf
      rdkafka
      zstd
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ rust-jemalloc-sys-unprefixed ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      rust-jemalloc-sys
      libiconv
      coreutils
      zlib
    ];

  # Fix build with gcc 15
  # https://github.com/vectordotdev/vector/issues/22888
  env.NIX_CFLAGS_COMPILE = "-std=gnu17";

  RUSTFLAGS = "-A dependency_on_unit_never_type_fallback -A dead_code -A mismatched_lifetime_syntaxes";

  # Without this, we get SIGSEGV failure
  RUST_MIN_STACK = 33554432;

  # needed for internal protobuf c wrapper library
  PROTOC = "${protobuf}/bin/protoc";
  PROTOC_INCLUDE = "${protobuf}/include";
  RUSTONIG_SYSTEM_LIBONIG = true;

  TZDIR = "${tzdata}/share/zoneinfo";

  # needed to dynamically link rdkafka
  CARGO_FEATURE_DYNAMIC_LINKING = 1;

  CARGO_PROFILE_RELEASE_LTO = "fat";
  CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";

  # In case anything goes wrong.
  RUST_BACKTRACE = "full";

  doCheck = false;

  checkFlags = [
    "--skip=sinks::loki::tests::healthcheck_grafana_cloud"
    "--skip=kubernetes::api_watcher::tests::test_stream_errors"
    "--skip=sources::socket::test::tcp_with_tls_intermediate_ca"
    "--skip=sources::host_metrics::cgroups::tests::generates_cgroups_metrics"
    "--skip=sources::aws_kinesis_firehose::tests::aws_kinesis_firehose_forwards_events"
    "--skip=sources::aws_kinesis_firehose::tests::aws_kinesis_firehose_forwards_events_gzip_request"
    "--skip=sources::aws_kinesis_firehose::tests::handles_acknowledgement_failure"
  ];

  postPatch = ''
    substituteInPlace ./src/dns.rs \
      --replace-fail "#[tokio::test]" ""

    substituteInPlace ./lib/vector-config-macros/src/lib.rs \
      --replace-fail "#![deny(warnings)]" ""
  '';

  passthru.tests = {
    inherit (nixosTests) vector;
  };

  meta = with lib; {
    description = "High-performance observability data pipeline";
    homepage = "https://github.com/vectordotdev/vector";
    license = licenses.mpl20;
    maintainers = with maintainers; [
      thoughtpolice
      happysalada
    ];
    platforms = with platforms; all;
    mainProgram = "vector";
  };
}
