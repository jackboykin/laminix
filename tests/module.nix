{
  nixpkgs,
  module,
  system,
}:
let
  inherit (nixpkgs) lib;

  eval =
    extra:
    lib.nixosSystem {
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
          qt.enable = true;
          environment.laminix = {
            enable = true;
            packages = [ "hello" ];
          };
        }
        extra
      ];
    };

  failed = sys: map (a: a.message) (lib.filter (a: !a.assertion) sys.config.assertions);
  pairsOf = sys: lib.splitString " " sys.pkgs.hello.pairs;

  base = eval { };
  kept = eval {
    environment.laminix.keepVariables = [
      "PATH"
      "NIXPKGS_QT6_QML_IMPORT_PATH"
    ];
  };
  typo = eval {
    environment.laminix.packages = lib.mkForce [
      "hello"
      "kdePackages.dolphinn"
    ];
  };
  rebuilt = eval {
    nixpkgs.overlays = lib.mkAfter [ (_: _: { inherit (nixpkgs.legacyPackages.${system}) hello; }) ];
  };
  deepExclude = eval { environment.laminix.exclude = lib.mkForce [ "share/dbus-1/services" ]; };
  nestedExclude = eval { environment.laminix.exclude = lib.mkForce [ "share/icons/hicolor" ]; };
  # less installs its man output, which checkMeta requires to exist.
  strict = eval {
    nixpkgs.config.checkMeta = true;
    environment.laminix.packages = lib.mkForce [ "less" ];
  };

  checks = {
    "NIXPKGS_QT6_QML_IMPORT_PATH flattens where the session searches QML2_IMPORT_PATH" =
      lib.elem "NIXPKGS_QT6_QML_IMPORT_PATH:lib/qt-6/qml" (pairsOf base);
    "PATH is kept" = !lib.any (lib.hasPrefix "PATH:") (pairsOf base);
    "keepVariables keeps an aliased variable" =
      !lib.any (lib.hasPrefix "NIXPKGS_QT6_QML_IMPORT_PATH:") (pairsOf kept);
    "the profile links each searched path whole" =
      lib.all (p: lib.elem p base.config.environment.pathsToLink)
        [
          "/share"
          "/etc/xdg"
          "/lib/qt-6/qml"
        ];
    "a clean configuration passes its assertions" = failed base == [ ];
    "a misspelled package fails an assertion" = lib.any (lib.hasInfix "kdePackages.dolphinn") (
      failed typo
    );
    "a later overlay replacing a shim fails an assertion" =
      lib.any (lib.hasInfix "pkgs.hello is not a shim") (failed rebuilt);
    "an exclude below the top level fails an assertion" =
      lib.any (lib.hasInfix "share/dbus-1/services") (failed deepExclude);
    "an exclude under a nested searched path fails an assertion" =
      lib.any (lib.hasInfix "share/icons/hicolor") (failed nestedExclude);
    "shims pass checkMeta" = lib.isString strict.pkgs.less.drvPath;
    "an override is the plain package" =
      let
        secure = strict.pkgs.less.override { withSecure = true; };
      in
      !(secure.laminix or false) && secure.drvPath != strict.pkgs.less.drvPath;
    "an overrideAttrs is the plain package" =
      let
        unchecked = strict.pkgs.less.overrideAttrs { doCheck = false; };
      in
      !(unchecked.laminix or false) && unchecked.drvPath != strict.pkgs.less.drvPath;
  };
  broken = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
nixpkgs.legacyPackages.${system}.runCommand "laminix-test-module" { } (
  if broken == [ ] then
    "touch $out"
  else
    throw "laminix module tests failed: ${lib.concatStringsSep "; " broken}"
)
