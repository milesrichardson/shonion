#!/usr/bin/env bash

# cd "$(dirname "$(git rev-parse --git-dir)")"

main() {
  echo  "Looking for shonion executable..."
  SHONION="$(./scripts/get-shonion-executable.sh)"

  if test -z "$SHONION" || test ! -f "$SHONION" ; then
    echo  "Error: invalid or undefined executable '$SHONION'"
    exit 1
  fi

  echo  "Creating symlink:"
  echo  "     $(pwd)/shonion"
  echo  "  -> $(pwd)/$SHONION"

  set -x
  ln -s "$SHONION" shonion
  set +x

  echo  "Success, try it:"
  echo  "./shonion --help"
}


_log() { >&2 echo "$@" ; }
# echo () { >&2 echo  "$@" ; }

main "$@"
