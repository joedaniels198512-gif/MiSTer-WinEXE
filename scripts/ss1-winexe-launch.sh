#!/bin/sh
# Generic WinEXE profile launcher. Warm Wine runtime is the default.
#
#   ss1-winexe-launch boot
#   ss1-winexe-launch launch-wex <path.wex>
#   ss1-winexe-launch launch <profile> [-- extra wine args]
#   ss1-winexe-launch restart
#   ss1-winexe-launch stop              # foreground app only → READY
#   ss1-winexe-launch shutdown          # full cold teardown
#   ss1-winexe-launch shutdown-guard    # teardown only if core left WinEXE
#   ss1-winexe-launch idle              # compat: boot if COLD, else stop-app
#   ss1-winexe-launch status
#
# Persistent desktop: explorer /desktop=ss1,640x480 with NO app.
# Apps join that desktop via wine start (registry Desktop=ss1).
# Do not use: wine explorer /desktop=ss1,640x480 <app.exe>
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
RTSTATUS=/tmp/ss1-winexe-runtime.status
LOCKDIR=/tmp/ss1-winexe.lock.d
WATCH_PID=/tmp/ss1-winexe-watch.pid
PIN_PID=/tmp/ss1-winexe-pin.pid
DESKTOP_PID=/tmp/ss1-wine-desktop.pid
APP_PIDF=/tmp/ss1-wine-app.pid
COREWATCH_PID=/tmp/ss1-winexe-corewatch.pid
WEXLOG="$WIN/logs/wex-launch.log"
RTLOG="$WIN/logs/runtime.log"
TRACE_PID=/tmp/ss1-wex-trace.pid
EXTRA_ARGS=""
CURRENT_WEX=""
DEFAULT_PREFIX="$WIN/wineprefix-prebuilt"
SS1_DESKTOP="ss1,640x480"

normalize_runtime_env() {
  if [ -z "$HOME" ] || [ "$HOME" = "/" ]; then
    export HOME=/root
  fi
  export USER="${USER:-root}"
  export LOGNAME="${LOGNAME:-$USER}"
  export DISPLAY=:0
  case ":$PATH:" in
    *:/media/fat/Windows/bin:*) ;;
    *) export PATH="/media/fat/Windows/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}" ;;
  esac
  if [ -d /root ]; then
    cd /root 2>/dev/null || cd "$WIN" || cd /
  fi
  unset WAYLAND_DISPLAY
}

# Shell-native timestamps. Do not spawn python per line.
uptime_ms() {
  awk '{ printf "%d", $1 * 1000 }' /proc/uptime 2>/dev/null || echo 0
}

wex_t0_reset() {
  awk '{ print $1 }' /proc/uptime > /tmp/ss1-wex-t0
}

wex_tms() {
  awk 'NR==1 { t0=$1 } NR==2 { printf "%d", ($1 - t0) * 1000 }' /tmp/ss1-wex-t0 /proc/uptime 2>/dev/null || echo 0
}

wexlog() {
  mkdir -p "$(dirname "$WEXLOG")"
  echo "t=$(wex_tms)ms $*" >>"$WEXLOG"
}

rtlog() {
  mkdir -p "$(dirname "$RTLOG")"
  echo "$(uptime_ms) $*" >>"$RTLOG"
}

rt_get() {
  key=$1
  [ -f "$RTSTATUS" ] || { echo ""; return 0; }
  awk -F= -v k="$key" '$1==k { print substr($0, index($0,"=")+1); exit }' "$RTSTATUS"
}

write_runtime() {
  wr_st=$1
  wr_profile=$2
  wr_name=$3
  wr_app_pid=$4
  wr_app_comm=$5
  wr_pending=$6
  wr_desk=$(cat "$DESKTOP_PID" 2>/dev/null)
  mkdir -p "$(dirname "$RTSTATUS")" "$(dirname "$STATUS")"
  cat > "$RTSTATUS" <<EOF
state=${wr_st:-COLD}
profile=${wr_profile:-}
name=${wr_name:-}
wex=${CURRENT_WEX:-}
pending_wex=${wr_pending:-}
app_pid=${wr_app_pid:-}
app_comm=${wr_app_comm:-}
desktop_pid=${wr_desk:-}
wineserver_pid=
start_pid=${wr_desk:-}
core=$(cat /tmp/CORENAME 2>/dev/null)
updated=$(uptime_ms)
EOF
  cat > "$STATUS" <<EOF
state=${wr_st:-COLD}
profile=${wr_profile:-}
name=${wr_name:-}
wex=${CURRENT_WEX:-}
wine_pid=${wr_desk:-}
core=$(cat /tmp/CORENAME 2>/dev/null)
updated=$(uptime_ms)
EOF
}

wait_x_ready() {
  export DISPLAY=:0
  if [ -f "$WIN/bin/ss1-x11-env.sh" ]; then
    # shellcheck disable=SC1091
    . "$WIN/bin/ss1-x11-env.sh"
  fi
  i=0
  while [ "$i" -lt 40 ]; do
    if [ -S /tmp/.X11-unix/X0 ]; then
      "$WIN/x11/bin/xset" q >/dev/null 2>&1 && return 0
    fi
    sleep 0.05
    i=$((i + 1))
  done
  return 1
}

wexlog_kv() {
  wexlog "  $1=${2-}"
}

wait_comm_pid() {
  name=$1
  t=${2:-40}
  i=0
  while [ "$i" -lt "$t" ]; do
    p=$(pidof "$name" 2>/dev/null | awk '{print $1}')
    if [ -n "$p" ]; then
      echo "$p"
      return 0
    fi
    sleep 0.25
    i=$((i + 1))
  done
  return 1
}

normalize_runtime_env

CMD=${1:-status}
[ $# -gt 0 ] && shift

usage() {
  cat <<EOF
ss1-winexe-launch boot
ss1-winexe-launch launch-wex <path.wex>
ss1-winexe-launch launch <profile> [-- args...]
ss1-winexe-launch osd <index>
ss1-winexe-launch restart
ss1-winexe-launch stop
ss1-winexe-launch shutdown
ss1-winexe-launch status
EOF
}

ini_get() {
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

current_profile() {
  rt_get profile
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

stop_core_watch() {
  if [ -f "$COREWATCH_PID" ]; then
    cpid=$(cat "$COREWATCH_PID" 2>/dev/null)
    if [ -n "$cpid" ] && [ "$cpid" != "$$" ]; then
      kill "$cpid" 2>/dev/null || true
    fi
    rm -f "$COREWATCH_PID"
  fi
}

# Detached CORENAME poll so a core switch can reclaim ~238 MB without a new Main binary.
# Does not block the FPGA load path.
start_core_watch() {
  if [ -f "$COREWATCH_PID" ] && kill -0 "$(cat "$COREWATCH_PID")" 2>/dev/null; then
    return 0
  fi
  (
    while :; do
      n=$(cat /tmp/CORENAME 2>/dev/null | tr -d '\r')
      case "$n" in
        WinEXE|WinEXE_Test) ;;
        *)
          awk '{ printf "%d CORE_UNLOAD\n", $1 * 1000 }' /proc/uptime >>"$RTLOG"
          "$0" shutdown </dev/null >/dev/null 2>&1 &
          exit 0
          ;;
      esac
      sleep 2
    done
  ) </dev/null >/dev/null 2>&1 &
  echo $! > "$COREWATCH_PID"
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

presenter_running() {
  if [ -f /tmp/ss1-winexe-x11-present.pid ] && kill -0 "$(cat /tmp/ss1-winexe-x11-present.pid)" 2>/dev/null; then
    return 0
  fi
  for d in /proc/[0-9]*; do
    c=$(cat "$d/comm" 2>/dev/null) || continue
    case "$c" in
      ss1-winexe-x11-*) return 0 ;;
    esac
  done
  return 1
}

# Neutral display for READY. Do not restart a healthy presenter.
apply_neutral_display() {
  export DISPLAY=:0
  if [ -f "$WIN/bin/ss1-x11-env.sh" ]; then
    # shellcheck disable=SC1091
    . "$WIN/bin/ss1-x11-env.sh"
  fi
  "$WIN/x11/bin/xsetroot" -solid "#000080" >/dev/null 2>&1 || true
  if ! presenter_running && [ -x "$BIN/ss1-winexe-present-restart.sh" ] && [ -S /tmp/.X11-unix/X0 ]; then
    SS1_HZ=60 SS1_SKIP_UNCHANGED=1 SS1_DIRTY=0 \
      SS1_TILE_W=32 SS1_TILE_H=32 SS1_DIRTY_PCT=60 \
      "$BIN/ss1-winexe-present-restart.sh" >/dev/null 2>&1 || true
  fi
}

apply_display() {
  pf=$1
  hz=$(ini_get "$pf" display presenter_hz 60)
  skip=$(ini_get "$pf" display skip_unchanged 1)
  dirty=$(ini_get "$pf" display dirty 0)
  tw=$(ini_get "$pf" display tile_w 32)
  th=$(ini_get "$pf" display tile_h 32)
  pct=$(ini_get "$pf" display dirty_pct 60)
  root=$(ini_get "$pf" display xsetroot "#000080")
  "$WIN/x11/bin/xsetroot" -solid "$root" >/dev/null 2>&1 || true
  if presenter_running && [ "$hz" = 60 ] && [ "$skip" = 1 ] && [ "$dirty" = 0 ]; then
    return 0
  fi
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
  if [ -n "$xaff" ]; then
    for p in $(pidof Xorg 2>/dev/null); do
      taskset -p "$xaff" "$p" >/dev/null 2>&1 || true
    done
  fi
  if [ -n "$paff" ]; then
    pp=$(cat /tmp/ss1-winexe-x11-present.pid 2>/dev/null)
    [ -n "$pp" ] && taskset -p "$paff" "$pp" >/dev/null 2>&1 || true
  fi
}

stop_wine_session() {
  stop_profile_helpers
  if [ -x "$BIN/ss1-winexe-stop-wine.sh" ]; then
    "$BIN/ss1-winexe-stop-wine.sh" || true
  else
    [ -f /tmp/ss1-wine.pid ] && kill "$(cat /tmp/ss1-wine.pid)" 2>/dev/null || true
    "$BIN/wineserver" -k 2>/dev/null || true
  fi
  rm -f "$DESKTOP_PID" "$APP_PIDF" /tmp/ss1-wine.pid
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

export_wine_env() {
  prefix=${1:-$DEFAULT_PREFIX}
  export WINEPREFIX="$prefix"
  export WINEARCH="${WINEARCH:-win32}"
  export FONTCONFIG_PATH="${FONTCONFIG_PATH:-$WIN/host-libs/etc/fonts}"
  export FONTCONFIG_FILE="${FONTCONFIG_FILE:-$WIN/host-libs/etc/fonts/fonts.conf}"
  export DISPLAY=:0
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
  if [ -f "$WIN/bin/ss1-x11-env.sh" ]; then
    # shellcheck disable=SC1091
    . "$WIN/bin/ss1-x11-env.sh"
  fi
  export DISPLAY=:0
}

ensure_ss1_registry() {
  prefix=${1:-$DEFAULT_PREFIX}
  ureg="$prefix/user.reg"
  if grep -q '"Desktop"="ss1"' "$ureg" 2>/dev/null; then
    return 0
  fi
  now=$(date +%s 2>/dev/null || echo 0)
  printf '\n[Software\\\\Wine\\\\Explorer] %s\n"Desktop"="ss1"\n\n[Software\\\\Wine\\\\Explorer\\\\Desktops] %s\n"ss1"="640x480"\n' "$now" "$now" >>"$ureg"
}

ss1_explorer_pid() {
  for p in $(pidof explorer.exe 2>/dev/null); do
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    echo "$cmd" | grep -q 'desktop=ss1,640x480' || continue
    echo "$p"
    return 0
  done
  return 1
}

count_ss1_explorers() {
  n=0
  for p in $(pidof explorer.exe 2>/dev/null); do
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    echo "$cmd" | grep -q 'desktop=ss1,640x480' && n=$((n + 1))
  done
  echo "$n"
}

kill_stray_explorers() {
  for p in $(pidof explorer.exe 2>/dev/null); do
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    echo "$cmd" | grep -q 'desktop=ss1,640x480' && continue
    echo "kill stray explorer pid=$p"
    kill -TERM "$p" 2>/dev/null || true
  done
  sleep 0.3
  for p in $(pidof explorer.exe 2>/dev/null); do
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    echo "$cmd" | grep -q 'desktop=ss1,640x480' && continue
    kill -KILL "$p" 2>/dev/null || true
  done
}

runtime_healthy() {
  [ -S /tmp/.X11-unix/X0 ] || return 1
  presenter_running || return 1
  ss1_explorer_pid >/dev/null || return 1
  return 0
}

wait_ss1_desktop() {
  i=0
  while [ "$i" -lt 90 ]; do
    pid=$(ss1_explorer_pid) && echo "$pid" && return 0
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}

# Watch the foreground app only. Persistent desktop must survive app exit.
start_watch() {
  stop_watch
  stem=$1
  comm=$2
  pid=$3
  setsid /bin/sh -c "
    while :; do
      alive=0
      if [ -n \"$pid\" ] && kill -0 \"$pid\" 2>/dev/null; then
        alive=1
      elif [ -n \"$comm\" ]; then
        for d in /proc/[0-9]*; do
          c=\$(cat \"\$d/comm\" 2>/dev/null) || continue
          if [ \"\$c\" = \"$comm\" ]; then
            alive=1
            break
          fi
        done
      fi
      [ \"\$alive\" = 1 ] || break
      sleep 2
    done
    cur=\$(awk -F= '\$1==\"profile\" { print \$2; exit }' $RTSTATUS 2>/dev/null)
    st=\$(awk -F= '\$1==\"state\" { print \$2; exit }' $RTSTATUS 2>/dev/null)
    if [ \"\$cur\" = \"$stem\" ] && [ \"\$st\" = APP_RUNNING ]; then
      WIN='$WIN' '$0' app-exited '$stem'
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

app_comm_of() {
  pf=$1
  target=$(ini_get "$pf" cpu app_comm "")
  if [ -z "$target" ]; then
    unix_exe=$(ini_get "$pf" app unix_exe "")
    exe=$(ini_get "$pf" app exe "")
    base=$(basename "${unix_exe:-$exe}")
    target=$base
  fi
  echo "$target"
}

kill_comm_all() {
  name=$1
  [ -n "$name" ] || return 0
  for p in $(pidof "$name" 2>/dev/null); do
    kill -TERM "$p" 2>/dev/null || true
  done
  sleep 0.4
  for p in $(pidof "$name" 2>/dev/null); do
    kill -KILL "$p" 2>/dev/null || true
  done
}

stop_app() {
  if [ "$(rt_get state)" != APP_RUNNING ]; then
    echo "READY (no app)"
    return 0
  fi
  stem=$(rt_get profile)
  comm=$(rt_get app_comm)
  apid=$(rt_get app_pid)
  rtlog "STOP_APP profile=${stem:-} comm=${comm:-} pid=${apid:-}"
  stop_watch
  stop_pin
  stop_profile_helpers "$stem"
  if [ -n "$apid" ]; then
    kill -TERM "$apid" 2>/dev/null || true
  fi
  kill_comm_all "$comm"
  # Paint imgsvc helper can leak RAM after STOP.
  if [ "$comm" = mspaint.exe ] || [ "$stem" = paint ]; then
    for p in $(pidof svchost.exe 2>/dev/null); do
      cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
      echo "$cmd" | grep -q imgsvc || continue
      kill -TERM "$p" 2>/dev/null || true
    done
  fi
  kill_stray_explorers
  rm -f "$APP_PIDF"
  apply_neutral_display
  CURRENT_WEX=""
  write_runtime READY "" "" "" "" ""
  rtlog "APP_RUNNING -> READY"
  echo "READY explorers=$(count_ss1_explorers) mem=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)kB"
}

on_app_exited() {
  stem=$1
  cur=$(rt_get profile)
  [ "$cur" = "$stem" ] || return 0
  [ "$(rt_get state)" = APP_RUNNING ] || return 0
  rtlog "APP_EXIT profile=$stem"
  stop_app
}

boot_runtime() {
  wex_t0_reset
  if [ -f /tmp/ss1-winexe-shutting ]; then
    i=0
    while [ -f /tmp/ss1-winexe-shutting ] && [ "$i" -lt 40 ]; do
      sleep 1
      i=$((i + 1))
    done
  fi
  if runtime_healthy; then
    rtlog "boot skipped: runtime healthy"
    stnow=$(rt_get state)
    if [ "$stnow" = APP_RUNNING ]; then
      start_core_watch
      echo "READY (already, app running)"
      return 0
    fi
    write_runtime READY "$(rt_get profile)" "$(rt_get name)" "$(rt_get app_pid)" "$(rt_get app_comm)" "$(rt_get pending_wex)"
    pending=$(rt_get pending_wex)
    if [ -n "$pending" ] && [ -f "$pending" ]; then
      rtlog "WEX_PENDING launch after healthy boot $pending"
      CURRENT_WEX=$pending
      write_runtime READY "$(rt_get profile)" "$(rt_get name)" "" "" ""
      launch_wex_into_desktop "$pending"
    fi
    echo "READY (already)"
    start_core_watch
    return 0
  fi

  pending=$(rt_get pending_wex)
  write_runtime BOOTING "" "" "" "" "$pending"
  rtlog "COLD -> BOOTING"

  ensure_core || {
    pending=$(rt_get pending_wex)
    rtlog "BOOT FAIL ensure_core"
    write_runtime COLD "" "" "" "" "$pending"
    return 1
  }

  bring_up_stack || {
    pending=$(rt_get pending_wex)
    rtlog "BOOT FAIL Xorg"
    write_runtime COLD "" "" "" "" "$pending"
    return 1
  }
  if wait_x_ready; then
    rtlog "X_READY"
  else
    rtlog "X_READY probe failed (continuing)"
  fi

  apply_neutral_display
  if presenter_running; then
    rtlog "PRESENTER_READY"
  else
    rtlog "PRESENTER_READY missing"
  fi

  export_wine_env "$DEFAULT_PREFIX"
  ensure_ss1_registry "$DEFAULT_PREFIX"

  winebin="$WIN/bin/wine"
  [ -x "$winebin" ] || winebin="$BIN/wine"
  mkdir -p "$WIN/logs"
  echo "===== desktop boot $(uptime_ms) =====" >>"$WIN/logs/wine-desktop.log"
  HOME="$HOME" DISPLAY=:0 setsid /bin/sh -c "export HOME=\"$HOME\"; export DISPLAY=:0; exec $winebin explorer /desktop=$SS1_DESKTOP" \
    </dev/null >>"$WIN/logs/wine-desktop.log" 2>&1 &
  echo $! > "$DESKTOP_PID"
  echo $! > /tmp/ss1-wine.pid

  expl=$(wait_ss1_desktop)
  if [ -z "$expl" ]; then
    pending=$(rt_get pending_wex)
    rtlog "BOOT FAIL wine desktop"
    write_runtime COLD "" "" "" "" "$pending"
    return 1
  fi
  n=$(count_ss1_explorers)
  rtlog "WINE_DESKTOP_READY pid=$expl count=$n"
  if [ "$n" != 1 ]; then
    kill_stray_explorers
    n=$(count_ss1_explorers)
    rtlog "WINE_DESKTOP_READY after stray-kill count=$n"
  fi

  pending=$(rt_get pending_wex)
  write_runtime READY "" "" "" "" "$pending"
  rtlog "BOOTING -> READY"
  echo "READY desktop=$expl explorers=$n"
  start_core_watch

  pending=$(rt_get pending_wex)
  if [ -n "$pending" ] && [ -f "$pending" ]; then
    rtlog "WEX_PENDING launch now $pending"
    CURRENT_WEX=$pending
    write_runtime READY "" "" "" "" ""
    launch_wex_into_desktop "$pending"
  fi
  return 0
}

shutdown_runtime() {
  guard=$1
  if [ "$guard" = guard ]; then
    sleep 1
    if core_ok && runtime_healthy; then
      rtlog "shutdown-guard aborted: core still WinEXE"
      echo "shutdown-guard: core still WinEXE, keeping runtime"
      return 0
    fi
  fi
  touch /tmp/ss1-winexe-shutting
  CURRENT_WEX=""
  write_runtime COLD "" "" "" "" ""
  rtlog "READY -> COLD (shutdown)"
  stop_core_watch
  stop_watch
  stop_pin
  CURRENT_WEX=""
  stop_wine_session
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
  write_runtime COLD "" "" "" "" ""
  rm -f /tmp/ss1-winexe-shutting
  echo "COLD core=$(cat /tmp/CORENAME 2>/dev/null || echo '?')"
}

launch_into_ss1() {
  stem=$1
  pf=$2
  name=$(ini_get "$pf" app name "$stem")
  exe=$(ini_get "$pf" app exe "")
  unix_exe=$(ini_get "$pf" app unix_exe "")
  workdir=$(ini_get "$pf" app workdir "")
  args=$(ini_get "$pf" app args "")
  prefix=$(ini_get "$pf" runtime wine_prefix "$DEFAULT_PREFIX")
  box86=$(ini_get "$pf" runtime box86 "")
  require=$(ini_get "$pf" app require "")
  optional=$(ini_get "$pf" app optional "")

  check=$require
  [ -n "$check" ] || check=$unix_exe
  if [ -n "$check" ] && [ ! -f "$check" ]; then
    echo "missing required file: $check ($name)" >&2
    return 1
  fi
  if [ -n "$optional" ] && [ ! -f "$optional" ]; then
    echo "optional file missing: $optional (continuing)" >&2
  fi

  if [ "$(rt_get state)" = APP_RUNNING ]; then
    stop_app
  fi

  export_wine_env "$prefix"
  ini_env_apply "$pf"
  export DISPLAY=:0
  if [ -n "$box86" ]; then
    export BOX86="$box86"
  fi
  apply_display "$pf"
  apply_cpu_services "$pf"

  pre=$(ini_get "$pf" helpers pre "")
  [ -n "$pre" ] || pre=$(ini_get "$pf" config script "")
  run_helpers "$pre"

  winebin="$WIN/bin/wine"
  [ -x "$winebin" ] || winebin="$BIN/wine"
  extra="$args"
  [ -n "$EXTRA_ARGS" ] && extra="$extra $EXTRA_ARGS"
  extra=$(echo "$extra" | sed 's/^[ \t]*//;s/[ \t]*$//')

  # Join existing ss1 desktop. Never: explorer /desktop=ss1,640x480 <app>.
  start_target=$unix_exe
  start_unix=1
  if [ -z "$start_target" ]; then
    case "$exe" in
      /*) start_target=$exe; start_unix=1 ;;
      *) start_target=$exe; start_unix=0 ;;
    esac
  fi
  if [ "$start_unix" = 1 ]; then
    launch="exec $winebin start /unix \"$start_target\" $extra"
  else
    launch="exec $winebin start \"$start_target\" $extra"
  fi
  if [ -n "$workdir" ]; then
    launch="cd \"$workdir\" && $launch"
  fi

  LOGDIR="$WIN/logs"
  mkdir -p "$LOGDIR"
  WINELOG="$LOGDIR/wine-winexe-${stem}.log"
  echo "===== launch $name $(uptime_ms) =====" >>"$WINELOG"
  echo "cmd=$launch" >>"$WINELOG"
  wexlog "wine start into ss1: $launch"
  HOME="$HOME" DISPLAY=:0 setsid /bin/sh -c "export HOME=\"$HOME\"; export DISPLAY=:0; $launch" \
    </dev/null >>"$WINELOG" 2>&1 &
  echo $! > "$APP_PIDF"

  pin_app_comm "$(ini_get "$pf" cpu app_comm "")" "$(ini_get "$pf" cpu app_affinity "")"
  run_helpers "$(ini_get "$pf" helpers post "")"
  bg=$(ini_get "$pf" helpers background "")
  run_helpers "$bg"

  target=$(app_comm_of "$pf")
  tpid=$(wait_comm_pid "$target" 48)
  if [ -n "$tpid" ]; then
    echo "$tpid" > "$APP_PIDF"
    wexlog "target EXE pid=$tpid comm=$target"
  else
    tpid=$(cat "$APP_PIDF" 2>/dev/null)
    wexlog "target EXE not seen yet comm=$target"
  fi

  kill_stray_explorers
  n=$(count_ss1_explorers)
  wexlog "ss1 explorer count=$n"
  if [ "$n" != 1 ]; then
    echo "warning: expected 1 ss1 desktop, have $n" >&2
  fi

  write_runtime APP_RUNNING "$stem" "$name" "$tpid" "$target" ""
  rtlog "READY -> APP_RUNNING profile=$stem pid=$tpid"
  start_watch "$stem" "$target" "$tpid"
  echo "LAUNCHED profile=$stem name=$name wex=${CURRENT_WEX:-} app=$tpid explorers=$n log=$WINELOG"
}

launch_wex_into_desktop() {
  wex=$1
  stem=$(ini_get "$wex" winexe profile "")
  if [ -z "$stem" ]; then
    echo "invalid .WEX (need [winexe] profile=): $wex" >&2
    return 1
  fi
  pf=$(resolve_profile "$stem") || {
    echo "unknown profile '$stem'" >&2
    return 1
  }
  stem=$(basename "$pf" .ini)
  CURRENT_WEX=$wex
  launch_into_ss1 "$stem" "$pf"
}

launch_wex() {
  wex_t0_reset
  wexlog "==== launch-wex argv='$1' ===="
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
  st=$(rt_get state)
  rtlog "WEX_SELECTED profile=$stem state=$st path=$wex"

  if [ "$st" = BOOTING ]; then
    CURRENT_WEX=$wex
    write_runtime BOOTING "$(rt_get profile)" "$(rt_get name)" "" "" "$wex"
    rtlog "WEX_PENDING profile=$stem"
    echo "PENDING profile=$stem (runtime BOOTING)"
    return 0
  fi

  if [ "$st" = COLD ] || [ -z "$st" ]; then
    CURRENT_WEX=$wex
    write_runtime COLD "" "" "" "" "$wex"
    rtlog "WEX_PENDING profile=$stem (will boot)"
    boot_runtime
    return $?
  fi

  if ! runtime_healthy; then
    CURRENT_WEX=$wex
    write_runtime COLD "" "" "" "" "$wex"
    boot_runtime
    return $?
  fi

  CURRENT_WEX=$wex
  launch_wex_into_desktop "$wex"
}

launch_profile() {
  stem=$1
  pf=$(resolve_profile "$stem") || {
    echo "unknown profile '$stem'" >&2
    return 1
  }
  stem=$(basename "$pf" .ini)
  st=$(rt_get state)
  if [ "$st" = BOOTING ]; then
    echo "runtime BOOTING; use a .WEX to queue, or wait for READY" >&2
    return 1
  fi
  if [ "$st" != READY ] && [ "$st" != APP_RUNNING ]; then
    boot_runtime || return 1
  fi
  launch_into_ss1 "$stem" "$pf"
}

show_status() {
  echo "===== runtime ====="
  if [ -f "$RTSTATUS" ]; then
    cat "$RTSTATUS"
  else
    echo "state=COLD"
  fi
  echo "ss1_explorers=$(count_ss1_explorers 2>/dev/null)"
  echo "-----"
  [ -x "$BIN/ss1-winexe-stop-wine.sh" ] && "$BIN/ss1-winexe-stop-wine.sh" status || true
}

PROFILE=""
case "$CMD" in
  boot)
    boot_runtime
    exit $?
    ;;
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
    stem=$(rt_get profile)
    wex=$(rt_get wex)
    [ -n "$stem" ] || { echo "no current profile" >&2; exit 1; }
    rtlog "RESTART profile=$stem"
    stop_app
    CURRENT_WEX=$wex
    if [ -n "$wex" ] && [ -f "$wex" ]; then
      launch_wex_into_desktop "$wex"
    else
      launch_profile "$stem"
    fi
    exit $?
    ;;
  stop)
    stop_app
    exit 0
    ;;
  app-exited)
    on_app_exited "$1"
    exit 0
    ;;
  shutdown)
    shutdown_runtime
    exit 0
    ;;
  shutdown-guard)
    shutdown_runtime guard
    exit 0
    ;;
  idle)
    # Old Main: core load and OSD Stop both call idle.
    st=$(rt_get state)
    case "$st" in
      COLD|"") boot_runtime; exit $? ;;
      BOOTING) echo "BOOTING"; exit 0 ;;
      *) stop_app; exit 0 ;;
    esac
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
