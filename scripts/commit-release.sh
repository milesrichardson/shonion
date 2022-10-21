cd "$(dirname "$(git rev-parse --git-dir)")"

main() {

  local variant="$1"
  shift

  if test -z "$variant" ; then
    _log "usage: $0 <static|dynamic>"
    exit 2
  fi

  current_commitish=$(git rev-parse HEAD | cut -c-8)
  git commit -m '[bin] build bin/'"$variant"' from '"$current_commitish"''
}

_log() { >&2 echo "$@" ; }

main "$@"
