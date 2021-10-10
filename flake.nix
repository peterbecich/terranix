{
  description = "terranix flake";

  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.terranix-examples.url = "github:terranix/terranix-examples";

  outputs = { self, nixpkgs, flake-utils, terranix-examples }:
    (flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {

        packages.terranix = pkgs.callPackage ./default.nix {
          # as long nix flake is an experimental feature;
          nix = pkgs.nixUnstable;
        };
        defaultPackage = self.packages.${system}.terranix;

        # nix develop
        devShell = pkgs.mkShell {
          buildInputs =
            [ pkgs.terraform_0_15 self.packages.${system}.terranix ];
        };

        # nix run
        defaultApp = self.apps.${system}.test;
        # nix run ".#test"
        apps.test = let
          createTest = testimport:
            let
              tests = import testimport {
                inherit pkgs;
                inherit (pkgs) lib;
                terranix = self.packages.${system}.terranix;
              };
              batsScripts = map (text: pkgs.writeText "test" text) tests;
              allBatsScripts =
                map (file: "${pkgs.bats}/bin/bats ${file}") batsScripts;
            in pkgs.writeScript "test-script"
            (nixpkgs.lib.concatStringsSep "\n" allBatsScripts);
          allTests = [ (createTest ./tests/test.nix) ];
        in pkgs.writers.writeBashBin "check" ''
          set -e
          ${nixpkgs.lib.concatStringsSep "\n" allTests}
        '';

      })) // {

        lib.buildTerranix = { pkgs, terranix_config, ... }@terranix_args:
          let terranixCore = import ./core/default.nix terranix_args;
          in pkgs.writeTextFile {
            name = "terraform-config";
            text = builtins.toJSON terranixCore.config;
            executable = false;
            destination = "/config.tf.json";
          };

        lib.buildOptions = { pkgs, terranix_modules, moduleRootPath ? "/"
          , urlPrefix ? "", urlSuffix ? "", ... }@terranix_args:
          let
            terranixOptions = import ./lib/terranix-doc-json.nix terranix_args;
          in pkgs.stdenv.mkDerivation {
            name = "terranix-options";
            src = self;
            installPhase = ''
              mkdir -p $out
              cat ${terranixOptions}/options.json \
                | ${pkgs.jq}/bin/jq '
                  del(.data) |
                  del(.locals) |
                  del(.module) |
                  del(.output) |
                  del(.provider) |
                  del(.resource) |
                  del(.terraform) |
                  del(.variable)
                  ' > $out/options.json
            '';
          };

        # nix flake init -t github:terranix/terranix#flake
        templates = terranix-examples.templates;
        # nix flake init -t github:terranix/terranix
        defaultTemplate = terranix-examples.defaultTemplate;
      };
}