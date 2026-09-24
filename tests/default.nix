{
  self,
  nixpkgs,
  pkgs,
}:
let
  module = self.nixosModules.default;
in
import ./shim.nix {
  inherit pkgs;
  shim = self.lib.shim pkgs;
  checks = ../checks.sh;
}
// {
  module = import ./module.nix {
    inherit nixpkgs module;
    inherit (pkgs.stdenv.hostPlatform) system;
  };
  plasma = import ./plasma.nix { inherit pkgs module; };
}
