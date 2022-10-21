cd "$(dirname "$(git rev-parse --git-dir)")"

main() {
  local commit_flag="$1"
  shift

  if stage_release "static" ; then
    if notify_commit_flag "$commit_flag" ; then
      _log "commit static executable" ;
      ./scripts/commit-release.sh static
    else
      set -x ; git restore --staged bin/static ; set +x
    fi
  else
    _log "no static executable to stage" ;
  fi

  if stage_release "dynamic" ; then
    if notify_commit_flag "$commit_flag" ; then
      _log "commit dynamic executable" ;
      ./scripts/commit-release.sh dynamic
    else
      set -x ; git restore --staged bin/dynamic ; set +x
    fi
  else
    _log "no dynamic executable to stage" ;
  fi
}

notify_commit_flag() {
  local commit_flag="$1"
  shift
  if test "$commit_flag" != "--commit" ; then
    _log ""
    _log "Restoring staged files..."
    _log "To commit, run:"
    _log "    $0 --commit"
    _log ""
    return 1
  fi
  return 0
}

stage_release() {
  local variant="$1"
  if test -z "$variant" ; then _log "usage: stage_release <static|dynamic>" ; exit 1 ; fi

  local host_triple="$(./scripts/get-host-triple.sh)"

  local dest_executable="$(./scripts/get-shonion-executable.sh "$variant")"
  local dest_dir="$(dirname "$dest_executable")"

  local src_executable="$(get_target_executable "$variant")"

  if ! test -f "$src_executable" ; then
    _log "error: missing executable at $src_executable"
    return 1
  fi

  if test -z "$dest_executable" ; then
      _log "error: invalid executable" ; exit 1 ;
  fi

  if test ! -d "$dest_dir" ; then
    _log "warn: executable dir does not exist at '$dest_dir' for '$dest_executable'"
    set -x ; mkdir -p "$dest_dir" ; set +x ;
  fi

  _log "---"
  _log "[ $variant ] [COPY release -> bin]"
  set -x
  cp "$src_executable" "$dest_executable"
  set +x

  _log
  _log "Success, copied:"
  _log "         $src_executable"
  _log "   to -> $dest_executable"

  _log ""
  set -x
  git add bin/"$variant"
  git status bin/"$variant"
  set +x

  _log ""
}

_log() { >&2 echo "$@" ; }

copy_compiled_executable_to_bin() {
  local compiled_executable="$1"
  shift

  local variant="$1"
  shift

  local host_triple="$1"
  shift

  local destination_executable="bin/$variant/$host_triple/shonion"
  set -x
  cp "$compiled_executable" "$destination_executable"
  set +x
  _pass_via_stdout "$destination_executable"
}

_pass_via_stdout() { echo -n "$@" ; }
get_target_dir() {
  _pass_via_stdout "target/$1/$(./scripts/get-host-triple.sh)"
}
get_target_executable() {
  local variant="$1" ; shift ;
  _pass_via_stdout "$(get_target_dir "$variant")"/release/shonion
}


main "$@"
