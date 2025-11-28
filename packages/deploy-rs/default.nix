{
  lib,
  rustPlatform,
  sources,
}:

rustPlatform.buildRustPackage {
  pname = sources.deploy-rs.pname;
  version = "0-unstable-${sources.deploy-rs.date}";
  src = sources.deploy-rs.src;

  # cargoHash needs to be updated when source changes
  # Build will fail with correct hash if outdated
  cargoHash = "sha256-9O93YTEz+e2oxenE0gwxsbz55clbKo9+37yVOqz7ErE=";

  meta = {
    description = "Multi-profile Nix-flake deploy tool";
    homepage = "https://github.com/serokell/deploy-rs";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [
      teutat3s
      jk
    ];
    mainProgram = "deploy";
  };
}
