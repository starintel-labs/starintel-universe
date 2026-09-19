# star-kb — RAGE research control plane (upstream has no flake).
# Ships the repository's validation tooling as a runnable application;
# tests run the upstream suite directly in CI.
{
  lib,
  stdenv,
  python3,
  src,
}:

stdenv.mkDerivation rec {
  pname = "star-kb";
  version = "0.1.0";

  inherit src;

  buildInputs = [ python3 ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/star-kb $out/bin
    cp -r scripts rage.toml roam $out/libexec/star-kb/

    for tool in save-research implement mark-design task_steward sync validate-docs; do
      if [ -f "$out/libexec/star-kb/scripts/$tool.py" ]; then
        cat > "$out/bin/star-kb-$tool" <<EOF
    #!/usr/bin/env bash
    exec ${python3}/bin/python3 "$out/libexec/star-kb/scripts/$tool.py" "\$@"
    EOF
        chmod +x "$out/bin/star-kb-$tool"
      fi
    done
    runHook postInstall
  '';

  meta = with lib; {
    description = "STAR-KB — RAGE research control plane tooling";
    license = licenses.mit;
  };
}
