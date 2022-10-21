#!/usr/bin/env bash

main() {
  echo "Looking for shonion executable..."
  SHONION="$(get_shonion_executable)"

  if test -z "$SHONION" || test ! -f "$SHONION" ; then
    echo "Error: invalid or undefined executable '$SHONION'"
    exit 1
  fi

  echo "Creating symlink:"
  echo "     $(pwd)/shonion"
  echo "  -> $(pwd)/$SHONION"

  set -x
  ln -s "$SHONION" shonion
  set +x

  echo "Success, try it:"
  echo "./shonion --help"
}

get_shonion_executable() {
  if test -n "$SHONION_EXECUTABLE" ; then
    echo -n "$SHONION_EXECUTABLE"
    return
  fi

  _error_unsupported() {
    echo "Detected platform" "$@" "(ostype $OSTYPE)" "has no precompiled executable in bin."
    echo "You can set SHONION_EXECUTABLE to the path of a binary to skip this check,"
    echo "or you can try compiling it with:"
    echo "  cargo build -vv --release --features=xplat"
    echo "If it's successful, please add the binary to the repo for others:"
    echo "  ./scripts/commit-release.sh"
    exit 1
}
  _select() {
    local selected="$1"
    shift
    >&2 echo "found executable $selected for platform" "$@" "(ostype $OSTYPE )"
    echo -n "bin/$selected"
  }

  case "$OSTYPE" in
    linux*)   _select "shonion-x86_64-unknown-linux-gnu" "Linux/WSL" ;;
    darwin*)  _error_unsupported "Mac OS" ;;
    win*)     _error_unsupported "Windows" ;;
    msys*)    _error_unsupported "MSYS / MinGW / Git Bash" ;;
    cygwin*)  _error_unsupported "Cygwin" ;;
    bsd*)     _error_unsupported "BSD" ;;
    solaris*) _error_unsupported "Solaris" ;;
    *)        _error_unsupported "unknown: $OSTYPE" ;;
  esac
}

main "$@"
