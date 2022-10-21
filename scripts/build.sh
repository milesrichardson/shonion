cd "$(dirname "$(git rev-parse --git-dir)")"
exec_name="$0"

main() {
  build_static
  build_dynamic

  _log ""
  _log "[COMPILED executables]"

  if ! should_skip_static ; then
    local static_artifact="$(get_artifact_path static)"
    _log "    -> static: $static_artifact"
    _log "               $(ls -lh "$static_artifact" | awk '{ print $5 " " $9 }')"
  else
    _log "    -> static: SKIPPED"
  fi

  _log ""

  if should_build_dynamic ; then
    local dynamic_artifact="$(get_artifact_path dynamic)"
    _log "    -> dynamic: $dynamic_artifact"
    _log "                $(ls -lh "$static_artifact" | awk '{ print $5 " " $9 }')"
  else
    _log "    -> dynamic: SKIPPED"
  fi
}

build_static() {
  if should_skip_static && should_build_dynamic ; then
    _log ""
    _log "[SKIP BUILD static executable]"
    _log "    skipping build of static executable because BUILD_STATIC=$BUILD_STATIC"
  elif should_skip_static && ! should_build_dynamic ; then
    _log "...but also skipping dynamic because BUILD_DYNAMIC is set, but not to 1"
    _log "To build only dynamic:         BUILD_DYNAMIC=1 BUILD_STATIC=0 $0 $@"
    return
  fi

  _log ""
  _log "[BUILD static executable]"
  _log "    Building standalone executable with static links to openssl, lzma and zstd..."

  set -e
  cargo build --release --features xplat --target-dir "$(get_target_dir static)"
  set +e
}

build_dynamic() {

  if ! should_build_dynamic ; then
    _log ""
    _log "[SKIP BUILD dynamic executable]"
    _log "    Not building executable with dynamic links to openssl, lzma and zstd"
    _log "          to build dynamic executable: BUILD_DYNAMIC=1 $exec_name $@"
    _log "         or *only* dynamic executable: BUILD_DYNAMIC=1 BUILD_STATIC=0 $exec_name $@"
    _log ""
    return
  fi

  _log ""
  _log "[BUILD dynamic executable] (dynamic links to openssl, lzma and zstd)"
  _log "    Building executable with dynamic links to openssl, lzma and zstd..."
  set -e
  cargo build --release --target-dir "$(get_target_dir dynamic)"
  set +e
  _log ""
}

should_skip_static() {
  test -n "$BUILD_STATIC" && test "$BUILD_STATIC" -ne "1" && return 0
  return 1
}

should_build_dynamic() {
  test -n "$BUILD_DYNAMIC" && test "$BUILD_DYNAMIC" == "1" && return 0
  return 1
}

get_target_dir() {
  _pass_via_stdout "target/$1/$(./scripts/get-host-triple.sh)"
}


get_artifact_path() {
  local variant="$1"
  shift

  local host_triple="${1-"$(./scripts/get-host-triple.sh)"}"
  local artifact_path="target/$variant/$host_triple/release/shonion"

  if test ! -f "$artifact_path" ; then
    _log "Error: failed post-build verification, missing artifact at:" "$1"
    exit 1
  fi

  _pass_via_stdout "$artifact_path"
}



copy_executable() {
  local host_triple="$1"
  shift
  local variant="$1"
  shift

  mkdir -p bin/"$variant"

  local executable_name="shonion-$host_triple"
  local executable_path="bin/$executable_name"

  if ! test -f "$executable_path" ; then
    _log "missing executable at: $executable_path"
    _log "Have you built it yet? Try:"
    _log "  ./scripts/build-static.sh (standalone binary with vendored openssl, lzma, zstd)"
    _log "  ./scripts/build-dynamic.sh (static binary with dynamic link to openssl, lzma, zstd)"
    exit 2
  fi

  _log "Copying executable into bin/ ..."
  local copied_to="$(copy_compiled_executable_to_bin "$executable_path" "static" "$host_triple")"

  _log "copied:  $executable_path"
  _log "   to -> $copied_to"
}

_log() { >&2 echo "$@" ; }
_pass_via_stdout() { echo -n "$@" ; }


main "$@"
