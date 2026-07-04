{
  lib,
  buildGo125Module,
  stdenv,
  go,
  sources,
}:

buildGo125Module {
  pname = "sops-install-secrets";
  version = "0.0.1";

  src = lib.sourceByRegex sources.sops-install-secrets.src [
    "go\\.(mod|sum)"
    "pkgs"
    "pkgs/sops-install-secrets.*"
  ];

  subPackages = [ "pkgs/sops-install-secrets" ];

  doCheck = false;

  outputs = [ "out" ] ++ lib.optional stdenv.isLinux "unittest";

  postInstall =
    ''
      go test -c ./pkgs/sops-install-secrets
    ''
    + lib.optionalString stdenv.isLinux ''
      install -D ./sops-install-secrets.test $unittest/bin/sops-install-secrets.test
      if command -v remove-references-to >/dev/null; then
        remove-references-to -t ${go} $unittest/bin/sops-install-secrets.test
      fi
    '';

  vendorHash = "sha256-3Ii7cWVfUvs+qjl497NxpedIDDRKnbD+jGuOG40iHmE=";

  meta = {
    description = "Atomic secret provisioning based on sops";
    homepage = "https://github.com/Mic92/sops-nix";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ mic92 ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "sops-install-secrets";
  };
}
