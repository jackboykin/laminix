# KPackage rejects files that canonicalise outside the root, so a split root
# is a black screen at login. KSvg reads desktoptheme without that check.
while IFS= read -r -d "" root; do
  canon=$(realpath "$root")
  while IFS= read -r -d "" f; do
    [[ $f == "$canon"/* ]] || {
      echo "laminix: split KPackage $root: $f" >&2
      exit 1
    }
  done < <(find -L "$root" -type f -exec realpath -z -- {} +)
done < <(find -L "$out/share" \( -path "$out/share/icons" -o -path "$out/share/plasma/desktoptheme" \) -prune \
  -o \( -name metadata.json -o -name metadata.desktop \) -printf '%h\0' 2>/dev/null)

# KWin's trust rule for restricted Wayland protocols; see shim.sh.
for d in "$out"/share/applications/*.desktop; do
  [[ -e $d ]] && grep -q '^X-KDE-Wayland-Interfaces=' "$d" || continue
  cmd=$(grep -m1 '^Exec=' "$d" || true)
  cmd=${cmd#Exec=}
  cmd=${cmd%% *}
  [[ $cmd == /* ]] || continue
  want=$(realpath -e "$cmd") || continue
  run=$want
  while next=$("$extractCmd" "$run" | sed -n "1s/^makeCWrapper '\([^']*\)'.*/\1/p") && [[ -n $next ]]; do
    run=$(realpath -e "$next") || continue 2
  done
  while [[ ${run##*/} == .*-wrapped ]]; do
    base=${run##*/}
    base=${base#.}
    run=${run%/*}/${base%-wrapped}
  done
  [[ $run == "$want" ]] || {
    echo "laminix: kwin won't trust $d: it runs $run but Exec is $want" >&2
    exit 1
  }
done
