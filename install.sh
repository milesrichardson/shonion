#!/usr/bin/env sh

SHONION_HOME_DIR="${HOME-"/tmp"}/.shonion"
mkdir -p "$SHONION_HOME_DIR"

SHONION_BIN="${SHONION_BIN}"
SHONION_REPO="${SHONION_REPO-"https://github.com/milesrichardson/shonion"}"
SHONION_BIN_URL="${SHONION_BIN_URL}"
SHONION_BUILD_DIR="${SHONION_BUILD_DIR-"$HOME/.shonion"}"
SHONION_UPDATE="${SHONION_UPDATE-"0"}"
SHONION_CLIENT="${SHONION_CLIENT-"1"}"
SHONION_LISTENER="${SHONION_LISTENER-"1"}"
SHONION_FORK_TO_CLIENT="${SHONION_FORK_TO_CLIENT-"0"}"
SHONION_FORK_TO_LISTENER="${SHONION_FORK_TO_LISTENER-"0"}"

main() {
  _configure && _require_deps && _download_shonion && _validate_env
}

_validate_env() {
  _dump_env
}

_dump_env() {
  echo "SHONION_REPO=$SHONION_REPO"
  echo "SHONION_BIN_URL=$SHONION_BIN_URL"
  echo "SHONION_BIN=$SHONION_BIN"
  echo "SHONION_BUILD_DIR=$SHONION_BUILD_DIR"
  echo "SHONION_UPDATE=$SHONION_UPDATE"
  echo "SHONION_LISTENER=$SHONION_LISTENER"
  echo "SHONION_CLIENT=$SHONION_CLIENT"
}

_require_deps() {
  _require_dep "base64"

  if ! _check_dep wget wget ; then
    if ! _check_dep curl curl ; then
      _fatal "either wget or curl is required, but neither is installed"
    fi
  fi

  if _is_client ; then
    _require_dep "ssh" "openssh-client"
  fi

  if _is_listener ; then
    _require_dep "sshd" "openssh-server"
  fi
}

_require_dep() {
  _check_dep "$@" || _fatal "missing bin $dep, unable to automatically install"
}

_is_command() {
  maybe_exec="$(command -v "$1")"
  if test -x "$maybe_exec" ; then return 0 ; else return 1; fi ;
}

did_package_manager_update=no
_check_dep() {
  dep="$1"
  shift
  maybe_exec="$(command -v "$dep")"
  if ! test -x "$maybe_exec" ; then
    echo "missing required executable: $dep"
    _try_install_dep "$@" || return 1
  else
    echo "found required executable $dep at: $maybe_exec"
  fi
}

_updated_pkg_mgr() {
  test "$did_package_manager_update" = "yes" && return 0
  return 1
}

_try_install_dep() {
  if ! _can_install_packages ; then
    return 1
  fi

  if test $# -eq 0 ; then
    return 1
  fi

  _log "try install:" "$@"

  if test -x "$(command -v apt-get)" ; then
    _updated_pkg_mgr || apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -yy "$@"
  elif test -x "$(command -v apt)" ; then
    _updated_pkg_mgr || { apt update && apt-get update -qq ; }
    DEBIAN_FRONTEND=noninteractive apt-get install -yy "$@"
  elif test -x "$(command -v apk)" ; then
    _updated_pkg_mgr || apk update
    DEBIAN_FRONTEND=noninteractive apk add "$@"
  elif test -x "$(command -v yum)" ; then
    _updated_pkg_mgr || yum check-update
    yum install "$@"
  else
    return 1
  fi

  did_package_manager_update=yes
  return 0
}

_can_install_packages() {
  case $(uname | tr '[:upper:]' '[:lower:]') in
    linux*)  return 0 ;;
    darwin*) return 1 ;;
    *)       return 1 ;;
  esac
}

_download_shonion() {
  if test -n "$SHONION_BIN" && ! test -f "$SHONION_BIN" ; then
    _fatal "SHONION_BIN is set to non-existent file: $SHONION_BIN"
  fi

  mkdir -p "$SHONION_BUILD_DIR"

  SHONION_BIN="$SHONION_BUILD_DIR"/shonion

  if test -f "$SHONION_BIN" && test "$SHONION_UPDATE" != "1" ; then
    _log "shonion binary already exists at" "$SHONION_BIN"
    _log "to download it anyway, set SHONION_UPDATE=1"
    return
  fi

  _log "downloading shonion"
  _log "    from $SHONION_BIN_URL"
  _log "    to   $SHONION_BIN"

  _fetch "$SHONION_BIN_URL" "$SHONION_BIN"
  chmod +x "$SHONION_BIN"
  _log "downloaded shonion to $SHONION_BIN"
}

_fetch() {
  url="$1"
  shift
  dest="$1"
  shift

  _fetch_wget() { echo "FETCH via wget" && wget -O "$dest" "$url" && return 1 ; }
  _fetch_curl() { echo "FETCH via curl" && curl -L "$url" -o "$dest" ; }

  if _is_command wget ; then
    if ! _fetch_wget ; then
      if _check_dep curl curl ; then
        _fetch_curl || _fatal "download failed"
      fi
    fi
  elif _check_dep curl curl ; then
    _fetch_curl || _fatal "download failed"
  fi

  _log "download success"
  return 0
}

_configure() {
  if test -n "$SHONION_BIN" && ! test -f "$SHONION_BIN" ; then
    _fatal "SHONION_BIN is set to non-existent file: $SHONION_BIN"
  fi

  _arch_url() {
    echo "https://github.com/milesrichardson/shonion/blob/main/bin/static/$1/shonion?raw=true"
  }

  _unknown_arch() {
    _log "Error: could not detect compatible architecture for binary"
    _log "To fix, download a bin from $SHONION_REPO"
    _log "and set SHONION_BIN=/path/to/shonion/bin"
  }

  case $(uname | tr '[:upper:]' '[:lower:]') in
    linux*)  SHONION_BIN_URL="$(_arch_url "x86_64-unknown-linux-gnu")" ;;
    darwin*) SHONION_BIN_URL="$(_arch_url "x86_64-apple-darwin")" ;;
    *)       _unknown_arch ;;
  esac

  export SHONION_BIN_URL
}

_is_darwin() {
  test "$(uname | tr '[:upper:]' '[:lower:]')" == "darwin" && return 0
  return 1
}

_is_linux() {
  test "$(uname | tr '[:upper:]' '[:lower:]')" == "linux" && return 0
  return 1
}

_log() {
  echo "$@" >&2
}

_fatal() {
  _log "fatal:" "$@"
  exit 1
}

_is_client() {
  test "$SHONION_CLIENT" = "1" && return 0
  return 1
}

_is_listener() {
  test "$SHONION_LISTENER" = "1" && return 0
  return 1
}

main "$@"
