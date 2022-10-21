#!/usr/bin/env bash

main() {

  local variant="${1-"static"}"
  local compiled_executable="$(get_compiled_executable "$variant")"

  _log "Looking for shonion executable..."
  SHONION="$(get_shonion_executable "$variant")"

  if test -z "$SHONION" || test ! -f "$SHONION" ; then
    _log "Error: invalid or undefined executable '$SHONION'"
    if ! test -f "$compiled_executable" ; then
      _log "No build found at $compiled_executable"
      _log -n "Need to build it? Run: "
      if test "$variant" == "dynamic" ; then
        _log "    BUILD_DYNAMIC=1 BUILD_STATIC=${BUILD_STATIC-1} ./scripts/build.sh"
      else
        _log "./scripts/build.sh"
      fi
    else
      _log "Binary found at $compiled_executable"
      _log "Need to move it to bin? Run: ./link.sh"
    fi
    _pass_via_stdout "$SHONION"
    exit 1
  fi

  _pass_via_stdout "$SHONION"
}

get_arch() {
  _error_unsupported() {
    _log "Detected platform" "$@" "(ostype $OSTYPE)" "has no precompiled executable in bin."
    _log "You can set SHONION_EXECUTABLE to the path of a binary to skip this check,"
    _log "or you can try compiling it with:"
    _log "  cargo build -vv --release --features=xplat"
    _log "If it's successful, please add the binary to the repo for others:"
    _log "  ./scripts/commit-release.sh"
    exit 1
  }

  _select() {
    local matched_arch="$1"
    shift
    local assumed_platform="$1"
    shift
    _log "matched architecture '$matched_arch' and platform '$assumed_platform' from ostype '$OSTYPE'"
    echo -n "$matched_arch"
  }

  case "$OSTYPE" in
    linux*)   _select "x86_64-unknown-linux-gnu" "Linux/WSL" ;;
    darwin*)  _select "x86_64-apple-darwin" "Mac OS" ;;
    win*)     _error_unsupported "Windows" ;;
    msys*)    _error_unsupported "MSYS / MinGW / Git Bash" ;;
    cygwin*)  _error_unsupported "Cygwin" ;;
    bsd*)     _error_unsupported "BSD" ;;
    solaris*) _error_unsupported "Solaris" ;;
    *)        _error_unsupported "unknown: $OSTYPE" ;;
  esac
}

get_target_dir() {
  local variant="$1" ; shift ;
  _pass_via_stdout "target/$variant/$(./scripts/get-host-triple.sh)"
}

get_compiled_executable() {
  local variant="$1" ; shift ;
  _pass_via_stdout "$(get_target_dir "$variant")"/release/shonion
}

get_shonion_executable() {
  if test -n "$SHONION_EXECUTABLE" ; then
    _pass_via_stdout "$SHONION_EXECUTABLE"
    return
  fi

  local variant
  if test -n "$1" ; then variant="$1" ; shift ; else variant="static" ; fi

  local matched_arch="$(get_arch)"

  if test -z "$matched_arch" ; then
    _log "warning: failed to match arch"
    _pass_via_stdout "unknown"
    return
  fi

  local executable_path="bin/$variant/$matched_arch/shonion"

  _pass_via_stdout "bin/$variant/$matched_arch/shonion"
}

_log() { >&2 echo "$@" ; }
_pass_via_stdout() { echo -n "$@" ; }

main "$@"

