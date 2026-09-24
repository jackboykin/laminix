{
  description = "Move wrapped NixOS packages' per-dependency search paths into the profile";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
        ] (system: f nixpkgs.legacyPackages.${system});
    in
    {
      nixosModules.default = ./module.nix;

      lib.shim = pkgs: pkgs.callPackage ./shim.nix { };

      packages = forAllSystems (
        pkgs:
        let
          audit = pkgs.callPackage ./audit.nix { };
        in
        {
          inherit audit;
          default = audit;
        }
      );

      checks = forAllSystems (pkgs: import ./tests { inherit self nixpkgs pkgs; });

      formatter = forAllSystems (pkgs: pkgs.callPackage ./treefmt.nix { });
    };
}
