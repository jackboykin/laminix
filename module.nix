{
  config,
  options,
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

  args = options._module.args;
  base =
    (lib.modules.mergeAttrDefinitionsWithPrio (
      args
      // {
        definitionsWithLocations = lib.filter (d: d.file != __curPos.file) args.definitionsWithLocations;
      }
    )).pkgs.value;

  shim = base.callPackage ./shim.nix { } {
    inherit pairs;
    inherit (cfg) exclude;
  };

  # What services.desktopManager.plasma6 installs that has binary wrappers.
  # A name missing from pkgs, as union is on 26.05, is skipped.
  plasmaBase = [
    "ark"
    "discover"
    "dolphin"
    "elisa"
    "gwenview"
    "kate"
    "khelpcenter"
    "kinfocenter"
    "kmenuedit"
    "konsole"
    "kwalletmanager"
    "kwin"
    "okular"
    "plasma-desktop"
    "plasma-systemmonitor"
    "plasma-workspace"
    "spectacle"
    "systemsettings"
  ];
  plasmaSets = {
    none = [ ];
    base = plasmaBase;
    full = plasmaBase ++ [
      "baloo"
      "baloo-widgets"
      "breeze"
      "drkonqi"
      "frameworkintegration"
      "kactivitymanagerd"
      "kauth"
      "kcmutils"
      "kconfig"
      "kde-cli-tools"
      "kde-gtk-config"
      "kde-inotify-survey"
      "kded"
      "kdeplasma-addons"
      "kfilemetadata"
      "kglobalacceld"
      "kguiaddons"
      "kiconthemes"
      "kio"
      "kio-admin"
      "kio-extras"
      "kio-fuse"
      "knighttime"
      "kpackage"
      "krdp"
      "kscreen"
      "kscreenlocker"
      "kservice"
      "ksystemstats"
      "ktexteditor"
      "kunifiedpush"
      "kwallet"
      "kwin-x11"
      "kwrited"
      "libkscreen"
      "libksysguard"
      "plasma-activities"
      "plasma-browser-integration"
      "plasma-keyboard"
      "polkit-kde-agent-1"
      "solid"
      "union"
      "xdg-desktop-portal-kde"
    ];
  };
  plasmaPaths = map (p: [
    "kdePackages"
    p
  ]) plasmaSets.${cfg.plasma};
  userPaths = map (lib.splitString ".") cfg.packages;
  paths = lib.unique (plasmaPaths ++ userPaths);
  present = lib.filter (p: lib.hasAttrByPath p base) paths;
  install =
    pkg:
    shim pkg
    // lib.intersectAttrs {
      override = null;
      overrideAttrs = null;
    } pkg;
  shimmed = lib.updateManyAttrsByPath (map (path: {
    inherit path;
    update = install;
  }) present) base;
in
{
  _file = __curPos.file;

  options.environment.laminix = {
    enable = lib.mkEnableOption "moving wrapped packages' per-dependency search paths into the profiles that install them";

    plasma = mkOption {
      type = types.enum [
        "none"
        "base"
        "full"
      ];
      default = if config.services.desktopManager.plasma6.enable then "full" else "none";
      defaultText = lib.literalExpression ''if config.services.desktopManager.plasma6.enable then "full" else "none"'';
      description = ''
        Which of Plasma's packages to shim. `"base"` is the desktop and the
        apps Plasma installs: ${lib.concatMapStringsSep ", " (p: "`${p}`") plasmaSets.base}.
        `"full"` adds its background services and the frameworks behind them:
        ${lib.concatMapStringsSep ", " (p: "`${p}`") (lib.subtractLists plasmaSets.base plasmaSets.full)}.
      '';
    };

    packages = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "kdePackages.kmail"
        "obs-studio"
      ];
      description = ''
        Attribute paths in `pkgs` to replace with shims, in addition to the
        Plasma set from {option}`environment.laminix.plasma`. Each must have
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
        "share/desktop-directories"
        "share/kglobalaccel"
        "share/krunner"
        "share/kio"
        "share/solid"
        "share/kconf_update"
        "share/user-tmpfiles.d"
        "share/vulkan"
        "etc/xdg/autostart"
        "etc/xdg/systemd"
        "etc/xdg/menus"
        "etc/xdg/plasma-workspace"
        "etc/xdg/mimeapps.list"
        "share/fish"
        "share/bash-completion"
        "share/zsh"
      ];
      description = ''
        Layer paths left out of the profile. A wrapper showed a dependency's
        dirs to one program, but daemons, shells, menus, the session, and the
        Vulkan loader read these straight from the profile, so folding them in
        would register the dependency's services, shortcuts, menu entries,
        login scripts, Vulkan layers, and completions for everyone. Each entry
        names one directory or file directly below a searched path, such as
        `share/dbus-1`.
      '';
    };

    pruneProfiles = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Search only {file}`/etc/profiles/per-user/$USER` and
        {file}`/run/current-system/sw`. Every entry in
        {option}`environment.profiles` is probed on every lookup, whether or
        not it exists. Packages from `nix-env`, `nix profile`, or Home
        Manager without {option}`home-manager.useUserPackages` drop out of
        every search path, `PATH` included.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      lib.singleton {
        assertion = lib.all (p: (lib.attrByPath p { } pkgs).laminix or false) present;
        message = "environment.laminix: modules get a pkgs without shims, so something else sets it, such as specialArgs.pkgs or a forced _module.args.pkgs.";
      }
      ++ map (e: {
        assertion =
          lib.elem (dirOf e) searched
          && !lib.any (s: lib.hasPrefix "${s}/" (dirOf e)) searched
          && !lib.elem e searched;
        message = "environment.laminix.exclude: ${e} is not one directory or file directly below a searched path that no other searched path contains (${toString searched}).";
      }) cfg.exclude;

    warnings = map (
      p:
      "environment.laminix.packages: pkgs.${lib.concatStringsSep "." p} doesn't exist, so nothing replaces it."
    ) (lib.filter (p: !lib.hasAttrByPath p base) userPaths);

    _module.args.pkgs = lib.mkOverride 99 shimmed;

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
