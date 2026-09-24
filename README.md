# laminix

On NixOS, Qt and KDE programs start through wrappers that add one directory per dependency to their search paths. Every icon, plugin, and config lookup tries each directory in turn, and child processes inherit the lists. In Plasma that adds up to hundreds of thousands of failed file lookups ([nixpkgs#126590](https://github.com/NixOS/nixpkgs/issues/126590)).

laminix rebuilds the wrappers of the packages you choose without those directories. Each directory becomes a lamina, a thin layer laid over the profile that installs the package, which the session already searches. Nothing is rebuilt from source.

Failed file lookups on one Plasma 6.7 machine:

| Program | Stock | laminix | laminix with `pruneProfiles` |
| --- | ---: | ---: | ---: |
| plasmashell, first 15 seconds | 758,000 | 257,000 | 147,000 |
| Dolphin, first 6 seconds | 62,000 | 26,300 | 24,400 |
| Konsole, first 6 seconds | 20,900 | 5,100 | 4,500 |

## Install

Add the flake to your inputs:

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

With Plasma 6, laminix shims the session, Dolphin, Konsole, and Kate. To choose others, set `environment.laminix.packages` to attribute paths such as `"kdePackages.okular"`.

If you install nothing with `nix-env`, `nix profile`, or standalone Home Manager, also set `environment.laminix.pruneProfiles = true`. It drops the profiles those tools use from every search path, `PATH` included.

## Caveats

- A shim works only when installed in a profile, such as `environment.systemPackages`.
- Only wrappers made by `makeBinaryWrapper` are rebuilt.
- The system build fails, instead of the session, if a shim would split a Plasma package or lose KWin's trust.

## Measure

`laminix-audit` runs a command under `strace` and counts its failed file lookups by directory:
