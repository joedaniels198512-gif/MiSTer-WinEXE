#!/bin/sh
# Generic WinEXE profile launcher. One command for every OSD app.
# Does not hard-code SC2K / Winamp behaviour; that lives in profiles/*.ini.
#
#   ss1-winexe-launch launch <profile> [-- extra wine args]
#   ss1-winexe-launch launch-wex <path.wex>
#   ss1-winexe-launch osd <0-3>          # legacy numeric OSD
#   ss1-winexe-launch restart
#   ss1-winexe-launch stop|idle
#   ss1-winexe-launch status
#
# OSD path: core already loaded. SSH path may load WinEXE_Test.rbf if needed.
set +e
WIN="${WIN:-/media/fat/Windows}"
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
BIN="$WIN/bin"
[ -x "$BIN/ss1-winexe-xorg.sh" ] || BIN="$HERE"
PROFILES="${SS1_PROFILES:-$WIN/profiles}"
if [ ! -d "$PROFILES" ]; then
  ROOT=$(CDPATH= cd "$HERE/.." && pwd)
  [ -d "$ROOT/profiles" ] && PROFILES="$ROOT/profiles"
fi
HELPERS="$WIN/helpers"
[ -d "$HELPERS" ] || HELPERS="$HERE"
STATUS=/tmp/ss1-winexe.status
LOCK=/tmp/ss1-winexe.lock
WATCH_PID=/tmp/ss1-winexe-watch.pid
PIN_PID=/tmp/ss1-winexe-pin.pid
EXTRA_ARGS=""
CURRENT_WEX=""

CMD=${1:-status}
[ $# -gt 0 ] && shift

usage() {
  cat <<EOF
ss1-winexe-launch launch <profile> [-- args...]
ss1-winexe-launch launch-wex <path.wex>
ss1-winexe-launch osd <index>
ss1-winexe-launch restart
ss1-winexe-launch stop
ss1-winexe-launch idle
ss1-winexe-launch status
EOF
}

ini_get() {
  # ini_get file section key [default]
  awk -F= -v s="$2" -v k="$3" -v d="${4-}" '
    BEGIN { sec=""; found=0 }
    /^[ \t]*[#;]/ { next }
    /^[ \t]*$/ { next }
    /^[ \t]*\[/ {
      gsub(/^[ \t]*\[/, ""); gsub(/\][ \t]*$/, ""); sec=$0
      next
    }
    {
      if (sec != s) next
      key=$1
      sub(/^[ \t]+/, "", key); sub(/[ \t]+$/, "", key)
      if (tolower(key) != tolower(k)) next
      val=substr($0, index($0, "=")+1)
      sub(/^[ \t]+/, "", val); sub(/[ \t\r]+$/, "", val)
      print val
      found=1
      exit
    }
    END { if (!found) print d }
  ' "$1"
}

ini_env_apply() {
  # Export [env] into the current shell. python3 is already used by config helpers.
  eval "$(python3 - "$1" << 'PY'
import shlex, sys
section = ""
for raw in open(sys.argv[1], "r", errors="replace"):
    line = raw.strip()
    if not line or line.startswith("#") or line.startswith(";"):
        continue
    if line.startswith("[") and line.endswith("]"):
        section = line[1:-1].strip()
        continue
    if section != "env" or "=" not in line:
        continue
    key, val = line.split("=", 1)
    key = key.strip()
    val = val.strip()
    if key:
        print("export %s=%s" % (key, shlex.quote(val)))
PY
)"
}

resolve_profile() {
  name=$1
  name=${name%.ini}
  for cand in \
    "$PROFILES/$name.ini" \
    "$PROFILES/experimental/$name.ini" \
    "$WIN/profiles/$name.ini"
  do
    if [ -f "$cand" ]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

profile_for_osd() {
  idx=$1
  found=""
  for f in "$PROFILES"/*.ini "$PROFILES"/experimental/*.ini; do
    [ -f "$f" ] || continue
    menu=$(ini_get "$f" osd menu 1)
    [ "$menu" = 1 ] || continue
    pidx=$(ini_get "$f" osd index "")
    if [ "$pidx" = "$idx" ]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

write_status() {
  mkdir -p "$(dirname "$STATUS")"
  cat > "$STATUS" <<EOF
state=${1:-unknown}
profile=${2:-}
name=${3:-}
wex=${CURRENT_WEX:-}
wine_pid=$(cat /tmp/ss1-wine.pid 2>/dev/null)
core=$(cat /tmp/CORENAME 2>/dev/null)
updated=$(date -Iseconds 2>/dev/null || date)
EOF
}

current_profile() {
  awk -F= '/^profile=/{print $2; exit}' "$STATUS" 2>/dev/null
}

resolve_helper() {
  cmd=$1
  first=${cmd%% *}
  rest=${cmd#"$first"}
  case "$first" in
    /*)
      echo "$cmd"
      return
      ;;
  esac
  for dir in "$BIN" "$HELPERS" "$WIN/bin"; do
    if [ -x "$dir/$first" ] || [ -f "$dir/$first" ]; then
      echo "$dir/$first$rest"
      return
    fi
  done
  echo "$cmd"
}

run_helpers() {
  # run_helpers "<semi-colon separated>"
  list=$1
  [ -n "$list" ] || return 0
  oldifs=$IFS
  IFS=';'
  set -f
  for item in $list; do
    set +f
    IFS=$oldifs
    item=$(echo "$item" | sed 's/^[ \t]*//;s/[ \t]*$//')
    [ -n "$item" ] || continue
    resolved=$(resolve_helper "$item")
    echo "helper: $resolved"
    # shellcheck disable=SC2086
    sh -c "$resolved" || echo "helper failed: $resolved" >&2
    IFS=';'
    set -f
  done
  set +f
  IFS=$oldifs
}

core_ok() {
  case "$(cat /tmp/CORENAME 2>/dev/null)" in
    WinEXE|WinEXE_Test) return 0 ;;
  esac
  return 1
}

ensure_core() {
  core_ok && return 0
  if [ -f /media/fat/WinEXE.rbf ]; then
    rbf=/media/fat/WinEXE.rbf
  elif [ -f /media/fat/_Computer/WinEXE.rbf ]; then
    rbf=/media/fat/_Computer/WinEXE.rbf
  elif [ -f /media/fat/_Console/WinEXE.rbf ]; then
    rbf=/media/fat/_Console/WinEXE.rbf
  elif [ -f /media/fat/WinEXE_Test.rbf ]; then
    rbf=/media/fat/WinEXE_Test.rbf
  else
    echo "no WinEXE RBF found; load the core from the MiSTer menu" >&2
    return 1
  fi
  echo "loading $rbf (was '$(cat /tmp/CORENAME 2>/dev/null)')"
  echo "load_core $rbf" > /dev/MiSTer_cmd
  i=0
  while [ "$i" -lt 20 ]; do
    sleep 1
    core_ok && return 0
    i=$((i + 1))
  done
  echo "core did not become WinEXE*" >&2
  return 1
}

stop_watch() {
  if [ -f "$WATCH_PID" ]; then
    kill "$(cat "$WATCH_PID")" 2>/dev/null || true
    rm -f "$WATCH_PID"
  fi
}

stop_profile_helpers() {
  prev=$(current_profile)
  [ -n "$prev" ] || prev=$1
  pf=$(resolve_profile "$prev" 2>/dev/null)
  if [ -n "$pf" ] && [ -f "$pf" ]; then
    run_helpers "$(ini_get "$pf" helpers cleanup "")"
  fi
  [ -x "$BIN/ss1-winexe-sc2k-toolbar.sh" ] && \
    "$BIN/ss1-winexe-sc2k-toolbar.sh" stop >/dev/null 2>&1 || true
}

restore_defaults() {
  if [ -x "$BIN/ss1-winexe-present-restart.sh" ] && [ -S /tmp/.X11-unix/X0 ]; then
    SS1_HZ=60 SS1_SKIP_UNCHANGED=1 SS1_DIRTY=0 \
      SS1_TILE_W=32 SS1_TILE_H=32 SS1_DIRTY_PCT=60 \
      "$BIN/ss1-winexe-present-restart.sh" >/dev/null 2>&1 || true
  fi
  for d in /proc/[0-9]*; do
    c=$(cat "$d/comm" 2>/dev/null) || continue
    case "$c" in
      Xorg|ss1-winexe-x11-*) taskset -p 0x3 "${d#/proc/}" >/dev/null 2>&1 || true ;;
    esac
  done
}

stop_wine_session() {
  stop_profile_helpers
  if [ -x "$BIN/ss1-winexe-stop-wine.sh" ]; then
    "$BIN/ss1-winexe-stop-wine.sh" || true
  else
    [ -f /tmp/ss1-wine.pid ] && kill "$(cat /tmp/ss1-wine.pid)" 2>/dev/null || true
    "$BIN/wineserver" -k 2>/dev/null || true
  fi
}

idle_runtime() {
  stop_watch
  stop_pin
  stop_wine_session
  restore_defaults
  CURRENT_WEX=""
  [ -x "$BIN/ss1-winexe-keep-input.sh" ] && \
    "$BIN/ss1-winexe-keep-input.sh" stop >/dev/null 2>&1 || true
  if [ -f /tmp/ss1-winexe-x11-present.pid ]; then
    kill "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null || true
    rm -f /tmp/ss1-winexe-x11-present.pid
  fi
  for d in /proc/[0-9]*; do
    c=$(cat "$d/comm" 2>/dev/null) || continue
    case "$c" in
      ss1-winexe-x11-*) kill "${d#/proc/}" 2>/dev/null || true ;;
    esac
  done
  [ -x "$BIN/ss1-winexe-xorg.sh" ] && "$BIN/ss1-winexe-xorg.sh" stop >/dev/null 2>&1 || true
  [ -x "$BIN/ss1-winexe-blank.sh" ] && "$BIN/ss1-winexe-blank.sh" || true
  write_status idle "" ""
  echo "idle core=$(cat /tmp/CORENAME 2>/dev/null || echo '?')"
}

bring_up_stack() {
  [ -x "$BIN/ss1-mount-prefix.sh" ] && "$BIN/ss1-mount-prefix.sh" || true
  mkdir -p "$WIN/x11/etc/X11" "$WIN/logs"
  if [ -f "$BIN/xorg.winexe.conf" ]; then
    cp "$BIN/xorg.winexe.conf" "$WIN/x11/etc/X11/xorg.winexe.conf"
  fi
  [ -x "$BIN/ss1-winexe-xorg.sh" ] || { echo "missing ss1-winexe-xorg.sh" >&2; return 1; }
  "$BIN/ss1-winexe-xorg.sh" start || return 1
  [ -x "$BIN/ss1-winexe-ungrab-input.sh" ] && "$BIN/ss1-winexe-ungrab-input.sh" || true
  [ -x "$BIN/ss1-winexe-keep-input.sh" ] && "$BIN/ss1-winexe-keep-input.sh" watch || true
  export DISPLAY="${DISPLAY:-:0}"
  if [ -f "$WIN/bin/ss1-x11-env.sh" ]; then
    # shellcheck disable=SC1091
    . "$WIN/bin/ss1-x11-env.sh"
  elif [ -f "$BIN/ss1-x11-env.sh" ]; then
    # shellcheck disable=SC1091
    . "$BIN/ss1-x11-env.sh"
  fi
  "$WIN/x11/bin/xset" s off -dpms >/dev/null 2>&1 || true
}

apply_display() {
  pf=$1
  hz=$(ini_get "$pf" display presenter_hz 60)
  skip=$(ini_get "$pf" display skip_unchanged 1)
  dirty=$(ini_get "$pf" display dirty 0)
  tw=$(ini_get "$pf" display tile_w 32)
  th=$(ini_get "$pf" display tile_h 32)
  pct=$(ini_get "$pf" display dirty_pct 60)
  root=$(ini_get "$pf" display xsetroot "#000000")
  "$WIN/x11/bin/xsetroot" -solid "$root" >/dev/null 2>&1 || true
  if [ -x "$BIN/ss1-winexe-present-restart.sh" ]; then
    SS1_HZ="$hz" SS1_SKIP_UNCHANGED="$skip" SS1_DIRTY="$dirty" \
      SS1_TILE_W="$tw" SS1_TILE_H="$th" SS1_DIRTY_PCT="$pct" \
      "$BIN/ss1-winexe-present-restart.sh" || return 1
  fi
}

apply_cpu_services() {
  pf=$1
  xaff=$(ini_get "$pf" cpu xorg_affinity "")
  paff=$(ini_get "$pf" cpu presenter_affinity "")
  for d in /proc/[0-9]*; do
    c=$(cat "$d/comm" 2>/dev/null) || continue
    case "$c" in
      Xorg)
        [ -n "$xaff" ] && taskset -p "$xaff" "${d#/proc/}" >/dev/null 2>&1 || true
        ;;
      ss1-winexe-x11-*)
        [ -n "$paff" ] && taskset -p "$paff" "${d#/proc/}" >/dev/null 2>&1 || true
        ;;
    esac
  done
}

stop_pin() {
  if [ -f "$PIN_PID" ]; then
    kill "$(cat "$PIN_PID")" 2>/dev/null || true
    rm -f "$PIN_PID"
  fi
}

pin_app_comm() {
  comm=$1
  mask=$2
  stop_pin
  [ -n "$comm" ] && [ -n "$mask" ] || return 0
  # Wine can spawn the exe more than once (explorer desktop). Keep
  # re-applying for the wait window instead of exiting on the first pid.
  (
    i=0
    while [ "$i" -lt 90 ]; do
      for d in /proc/[0-9]*; do
        c=$(cat "$d/comm" 2>/dev/null) || continue
        if [ "$c" = "$comm" ]; then
          taskset -p "$mask" "${d#/proc/}" >/dev/null 2>&1 || true
        fi
      done
      sleep 1
      i=$((i + 1))
    done
  ) >/dev/null 2>&1 &
  echo $! > "$PIN_PID"
}

start_watch() {
  stop_watch
  stem=$1
  setsid /bin/sh -c "
    while [ -f /tmp/ss1-wine.pid ] && kill -0 \"\$(cat /tmp/ss1-wine.pid)\" 2>/dev/null; do
      sleep 2
    done
    cur=\$(awk -F= '/^profile=/{print \$2; exit}' $STATUS 2>/dev/null)
    if [ \"\$cur\" = \"$stem\" ]; then
      WIN='$WIN' '$0' idle
    fi
  " </dev/null >/dev/null 2>&1 &
  echo $! > "$WATCH_PID"
}

wex_abs_path() {
  p=$1
  [ -n "$p" ] || return 1
  case "$p" in
    /*) ;;
    *) p="/media/fat/$p" ;;
  esac
  echo "$p"
}

launch_wex() {
  wex=$(wex_abs_path "$1") || {
    echo "launch-wex path required" >&2
    return 1
  }
  [ -f "$wex" ] || {
    echo "missing .WEX: $wex" >&2
    return 1
  }
  stem=$(ini_get "$wex" winexe profile "")
  if [ -z "$stem" ]; then
    echo "invalid .WEX (need [winexe] profile=): $wex" >&2
    return 1
  fi
  CURRENT_WEX=$wex
  launch_profile "$stem"
}

launch_profile() {
  stem=$1
  pf=$(resolve_profile "$stem") || {
    echo "unknown profile '$stem'" >&2
    return 1
  }
  stem=$(basename "$pf" .ini)

  name=$(ini_get "$pf" app name "$stem")
  exe=$(ini_get "$pf" app exe "")
  unix_exe=$(ini_get "$pf" app unix_exe "")
  workdir=$(ini_get "$pf" app workdir "")
  args=$(ini_get "$pf" app args "")
  explorer=$(ini_get "$pf" app explorer 1)
  desktop=$(ini_get "$pf" app desktop "ss1,640x480")
  require=$(ini_get "$pf" app require "")
  optional=$(ini_get "$pf" app optional "")
  prefix=$(ini_get "$pf" runtime wine_prefix "$WIN/wineprefix-prebuilt")
  box86=$(ini_get "$pf" runtime box86 "")

  check=$require
  [ -n "$check" ] || check=$unix_exe
  if [ -n "$check" ] && [ ! -f "$check" ]; then
    echo "missing required file: $check ($name)" >&2
    return 1
  fi
  if [ -n "$optional" ] && [ ! -f "$optional" ]; then
    echo "optional file missing: $optional (continuing)" >&2
  fi

  write_status launching "$stem" "$name"
  stop_watch
  stop_wine_session
  restore_defaults

  ensure_core || return 1
  bring_up_stack || return 1
  apply_display "$pf" || return 1
  apply_cpu_services "$pf"

  export WINEPREFIX="$prefix"
  export WINEARCH="${WINEARCH:-win32}"
  export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
  export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
  export DISPLAY="${DISPLAY:-:0}"
  ini_env_apply "$pf"
  if [ -f "$WIN/bin/ss1-x11-env.sh" ]; then
    # shellcheck disable=SC1091
    . "$WIN/bin/ss1-x11-env.sh"
  fi

  if [ -n "$box86" ]; then
    export BOX86="$box86"
    # wine wrapper on this tree honors BOX86 when set; otherwise original box86.
  fi

  pre=$(ini_get "$pf" helpers pre "")
  [ -n "$pre" ] || pre=$(ini_get "$pf" config script "")
  run_helpers "$pre"

  LOGDIR="$WIN/logs"
  mkdir -p "$LOGDIR"
  WINELOG="$LOGDIR/wine-winexe-${stem}.log"
  : > "$WINELOG"

  winebin="$WIN/bin/wine"
  [ -x "$winebin" ] || winebin="$BIN/wine"

  winecmd="$winebin"
  if [ "$explorer" = 1 ]; then
    winecmd="$winebin explorer /desktop=$desktop"
  fi

  extra="$args"
  [ -n "$EXTRA_ARGS" ] && extra="$extra $EXTRA_ARGS"
  extra=$(echo "$extra" | sed 's/^[ \t]*//;s/[ \t]*$//')

  if [ -n "$workdir" ]; then
    launch="cd \"$workdir\" && exec $winecmd \"$exe\" $extra"
  else
    launch="exec $winecmd \"$exe\" $extra"
  fi

  echo "===== launch $name $(date) =====" >>"$WINELOG"
  setsid /bin/sh -c "$launch" </dev/null >>"$WINELOG" 2>&1 &
  echo $! > /tmp/ss1-wine.pid

  pin_app_comm "$(ini_get "$pf" cpu app_comm "")" "$(ini_get "$pf" cpu app_affinity "")"
  run_helpers "$(ini_get "$pf" helpers post "")"
  run_helpers "$(ini_get "$pf" helpers background "")"

  write_status running "$stem" "$name"
  start_watch "$stem"
  echo "LAUNCHED profile=$stem name=$name wex=${CURRENT_WEX:-} wine=$(cat /tmp/ss1-wine.pid) log=$WINELOG"
}

show_status() {
  if [ -f "$STATUS" ]; then
    cat "$STATUS"
  else
    echo "state=unknown"
  fi
  echo "-----"
  [ -x "$BIN/ss1-winexe-stop-wine.sh" ] && "$BIN/ss1-winexe-stop-wine.sh" status || true
}

# Strip -- and keep extra wine args for launch.
PROFILE=""
case "$CMD" in
  launch)
    PROFILE=$1
    [ -n "$PROFILE" ] || { usage >&2; exit 1; }
    shift
    if [ "$1" = "--" ]; then shift; fi
    EXTRA_ARGS="$*"
    launch_profile "$PROFILE"
    exit $?
    ;;
  launch-wex)
    [ -n "$1" ] || { echo "launch-wex path required" >&2; exit 1; }
    launch_wex "$1"
    exit $?
    ;;
  osd)
    idx=$1
    [ -n "$idx" ] || { echo "osd index required" >&2; exit 1; }
    pf=$(profile_for_osd "$idx") || { echo "no OSD profile for index $idx" >&2; exit 1; }
    launch_profile "$(basename "$pf" .ini)"
    exit $?
    ;;
  restart)
    stem=$(current_profile)
    [ -n "$stem" ] || { echo "no current profile" >&2; exit 1; }
    CURRENT_WEX=$(awk -F= '/^wex=/{print $2; exit}' "$STATUS" 2>/dev/null)
    launch_profile "$stem"
    exit $?
    ;;
  stop|idle)
    idle_runtime
    exit 0
    ;;
  status)
    show_status
    exit 0
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    # Bare profile name: ss1-winexe-launch notepad
    if pf=$(resolve_profile "$CMD"); then
      if [ "$1" = "--" ]; then shift; fi
      EXTRA_ARGS="$*"
      launch_profile "$(basename "$pf" .ini)"
      exit $?
    fi
    usage >&2
    exit 1
    ;;
esac
