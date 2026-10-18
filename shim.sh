# Rebuild binary wrappers without the per-dependency dirs the session already
# searches. The dirs become layers, which the installing profile folds in
# through propagated-user-env-packages.

# The shim keeps the original's name, so say whose failure this is.
failureHook() {
  echo "laminix: failed to shim $name, which is unchanged. To build without the shim, remove it from environment.laminix.packages." >&2
}

outs=($outputs)
srcs=($srcPaths)

declare -A flat
for p in $pairs; do
  flat[$p]=1
done

# A package's own system bus services, systemd units, polkit actions, and
# udev rules start programs outside the session, where nothing searches the
# profile, so those keep their wrappers.
declare -A outside
started=()
for s in "${srcs[@]}"; do
  for d in share/dbus-1/system-services {lib,etc}/systemd/system share/polkit-1/actions {lib,etc}/udev/rules.d; do
    if [[ -d $s/$d ]]; then
      started+=("$s/$d")
    fi
  done
done
if ((${#started[@]})); then
  while IFS= read -r p; do
    outside[$(realpath -m "$p")]=1
  done < <(grep -RhoE "$NIX_STORE/[^[:space:]\"'<>]+" "${started[@]}" || true)
fi

# Run each wrapper's embedded makeCWrapper call with FN in its place: bash's
# parser hands FN the argv, and the wrapper path as $wrapper.
forEachWrapper() {
  local fn=$1 wrapper cmd
  while IFS= read -r -d "" wrapper; do
    cmd=$("$extractCmd" "$wrapper")
    [[ -n $cmd ]] || continue
    eval "$fn ${cmd#makeCWrapper}"
  done < <(find "$src" -type f -executable -print0)
}

# A KPackage root must stay one symlink: KPackage rejects files that
# canonicalise outside it.
own() {
  local p=$dst part parts=()
  [[ $1 == */* ]] && IFS=/ read -ra parts <<<"${1%/*}"
  for part in "${parts[@]}"; do
    p+=/$part
    if [[ -L $p ]]; then
      if [[ -e $p/metadata.json || -e $p/metadata.desktop ]]; then
        echo "laminix: replacing $1 would split KPackage ${p#"$dst"/}" >&2
        exit 1
      fi
      rm "$p"
      mkdir "$p"
      find -H "$src${p#"$dst"}" -mindepth 1 -maxdepth 1 -exec ln -st "$p" {} +
    elif [[ ! -e $p ]]; then
      mkdir "$p"
    fi
  done
  rm -f "$dst/$1"
}

isFlat() {
  local var=$1 sep=$2 dir=$3
  [[ $sep == : && $dir == "$NIX_STORE"/*/* ]] || return 1
  [[ -n ${flat[$var:${dir#"$NIX_STORE"/*/}]-} ]]
}

reshim() {
  local exe=$1 kept=() rel=${wrapper#"$src"/} a inherit= other=
  [[ -z ${outside[$wrapper]-} ]] || return 0
  shift
  while (($#)); do
    if [[ $1 == --prefix || $1 == --suffix ]] && isFlat "$2" "$3" "$4"; then
      layers+=("$4")
      shift 4
    else
      kept+=("$1")
      shift
    fi
  done
  # KWin trusts a client whose /proc/pid/exe, minus .X-wrapped, is its desktop
  # entry's canonical Exec, which names the shim: the program must be a copy.
  own "$rel"
  for a in "${kept[@]}"; do
    if [[ $a == --inherit-argv0 ]]; then inherit=1; else other=1; fi
  done
  if [[ $exe != "$src"/* ]]; then
    makeBinaryWrapper "$exe" "$dst/$rel" "${kept[@]}"
  elif [[ -n $("$extractCmd" "$exe") ]]; then
    makeBinaryWrapper "$dst/${exe#"$src"/}" "$dst/$rel" "${kept[@]}"
  elif [[ -n $inherit && -z $other && ${rel##*/} != .*-wrapped* ]]; then
    # A copy named .X-wrapped_ wouldn't unwrap to its desktop entry's name.
    cp "$exe" "$dst/$rel"
  else
    own "${exe#"$src"/}"
    cp "$exe" "$dst/${exe#"$src"/}"
    makeBinaryWrapper "$dst/${exe#"$src"/}" "$dst/$rel" "${kept[@]}"
  fi
}

writeLayers() {
  local propagated=nix-support/propagated-user-env-packages prop=() dir rel layer e hide n=0
  ((${#layers[@]})) || return 0
  own "$propagated"
  if [[ -e $src/$propagated ]]; then
    prop=($(<"$src/$propagated"))
  fi
  while IFS= read -r dir; do
    [[ -d $dir ]] || continue
    rel=${dir#"$NIX_STORE"/*/}
    layer=$dst/nix-support/layers/$((n++))
    mkdir -p "$(dirname "$layer/$rel")"
    hide=" "
    for e in $exclude; do
      [[ $e == "$rel"/* ]] && hide+="${e#"$rel"/} "
    done
    if [[ $hide == " " ]]; then
      ln -s "$dir" "$layer/$rel"
    else
      mkdir "$layer/$rel"
      while IFS= read -r -d "" e; do
        [[ $hide == *" ${e##*/} "* ]] || ln -s "$e" "$layer/$rel/"
      done < <(find -H "$dir" -mindepth 1 -maxdepth 1 -print0)
    fi
    prop+=("$layer")
  done < <(printf '%s\n' "${layers[@]}" | sort -u)
  echo "${prop[*]}" >"$dst/$propagated"
}

sedExpr=
grepArgs=()
for i in "${!outs[@]}"; do
  for d in bin sbin libexec; do
    sedExpr+="s|${srcs[i]}/$d|${!outs[i]}/$d|g;"
    grepArgs+=(-e "${srcs[i]}/$d")
  done
done

for i in "${!outs[@]}"; do
  src=${srcs[i]}
  dst=${!outs[i]}
  layers=()
  mkdir "$dst"
  find "$src" -mindepth 1 -maxdepth 1 -exec ln -st "$dst" {} +
  forEachWrapper reshim

  while IFS= read -r f; do
    rel=${f#"$src"/}
    own "$rel"
    sed "$sedExpr" "$f" >"$dst/$rel"
    chmod --reference="$f" "$dst/$rel"
  done < <(grep -RlIF "${grepArgs[@]}" "$src")

  writeLayers
done

# Rebuilding the shim reads every original, so keep them all alive with it.
src=${srcs[0]}
dst=${!outs[0]}
own nix-support/laminix-originals
echo "${srcs[@]}" >"$dst/nix-support/laminix-originals"

# Whether KWin, by the rule in reshim, denies entry $1. Sets $run and $want.
denied() {
  local cmd next base
  grep -q '^X-KDE-Wayland-Interfaces=' "$1" || return 1
  cmd=$(grep -m1 '^Exec=' "$1") || return 1
  cmd=${cmd#Exec=}
  cmd=${cmd%% *}
  [[ $cmd == /* ]] && want=$(realpath -e "$cmd") || return 1
  run=$want
  while next=$("$extractCmd" "$run" | sed -n "1s/^makeCWrapper '\([^']*\)'.*/\1/p") && [[ -n $next ]]; do
    run=$(realpath -e "$next") || return 1
  done
  while [[ ${run##*/} == .*-wrapped ]]; do
    base=${run##*/}
    base=${base#.}
    run=${run%/*}/${base%-wrapped}
  done
  [[ $run != "$want" ]]
}

for i in "${!outs[@]}"; do
  for d in "${!outs[i]}"/share/applications/*.desktop; do
    rel=${d#"${!outs[i]}"/}
    [[ -e $d ]] && ! denied "${srcs[i]}/$rel" && denied "$d" || continue
    echo "laminix: kwin won't trust $rel: it runs $run but Exec is $want" >&2
    exit 1
  done
done
