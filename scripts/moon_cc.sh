#!/usr/bin/env bash
set -euo pipefail

# A small compiler wrapper for Moon native builds.
#
# Moon's `moon.pkg.json` supports conditional compilation by target backend/mode but not by OS.
# Some link flags are OS-specific (e.g. `-framework ...` on Darwin). This wrapper strips flags that
# do not apply to the current OS so the same package can build across platforms.

REAL_CC="${MOON_REAL_CC:-${CC:-cc}}"
OS="$(uname -s 2>/dev/null || echo unknown)"

is_darwin=0
is_windows=0
is_linux=0

if [[ "$OS" == "Darwin" ]]; then
  is_darwin=1
elif [[ "$OS" == "Linux" ]]; then
  is_linux=1
elif [[ "$OS" == MINGW* || "$OS" == MSYS* || "$OS" == CYGWIN* ]]; then
  is_windows=1
fi

filtered=()
skip_next=0
for arg in "$@"; do
  if [[ $skip_next -eq 1 ]]; then
    skip_next=0
    continue
  fi

  # Darwin frameworks
  if [[ $is_darwin -eq 0 && "$arg" == "-framework" ]]; then
    skip_next=1
    continue
  fi
  if [[ $is_darwin -eq 0 && "$arg" == -Wl,-framework,* ]]; then
    continue
  fi

  # Windows-only libs (keep minimal; prefer runtime dynamic loading)
  if [[ $is_windows -eq 0 ]]; then
    case "$arg" in
      -lole32|-luuid|-lmmdevapi|-lavrt|-lxinput|-lxinput9_1_0|-lxinput1_4)
        continue
        ;;
    esac
  fi

  # Avoid pthread flags on Windows toolchains.
  if [[ $is_windows -eq 1 ]]; then
    case "$arg" in
      -pthread|-lpthread)
        continue
        ;;
    esac
  fi

  filtered+=("$arg")
done

if [[ ${#filtered[@]} -eq 0 ]]; then
  exec "$REAL_CC"
fi

exec "$REAL_CC" "${filtered[@]}"

