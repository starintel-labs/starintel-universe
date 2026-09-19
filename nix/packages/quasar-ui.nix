# quasar-ui — packaged in-universe (upstream has no flake).
{
  lib,
  buildNpmPackage,
  nodejs_22,
  src,
}:

buildNpmPackage rec {
  pname = "quasar-ui";
  version = "0.1.0";

  inherit src;

  npmDepsHash = "sha256-OZvAblVkNZcsafsSYWn9APZt5Y89YXkNbeK9XNHtJFU=";

  nodejs = nodejs_22;

  npmBuildScript = "build";
  # quasar-ui's package-lock pins a github: dependency (starintel_doc);
  # its transitive tarballs are not part of the offline npm cache, so the
  # fetch falls back to git (still lockfile-pinned, not floating).
  forceGitDeps = true;
  makeCacheWritable = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/quasar-ui
    cp -r dist/* $out/share/quasar-ui/
    mkdir -p $out/bin
    cat > $out/bin/quasar-ui-serve <<'EOF'
    #!/usr/bin/env bash
    exec ${nodejs_22}/bin/npx --yes serve -s "$out/share/quasar-ui" "$@"
    EOF
    chmod +x $out/bin/quasar-ui-serve
    runHook postInstall
  '';

  meta = with lib; {
    description = "Quasar UI — React control-plane frontend for StarIntel";
    license = licenses.mit;
  };
}
