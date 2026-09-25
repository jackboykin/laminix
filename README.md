# laminix

laminix makes programs on NixOS find their files faster, without recompiling them.

Many programs on NixOS start through a wrapper that gives them a list of directories to search, one for each dependency. Every icon, plugin, and config lookup tries each directory in turn, and any program they start inherits the lists.

For each package you choose, laminix builds a shim: a copy made of links to the original, whose wrappers leave out the per-dependency directories. The files in those directories go into your profile instead, which programs already search. A lookup then checks a few directories instead of one per dependency. A shim builds in seconds.

Each moved directory lies over your profile as a thin layer or *lamina*.

KDE Plasma gains the most. Its lists add up to hundreds of thousands of failed file lookups, and opening the app launcher, a system tray popup, or a KDE app takes noticeably longer than on other distributions. KDE slowness has been an issue for quite some time ([nixpkgs#363068](https://github.com/NixOS/nixpkgs/issues/363068), [nixpkgs#126590](https://github.com/NixOS/nixpkgs/issues/126590)).

Failed file lookups in each program's first 15 seconds, in a Plasma 6.7 VM, with the program shimmed. Plasma and the apps it installs are shimmed by default; the rest need listing in `environment.laminix.packages`.

<table>
<tr>
<td valign="top">

| KDE | Stock | laminix |
| --- | ---: | ---: |
| plasmashell | 758,000 | 257,000 |
| KMail | 81,700 | 27,800 |
| Dolphin | 77,800 | 38,300 |
| System Monitor | 67,000 | 6,060 |
| KDevelop | 41,700 | 18,200 |
| Discover | 25,100 | 10,800 |
| Krita | 24,700 | 19,400 |
| Kdenlive | 21,400 | 13,800 |
| Haruna | 15,700 | 7,270 |
| Okular | 14,100 | 5,980 |
| System Settings | 13,800 | 6,250 |
| Gwenview | 13,800 | 6,660 |
| digiKam | 13,100 | 6,630 |
| Konsole | 12,800 | 6,060 |

</td>
<td valign="top">

| Other programs | Stock | laminix |
| --- | ---: | ---: |
| OBS Studio | 37,800 | 13,600 |
| Telegram | 14,400 | 10,800 |
| Nextcloud client | 9,700 | 4,960 |
| Prism Launcher | 8,300 | 7,370 |
| PCSX2 | 7,770 | 4,870 |
| VLC | 5,040 | 3,570 |
| qBittorrent | 3,530 | 2,710 |
| KeePassXC | 3,440 | 2,970 |

</td>
</tr>
</table>

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

With Plasma 6, laminix shims the packages Plasma installs that have wrappers to rebuild. `environment.laminix.plasma` picks which: `"full"`, the default, covers the desktop, its apps, and its background services; `"base"` leaves out the services; `"none"` leaves Plasma alone. The option's description in `module.nix` lists each set's packages.

To shim more programs, list their attribute paths. They're added to the Plasma set:

```nix
{
  environment.laminix.packages = [
    "kdePackages.kmail"
    "obs-studio"
  ];
}
```

laminix rebuilds wrappers made by `makeBinaryWrapper`, and leaves any other program as it is.

If you install nothing with `nix-env`, `nix profile`, or Home Manager without `home-manager.useUserPackages = true`, also set `environment.laminix.pruneProfiles = true`. It drops the profiles those tools use from every search path, `PATH` included.

## Caveats

- A shim works only when a profile installs it directly, as `environment.systemPackages` does. A module that wraps it first, such as `programs.obs-studio`, fails the build.
- Only NixOS modules see shims. Packages, including ones your configuration builds with `pkgs.callPackage`, get the originals, so nothing recompiles against a shim.
- Files a wrapper showed to one program, such as icons, Qt plugins, and QML modules, become visible to every program. Files that would register something for everyone, such as services, menu entries, and shortcuts, stay out. `environment.laminix.exclude` lists them, and you can add more.
- `override` and `overrideAttrs` on a shimmed package give the plain package without a shim. To patch a package and keep its shim, patch it in an overlay.
- The system build fails, instead of the session, if a shim would split a Plasma package or lose KWin's trust.

## Measure

`laminix-audit` runs a command under `strace` and counts its failed file lookups by directory:

```sh
nix run github:jackboykin/laminix#audit -- -t 10 dolphin
```
