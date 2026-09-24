{
  description = "Move wrapped NixOS packages' per-dependency search paths into the profile";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      nixosModules.default = ./module.nix;

      lib.shim = pkgs: import ./shim.nix { inherit (pkgs) lib runCommandLocal makeBinaryWrapper; };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = self.packages.${system}.audit;
          audit = pkgs.writeShellApplication {
            name = "laminix-audit";
            runtimeInputs = [
              pkgs.strace
              pkgs.gawk
              pkgs.coreutils
            ];
            text = builtins.readFile ./audit.sh;
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./tests/shim.nix {
          inherit pkgs;
          shim = self.lib.shim pkgs;
          checks = ./checks.sh;
        }
        // {
          module = import ./tests/module.nix {
            inherit nixpkgs system;
            module = self.nixosModules.default;
          };
          plasma = import ./tests/plasma.nix {
            inherit pkgs;
            module = self.nixosModules.default;
          };
        }
      );

      # nixpkgs' own Nix formatting and lint, from its ci/treefmt.nix.
      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.treefmt.withConfig {
          runtimeInputs = [
            pkgs.nixf-diagnose
            pkgs.nixfmt
            pkgs.markdown-code-runner
          ];
          settings = {
            tree-root-file = "flake.nix";
            on-unmatched = "debug";
            formatter = {
              nixf-diagnose = {
                command = "nixf-diagnose";
                options = [ "--auto-fix" ];
                includes = [ "*.nix" ];
                priority = -1;
              };
              nixfmt = {
                command = "nixfmt";
                includes = [ "*.nix" ];
              };
              markdown-code-runner = {
                command = "mdcr";
                options = [
                  "--config=${
                    pkgs.writers.writeTOML "markdown-code-runner-config" {
                      presets.nixfmt = {
                        language = "nix";
                        command = [ "nixfmt" ];
                      };
                    }
                  }"
                ];
                includes = [ "*.md" ];
              };
            };
          };
        }
      );
    };
}
