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
