% Nix integration facts (verified 2026-09-19, nix 2.33).
nix_fact(submodule_flake_inputs, 'path: inputs cannot see inside submodules; use git+file:./components/<name> (each submodule is its own repo)').
nix_fact(non_flake_components, 'flake=false git+file inputs for quasar-ui/star-kb sources; lock records the submodule pin').
nix_fact(sandbox_checks, 'nix flake check copies only git-TRACKED files: no submodule contents; gate submodule/dir-existence tests on in_full_worktree/0').
nix_fact(iso_sysctl_conflict, 'installation-device + services.redis both set vm.overcommit_memory plainly; disable withValkey on the ISO profile').
nix_fact(npm_builds, 'quasar-ui needs makeCacheWritable=true + forceGitDeps=true (github: dep) and a computed npmDepsHash').
nix_fact(redis_module_name, 'nixos-unstable exposes services.redis (no services.valkey module) at this ref').
