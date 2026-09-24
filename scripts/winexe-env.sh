# Shared WinEXE paths. Source from other scripts:
#   . "$(dirname "$0")/winexe-env.sh"
# Override with WINEXE_ROOT if needed. Do not hardcode /media/fat/Windows.
WINEXE_ROOT="${WINEXE_ROOT:-/media/fat/games/WinEXE}"
WIN="${WIN:-$WINEXE_ROOT}"
export WINEXE_ROOT WIN
