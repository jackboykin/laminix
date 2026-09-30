usage() {
  echo "usage: laminix-audit [-t SECONDS] [-n TOP] COMMAND [ARGS...]" >&2
  exit 2
}

seconds=10
top=15
while getopts t:n:h opt; do
  case $opt in
    t)
      [[ $OPTARG =~ ^[0-9]+$ ]] || usage
      seconds=$OPTARG
      ;;
    n) top=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
(($#)) || usage
if ! command -v "$1" >/dev/null; then
  echo "laminix-audit: $1: command not found" >&2
  exit 1
fi

# One log per process, so no call is split across lines by another's.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
# A background job starts with SIGINT ignored, so hand it back to the command.
strace -ff -qq -e trace=%file,readlink -o "$dir/log" \
  -- env --default-signal=INT sh -c 'exec "$@" >/dev/null 2>&1' sh "$@" &
tracer=$!
# strace dies of the signal that killed its last tracee, which bash would report.
disown

# Ctrl-C ends the wait early instead of the audit.
end=$((SECONDS + seconds))
trap 'end=0' INT
while ((SECONDS < end)) && kill -0 "$tracer" 2>/dev/null; do
  sleep 0.2
done
trap - INT

# strace waits for everything it traces, including daemons the command
# starts, as KMail starts Akonadi, so interrupt them all.
traced() {
  grep -lx "TracerPid:[[:space:]]*$tracer" /proc/[0-9]*/status 2>/dev/null | cut -d/ -f3
}
for sig in INT KILL; do
  mapfile -t pids < <(traced)
  ((${#pids[@]})) || break
  kill -s "$sig" "${pids[@]}" 2>/dev/null || true
  timeout 2 tail --pid="$tracer" -f /dev/null && break
done
tail --pid="$tracer" -f /dev/null
logs=("$dir"/log.*)
if [[ ! -e ${logs[0]} ]]; then
  echo "laminix-audit: strace recorded nothing" >&2
  exit 1
fi

awk -v top="$top" '
  { calls++ }
  / = -1 ENOENT / {
    failed++
    if (!match($0, /"[^"]*"/)) next
    p = substr($0, RSTART + 1, RLENGTH - 2)
    n = split(p, a, "/")
    if (p ~ /^\/nix\/store\//) {
      sub(/^[a-z0-9]{32}-/, "", a[4])
      k = "/nix/store/" a[4]
      for (i = 5; i <= 6 && i < n; i++) k = k "/" a[i]
    } else {
      k = ""
      for (i = 2; i <= 5 && i < n; i++) k = k "/" a[i]
    }
    dirs[k]++
  }
  END {
    printf "file syscalls  %d\nfailed         %d\n\n", calls, failed
    cmd = "sort -rn | head -n " top
    for (k in dirs) printf "%8d  %s\n", dirs[k], k | cmd
  }
' "${logs[@]}"
