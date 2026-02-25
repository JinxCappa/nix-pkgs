{
  lib,
  buildNpmPackage,
  nodejs_20,
  sources,
}:

buildNpmPackage {
  inherit (sources.claude-code) pname version src;

  nodejs = nodejs_20; # required for sandboxed Nix builds on Darwin

  # npmDepsHash needs to be updated manually when version changes
  # Run: npm install --package-lock-only @anthropic-ai/claude-code@VERSION
  # Then: prefetch-npm-deps package-lock.json
  npmDepsHash = "sha256-ZbxG7On2v0SBbJwoY9QZuae30wlHDddaNRGY7rU7fJ4=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  dontNpmBuild = true;

  AUTHORIZED = "1";

  # `claude-code` tries to auto-update by default, this disables that functionality.
  # https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview#environment-variables
  # The DEV=true env var causes claude to crash with `TypeError: window.WebSocket is not a constructor`
  postInstall = ''
    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --unset DEV
  '';

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [
      malo
      markus1189
      omarjatoi
    ];
    mainProgram = "claude";
  };
}
