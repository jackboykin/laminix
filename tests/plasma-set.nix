{
  nixpkgs,
  module,
  system,
}:
let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};

  # Turn on everything the Plasma module installs something for.
  sys = lib.nixosSystem {
    inherit system;
    modules = [
      module
      {
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = "26.11";
        services.desktopManager.plasma6.enable = true;
        environment.laminix.enable = true;
        programs.kde-pim = {
          kmail = true;
          kontact = true;
          merkuro = true;
        };
        hardware.bluetooth.enable = true;
        hardware.sane.enable = true;
        hardware.sensor.iio.enable = true;
        networking.networkmanager.enable = true;
        services.colord.enable = true;
        services.flatpak.enable = true;
        services.fwupd.enable = true;
        services.hardware.bolt.enable = true;
        services.printing.enable = true;
        services.samba.enable = true;
        services.xserver.wacom.enable = true;
      }
    ];
  };

  # Left out on purpose: kio-extras-kf5 would fold a whole Qt 5 stack into
  # the profile for one rarely run helper, and the system bus starts
  # kdenetwork-filesharing's only wrapper, so its shim would change nothing.
  skipped = [
    "kio-extras-kf5"
    "kdenetwork-filesharing"
  ];

  kde =
    p:
    let
      n = lib.getName p;
    in
    pkgs.kdePackages ? ${n} && pkgs.kdePackages.${n}.outPath == p.outPath && !lib.elem n skipped;
  left = lib.filter (p: !(p.laminix or false) && kde p) sys.config.environment.systemPackages;
  shim = pkgs.callPackage ../shim.nix { } {
    pairs = [ ];
    exclude = [ ];
  };
  scanned = lib.concatMap (p: (shim p).srcPaths) (lib.unique left);
in
pkgs.runCommand "laminix-test-plasma-set" { nativeBuildInputs = [ pkgs.binutils-unwrapped ]; } ''
  for p in ${toString scanned}; do
    while IFS= read -r -d "" f; do
      if [[ -n $(${pkgs.makeBinaryWrapper.extractCmd} "$f") ]]; then
        echo "laminix: Plasma installs $p, whose $f is a binary wrapper, but the full set leaves it out" >&2
        exit 1
      fi
    done < <(find "$p" -type f -executable -print0)
  done
  touch $out
''
