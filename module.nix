{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.environment.laminix;
  inherit (lib) mkOption types;

  # Wrappers set NIXPKGS_QT*_QML_IMPORT_PATH; Qt also reads QML2_IMPORT_PATH.
  aliases = {
    NIXPKGS_QT5_QML_IMPORT_PATH = "QML2_IMPORT_PATH";
    NIXPKGS_QT6_QML_IMPORT_PATH = "QML2_IMPORT_PATH";
  };
  session = config.environment.profileRelativeSessionVariables;
  suffixes = removeAttrs (
    session // lib.mapAttrs (_: var: session.${var} or [ ]) aliases
  ) cfg.keepVariables;
  pairs = lib.concatLists (
    lib.mapAttrsToList (var: map (s: "${var}:${lib.removePrefix "/" s}")) suffixes
  );
  searched = lib.unique (map (p: lib.last (lib.splitString ":" p)) pairs);

  shim =
    pkgs':
    pkgs'.callPackage ./shim.nix { } {
      inherit pairs;
      inherit (cfg) exclude;
    };

  paths = map (lib.splitString ".") cfg.packages;
  # Keys that depend on prev make pkgs recurse; missing paths fail an assertion.
  overlay =
    final: prev:
    lib.genAttrs (lib.unique (map lib.head paths)) (
      top:
      if prev ? ${top} then
        lib.updateManyAttrsByPath (map (p: {
          path = lib.tail p;
          update = shim final;
        }) (lib.filter (p: lib.head p == top && lib.hasAttrByPath p prev) paths)) prev.${top}
      else
        null
    );
in
{
  options.environment.laminix = {
    enable = lib.mkEnableOption "moving wrapped packages' per-dependency search paths into the profiles that install them";

    packages = mkOption {
      type = types.listOf types.str;
      default = lib.optionals config.services.desktopManager.plasma6.enable [
        "kdePackages.plasma-workspace"
        "kdePackages.kwin"
        "kdePackages.dolphin"
        "kdePackages.konsole"
        "kdePackages.kate"
      ];
      defaultText = lib.literalMD "Plasma's session and its most-launched apps when Plasma 6 is enabled, else none";
      example = [
        "kdePackages.okular"
        "kdePackages.spectacle"
      ];
      description = ''
        Attribute paths in `pkgs` to replace with shims. Each must have
        binary wrappers from `makeBinaryWrapper`; the build fails otherwise.
        A shim only works from a profile the session searches, such as
        {option}`environment.systemPackages` or
        {option}`users.users.<name>.packages`: `nix run` on one misses its
        dependencies.
      '';
    };

    keepVariables = mkOption {
      type = types.listOf types.str;
      default = [ "PATH" ];
      description = ''
        Variables the wrappers keep even though the session searches profiles
        for them. Folding `PATH` dirs into the profile would put every
        dependency's commands on everyone's `PATH`.
      '';
    };

    exclude = mkOption {
      type = types.listOf types.str;
      default = [
        "share/dbus-1"
        "share/systemd"
        "share/polkit-1"
        "share/xdg-desktop-portal"
        "share/wayland-sessions"
        "share/xsessions"
        "share/applications"
        "etc/xdg/autostart"
        "etc/xdg/systemd"
        "share/fish"
        "share/bash-completion"
        "share/zsh"
      ];
      description = ''
        Layer paths left out of the profile. A wrapper showed a dependency's
        dirs to one program, but daemons, shells, and menus read these straight
        from the profile, so folding them in would register the dependency's
        services, autostart entries, menu entries, and completions for
        everyone. Each entry names one directory directly below a searched
        path, such as `share/dbus-1`.
      '';
    };

    pruneProfiles = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Search only {file}`/etc/profiles/per-user/$USER` and
        {file}`/run/current-system/sw`. Every entry in
        {option}`environment.profiles` is probed on every lookup, whether or
        not it exists. Packages from `nix-env`, `nix profile`, or standalone
        Home Manager drop out of every search path, `PATH` included.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      map (p: {
        assertion = (lib.attrByPath p null pkgs).laminix or false;
        message = "environment.laminix.packages: pkgs.${lib.concatStringsSep "." p} is not a shim: it doesn't exist, or a later overlay rebuilt its scope.";
      }) paths
      ++ map (e: {
        assertion =
          lib.elem (dirOf e) searched
          && !lib.any (s: lib.hasPrefix "${s}/" (dirOf e)) searched
          && !lib.elem e searched;
        message = "environment.laminix.exclude: ${e} is not one directory directly below a searched path that no other searched path contains (${toString searched}).";
      }) cfg.exclude;

    nixpkgs.overlays = [ overlay ];

    # Shims drop whole PKG/share dirs, so the profile must link them whole.
    environment.pathsToLink = map (s: "/${s}") searched;

    environment.profiles = lib.mkIf cfg.pruneProfiles (
      lib.mkForce [
        "/etc/profiles/per-user/$USER"
        "/run/current-system/sw"
      ]
    );

    environment.extraSetup = ''
      extractCmd=${pkgs.makeBinaryWrapper.extractCmd}
      PATH=$PATH:${pkgs.buildPackages.binutils-unwrapped}/bin
      source ${./check-profile.sh}
    '';
  };
}
