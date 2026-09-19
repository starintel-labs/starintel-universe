{
  description = "StarIntel Universe — canonical integration of the StarIntel system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Component flakes are consumed at their exact pinned submodule commits.
    # Components without flakes (quasar-ui, star-kb) are packaged in-universe.
    starintel-server.url = "git+file:./components/starintel-server";
    quasar.url = "git+file:./components/quasar";
    star-lang.url = "git+file:./components/star-lang";
    star-cl.url = "git+file:./components/star-cl";
    prolog-rlm.url = "git+file:./components/prolog-rlm";
    zara.url = "git+file:./components/zara";
    zara-plugins.url = "git+file:./components/zara-plugins";
    dotfiles.url = "git+file:./components/dotfiles";

    # Non-flake component sources, locked to the submodule pins.
    quasar-ui-src = {
      url = "git+file:./components/quasar-ui";
      flake = false;
    };
    star-kb-src = {
      url = "git+file:./components/star-kb";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
      pkgsFor = system: import nixpkgs { inherit system; };

      lib = nixpkgs.lib;

      hasPkg =
        system: flake: attr:
        (flake.packages or { } ? ${system}) && (flake.packages.${system} ? ${attr});

      moduleSpecialArgs = {
        starintel-flake = self;
      };
    in
    {
      nixosModules = {
        starintel = import ./nix/modules/starintel.nix;
        vanta = import ./distro/vanta/module.nix;
        quasar = import ./nix/modules/quasar.nix;
        starintel-server = import ./nix/modules/starintel-server.nix;
        xdg = import ./nix/modules/xdg.nix;
        user = import ./nix/modules/user.nix;
        default = import ./nix/modules/starintel.nix;
      };

      homeModules = {
        starintel = import ./nix/home/default.nix;
        default = import ./nix/home/default.nix;
      };

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          quasar-ui = pkgs.callPackage ./nix/packages/quasar-ui.nix { src = inputs.quasar-ui-src; };
          star-kb = pkgs.callPackage ./nix/packages/star-kb.nix { src = inputs.star-kb-src; };
          vanta =
            if hasPkg system inputs.zara "zarathushtra" then
              pkgs.callPackage ./distro/vanta/package.nix {
                zaraPkgs = inputs.zara.packages.${system};
              }
            else
              throw "vanta (zara) unavailable on ${system}";

          starintel-server =
            if hasPkg system inputs.starintel-server "default" then
              inputs.starintel-server.packages.${system}.default
            else
              throw "starintel-server unavailable on ${system}";
          quasar =
            if hasPkg system inputs.quasar "quasar-server" then
              inputs.quasar.packages.${system}.quasar-server
            else
              throw "quasar unavailable on ${system}";
          star-lang =
            if hasPkg system inputs.star-lang "star-lang" then
              inputs.star-lang.packages.${system}.star-lang
            else
              throw "star-lang unavailable on ${system}";
          prolog-rlm =
            if hasPkg system inputs.prolog-rlm "prolog-rlm" then
              inputs.prolog-rlm.packages.${system}.prolog-rlm
            else
              throw "prolog-rlm unavailable on ${system}";
          zara =
            if hasPkg system inputs.zara "zarathushtra" then
              inputs.zara.packages.${system}.zarathushtra
            else
              throw "zara unavailable on ${system}";
          zara-plugins =
            if hasPkg system inputs.zara-plugins "zara-plugins" then
              inputs.zara-plugins.packages.${system}.zara-plugins
            else
              throw "zara-plugins unavailable on ${system}";
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          star-cl =
            if inputs.star-cl.packages ? x86_64-linux then
              inputs.star-cl.packages.x86_64-linux.default
            else
              throw "star-cl unavailable";
        }
        // {
          # Aggregate end-user closure: every runtime piece of the universe.
          starintel = pkgs.buildEnv {
            name = "starintel-universe";
            paths = (
              [
                self.packages.${system}.vanta
                self.packages.${system}.quasar-ui
                self.packages.${system}.star-kb
                self.packages.${system}.quasar
                self.packages.${system}.star-lang
                self.packages.${system}.prolog-rlm
                self.packages.${system}.zara-plugins
              ]
              ++ lib.optionals (system == "x86_64-linux") [
                self.packages.${system}.star-cl
              ]
            );
            pathsToLink = [
              "/bin"
              "/share"
            ];
          };
          default = self.packages.${system}.starintel;
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          starintel-iso = self.nixosConfigurations.starintel-os.config.system.build.isoImage;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          nixfmt =
            pkgs.runCommand "nixfmt-check"
              {
                nativeBuildInputs = [
                  pkgs.nixfmt-rfc-style
                  pkgs.findutils
                ];
              }
              ''
                cd ${self}
                find . -maxdepth 4 -name '*.nix' -not -path './components/*' -print0 \
                  | xargs -0 nixfmt --check
                touch $out
              '';

          prolog-policy =
            pkgs.runCommand "prolog-policy"
              {
                nativeBuildInputs = [ pkgs.swi-prolog ];
              }
              ''
                cp -r ${self} work -r
                chmod -R u+w work
                cd work
                swipl -q -g "consult('.prolog/universe'), consult('.prolog/policy_suite'), run_tests, halt(0)" -t "halt(2)"
                touch $out
              '';

          structure =
            pkgs.runCommand "structure-validation"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.git
                  pkgs.swi-prolog
                ];
              }
              ''
                cp -r ${self} work -r
                chmod -R u+w work
                cd work
                bash scripts/validate-structure.sh
                touch $out
              '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              swi-prolog
              nixfmt-rfc-style
              git
              python3
              jq
            ];
            shellHook = ''
              export STARINTEL_UNIVERSE_ROOT="$PWD"
            '';
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);

      nixosConfigurations = {
        starintel-desktop = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = moduleSpecialArgs;
          modules = [
            self.nixosModules.starintel
            (import ./nix/profiles/desktop.nix)
          ];
        };

        starintel-server = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = moduleSpecialArgs;
          modules = [
            self.nixosModules.starintel
            (import ./nix/profiles/server.nix)
          ];
        };

        starintel-developer = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = moduleSpecialArgs;
          modules = [
            self.nixosModules.starintel
            (import ./nix/profiles/developer.nix)
          ];
        };

        starintel-os = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = moduleSpecialArgs;
          modules = [
            (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
            self.nixosModules.starintel
            (import ./nix/iso/starintel-os.nix)
          ];
        };
      };
    };
}
