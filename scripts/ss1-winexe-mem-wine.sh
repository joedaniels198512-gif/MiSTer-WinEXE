#!/bin/sh
# Targeted Wine memory snapshot. Reads only matching comms + their
# smaps_rollup / status. Do not run a full /proc crawl of every mapping.
set +e
echo "===== meminfo ====="
grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|Shmem|SReclaimable|SUnreclaim|Slab|AnonPages|Mapped|CommitLimit|Committed_AS):' /proc/meminfo

echo
echo "===== wine processes (comm / rss / pss / anon / file) ====="
printf '%-16s %6s %8s %8s %8s %8s\n' COMM PID RSS_kB PSS_kB ANON_kB FILE_kB
for d in /proc/[0-9]*; do
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  case "$comm" in
    SIMCITY.EXE|explorer.exe|wineserver|services.exe|winedevice.exe|plugplay.exe|svchost.exe|rpcss.exe|start.exe|wine-preloader|wine|winedevice|plugplay)
      ;;
    *.exe|*.EXE)
      ;;
    *)
      continue
      ;;
  esac
  pid=${d#/proc/}
  rss=$(awk '/^VmRSS:/{print $2}' "$d/status" 2>/dev/null)
  pss=; anon=; file=
  if [ -r "$d/smaps_rollup" ]; then
    eval $(awk '
      /^Pss:/{p=$2}
      /^Anonymous:/{a=$2}
      /^Rss:/{r=$2}
      END{
        if (r=="") r=0
        if (p=="") p=0
        if (a=="") a=0
        printf "pss=%s anon=%s file=%s\n", p, a, r-a
      }' "$d/smaps_rollup")
  fi
  printf '%-16s %6s %8s %8s %8s %8s\n' "$comm" "$pid" "${rss:--}" "${pss:--}" "${anon:--}" "${file:--}"
done
echo
echo "===== host keep-alive ====="
for d in /proc/[0-9]*; do
  comm=$(cat "$d/comm" 2>/dev/null) || continue
  case "$comm" in
    Xorg|ss1-winexe-x11-|ss1-winexe-keep)
      pid=${d#/proc/}
      rss=$(awk '/^VmRSS:/{print $2}' "$d/status" 2>/dev/null)
      echo "$comm pid=$pid rss_kB=${rss:--}"
      ;;
  esac
done
