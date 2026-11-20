# KPackage rejects files that canonicalise outside a package's root, so a root
# buildEnv merged from several packages is a black screen at login. KSvg reads
# desktoptheme without that check.
while IFS= read -r -d "" root; do
  [[ $(realpath "$root") == "$out"/* ]] || continue
  echo "laminix: split KPackage $root, merged from:" >&2
  find "$root" -type l -exec realpath {} + | grep -o "^$NIX_STORE/[^/]*" | sort -u >&2
  exit 1
done < <(find -L "$out/share" \( -path "$out/share/icons" -o -path "$out/share/plasma/desktoptheme" \) -prune \
  -o \( -name metadata.json -o -name metadata.desktop \) -printf '%h\0' 2>/dev/null)
