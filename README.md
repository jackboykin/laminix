# laminix

laminix makes programs on NixOS find their files faster, without recompiling them.

Many programs on NixOS start through a wrapper that gives them a list of directories to search, one for each dependency. Every icon, plugin, and config lookup tries each directory in turn, and any program they start inherits the lists.

For each package you choose, laminix builds a shim: a copy made of links to the original, whose wrappers leave out the per-dependency directories. The files in those directories go into your profile instead, which programs already search. A lookup then checks a few directories instead of one per dependency. A shim builds in seconds.

Each moved directory lies over your profile as a thin layer or *lamina*.

KDE Plasma gains the most. Its lists add up to hundreds of thousands of failed file lookups, and opening the app launcher, a system tray popup, or a KDE app takes noticeably longer than on other distributions. KDE slowness has been an issue for quite some time ([nixpkgs#126590](https://github.com/NixOS/nixpkgs/issues/126590)).

The tables count failed file lookups in each program's first 15 seconds in a Plasma 6.7 VM.

With Plasma, turning laminix on shims the desktop and the apps and services Plasma installs. Here are a few of them:

| Program | Stock | laminix |
| --- | ---: | ---: |
| plasmashell | 758,000 | 257,000 |
| KMail | 81,700 | 27,800 |
| Dolphin | 77,800 | 38,300 |
| System Monitor | 67,000 | 6,060 |
| Discover | 25,100 | 10,800 |
| Okular | 14,100 | 5,980 |
| System Settings | 13,800 | 6,250 |
| Gwenview | 13,800 | 6,660 |
| Konsole | 12,800 | 6,060 |

Any other program keeps its stock wrapper until you list it in `environment.laminix.packages`:

| Program | Stock | laminix |
| --- | ---: | ---: |
| OBS Studio | 37,800 | 13,600 |
| Krita | 24,700 | 19,400 |
| Kdenlive | 21,400 | 13,800 |
| Haruna | 15,700 | 7,270 |
| Telegram | 14,400 | 10,800 |
| digiKam | 13,100 | 6,630 |
| Prism Launcher | 8,300 | 7,370 |
| VLC | 5,040 | 3,570 |
| qBittorrent | 3,530 | 2,710 |

Qt programs gain the most. GTK programs typically gain little.

## Install

laminix supports NixOS 26.05 and unstable. Add the flake to your inputs:

```nix
{
  inputs.laminix = {
    url = "github:jackboykin/laminix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then import its module and turn it on:

```nix
{
  imports = [ inputs.laminix.nixosModules.default ];
  environment.laminix.enable = true;
}
```

Without flakes, import `module.nix` from a copy of the repository, such as one from `npins` or `fetchTarball`:

```nix
{
  imports = [
    "${builtins.fetchTarball "https://github.com/jackboykin/laminix/archive/master.tar.gz"}/module.nix"
  ];
  environment.laminix.enable = true;
}
```

`environment.laminix.plasma` picks which of Plasma's packages get shims. `"full"`, the default, is every package the Plasma and KDE PIM modules can install that has a wrapper to rebuild. `"base"` keeps only the desktop and its apps, and `"none"` leaves Plasma alone. [`module.nix`](module.nix#L43-L127) lists the packages of each.

List other programs by attribute path. They're shimmed along with Plasma's:

```nix
{
  environment.laminix.packages = [
    "kdePackages.kdeconnect-kde"
    "obs-studio"
  ];
}
```

laminix rebuilds wrappers made by `makeBinaryWrapper`, and leaves any other program as it is. With nothing to shim, as on a server, it changes nothing, so a configuration shared by every host can turn it on.

If you install nothing with `nix-env`, `nix profile`, or Home Manager without `home-manager.useUserPackages = true`, also set `environment.laminix.pruneProfiles = true`. It drops the profiles those tools use from every search path, `PATH` included.

## Caveats

- A shim works only when a profile installs it directly, as `environment.systemPackages` does. A module that wraps it first, such as `programs.obs-studio`, fails the build.
- `override` and `overrideAttrs` on a shimmed package give the plain package without a shim. To patch a package and keep its shim, patch it in an overlay.
- Only NixOS modules see shims. Packages, including ones your configuration builds with `pkgs.callPackage`, get the originals, so nothing recompiles against a shim.
- A path compiled into a program skips the shim. `pam_kwallet` starts `ksecretd` this way and Info Center starts System Settings, so both run with their stock wrappers.
- Files a wrapper showed to one program, such as icons, Qt plugins, and QML modules, become visible to every program. Files that would register something for everyone, such as services, menu entries, and shortcuts, stay out. `environment.laminix.exclude` lists them, and you can add more.
- Programs a package's own system bus services, systemd units, polkit actions, or udev rules start keep their wrappers, since they run outside the session, where nothing searches the profile. A NixOS module that starts a shimmed program outside the session some other way gets the shim.
- The system build fails, instead of the session, if a shim would split a Plasma package or lose KWin's trust.
- laminix builds `pkgs` from the `environment.laminix` options, so their definitions can't read `pkgs`. Neither can the attribute names under `environment`: `environment = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux { … }` recurses forever, and `lib.mkIf` in its place evaluates.

## Measure

`laminix-audit` runs a command under `strace` and counts its failed file lookups by directory:

```sh
nix run github:jackboykin/laminix#audit -- -t 10 dolphin
```
