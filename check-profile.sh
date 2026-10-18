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

