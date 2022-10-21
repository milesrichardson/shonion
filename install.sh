#!/usr/bin/env sh

SHONION_HOME_DIR="${HOME-"/tmp"}/.shonion"
mkdir -p "$SHONION_HOME_DIR"

SHONION_BIN="${SHONION_BIN}"
SHONION_REPO="${SHONION_REPO-"https://github.com/milesrichardson/shonion"}"
SHONION_BIN_URL="${SHONION_BIN_URL}"
SHONION_BUILD_DIR="${SHONION_BUILD_DIR-"$HOME/.shonion"}"
SHONION_UPDATE="${SHONION_UPDATE-"0"}"
SHONION_FORK_TO_CLIENT="${SHONION_FORK_TO_CLIENT-"0"}"
SHONION_FORK_TO_LISTENER="${SHONION_FORK_TO_LISTENER-"0"}"
SHONION_LISTENER_ROOT="${SHONION_LISTENER_ROOT-""}"

SHONION_TOR_ROOT="/tmp/tor-rust"

main() {
  _parse_cli_opts "$@"

  _configure && _require_deps && _download_shonion && _validate_env && fork_to_work
}

fork_to_work() {
  if _should_fork_to_listener ; then
    _fork_to_listener
  elif _should_fork_to_client ; then
    _fork_to_client
  else
    _log "Not forking to any new process"
    _log "      to fork to client: SHONION_FORK_TO_CLIENT=1 $0"
    _log "    to fork to listener: SHONION_FORK_TO_LISTENER=1 $0"
  fi
}

# _wait_for_shutdown() {
#   until [ -f "$hostname_file" ]
#   do
#       sleep 5
#   done
# }

PID_SHONION=
_cleanup() {
  echo "Kill Shonion ($PID_SHONION)"
  kill -9 "$PID_SHONION" || true

  echo "KILL SSHD FROM" "$SHONION_LISTENER_ROOT"/sshd.pid
  xargs kill -9 < "$SHONION_LISTENER_ROOT"/sshd.pid || true
}

_fork_to_listener() {
  _log "[TODO] forking to listener ...."

  "$SHONION_BIN" &
  PID_SHONION=$!
  trap 'echo CLEANUP shonion pid $PID_SHONION ; kill $PID_SHONION' INT

  _wait_for_onion_hostname

  _setup_listener_dir

  /usr/sbin/sshd \
-o Port=5678 \
-o StrictModes=no \
-o HostKey="$SHONION_LISTENER_ROOT"/ssh_host_rsa_key \
-o PidFile="$SHONION_LISTENER_ROOT"/sshd.pid \
-o KbdInteractiveAuthentication=no \
-o ChallengeResponseAuthentication=no \
-o PasswordAuthentication=no \
-o UsePAM=yes \
-o AuthorizedKeysFile="$SHONION_LISTENER_ROOT"/authorized_keys

  _log "sshd.pid: $SHONION_LISTENER_ROOT/sshd.pid"

  _print_client_instructions

  wait "$PID_SHONION"

  _log "Done ."
}


_wait_for_onion_hostname() {
  hostname_file="$SHONION_TOR_ROOT/hs-dir/hostname"
  _log "Wait for .onion hostname: $hostname_file ..."
  until [ -f "$hostname_file" ]
  do
      sleep 5
  done
  _log "found hostname: $(_get_onion_hostname)"
}

# _wait_for_tor_network() {
#   _log "Wait for Tor network to be up ..."
#   until [ -n "$()" ]
#   do
#       sleep 5
#   done
# }

_get_onion_hostname() {
  cat "$SHONION_TOR_ROOT/hs-dir/hostname"
}

_fork_to_client() {
  _log "[TODO] forking to client ...."
}

_setup_listener_dir() {
  test -n "$SHONION_LISTENER_ROOT" || SHONION_LISTENER_ROOT="$(mktemp -d)"

  test -n "$SHONION_LISTENER_ROOT" || _fatal "SHONION_LISTENER_ROOT not defined"
  test -d "$SHONION_LISTENER_ROOT" || _fatal "SHONION_LISTENER_ROOT $SHONION_LISTENER_ROOT is not dir"
  mkdir -p "$SHONION_LISTENER_ROOT"

  _log "[LISTENER ROOT] $SHONION_LISTENER_ROOT"

  trap '_cleanup' INT

  _compile_client_script

  _log "[CLIENT SCRIPT]" "$SHONION_LISTENER_ROOT/connect.sh"
  _log "---"
  cat "$SHONION_LISTENER_ROOT/connect.sh"
  _log "---"
}

_print_client_instructions() {
  echo
  _log "Listening..."
  _log "To connect from another machine, paste this into a terminal:"

  tee <<EOC
bash <(echo "$(base64 -w0 "$SHONION_LISTENER_ROOT"/connect.sh)" | base64 -D)
EOC
}

_compile_client_script() {

  echo "CWD IS: $(pwd)"
  cd "$SHONION_LISTENER_ROOT" || _fatal "failed cd $SHONION_LISTENER_ROOT"
  echo "CWD IS: $(pwd)"

  touch sshd.pid \
  && ssh-keygen -f id_shonion_client_rsa -N '' \
  && cat id_shonion_client_rsa.pub > authorized_keys \
  && ssh-keygen -f ssh_host_rsa_key -N ''

cat <<EOC > "$SHONION_LISTENER_ROOT/connect.sh"
#!/usr/bin/env bash

cd \$(mktemp -d)

tee id_shonion_client_rsa <<EOX
$(cat id_shonion_client_rsa)
EOX

tee id_shonion_client_rsa.pub <<EOX
$(cat id_shonion_client_rsa.pub)
EOX

chmod 0400 id_shonion_client_rsa id_shonion_client_rsa.pub

exec ssh -v \\
    -F /dev/null \\
    -o IdentityFile=\$PWD/id_shonion_client_rsa \\
    -o IdentitiesOnly=yes \\
    -o ConnectTimeout=120 \\
    -o StrictHostKeychecking=no \\
    -o UserKnownHostsFile=/dev/null \\
    -o "proxyCommand=nc -x 127.0.0.1:19050 -X 5 %h %p" \\
$(whoami)@$(cat /tmp/tor-rust/hs-dir/hostname) -p 34567
EOC

  cd - || _fatal "failed cd back"
  echo "CWD IS: $(pwd)"
}

_parse_cli_opts() {
  while test "$#" -gt 0 ; do
    nextarg="$1"
    case "$nextarg" in
      --connect)  shift ; SHONION_FORK_TO_CLIENT=1 ;;
      --listen) shift ; SHONION_FORK_TO_LISTENER=1 ;;
    esac
  done
}

_should_fork_to_client() {
  test "$SHONION_FORK_TO_CLIENT" = "1" || return 1
  return 0
}

_should_fork_to_listener() {
  test "$SHONION_FORK_TO_LISTENER" = "1" || return 1
  return 0
}

_validate_env() {
  _dump_env

  test -n "$SHONION_BIN" || _fatal "SHONION_BIN is not set"
  test -x "$SHONION_BIN" || _fatal "SHONION_BIN is not executable at $SHONION_BIN"

  if test "$SHONION_FORK_TO_CLIENT" = "1" && test "$SHONION_FORK_TO_LISTENER" = "1" ; then
    _fatal "cannot fork to both client and server"
  fi

}

_dump_env() {
  echo "SHONION_REPO=$SHONION_REPO"
  echo "SHONION_BIN_URL=$SHONION_BIN_URL"
  echo "SHONION_BIN=$SHONION_BIN"
  echo "SHONION_BUILD_DIR=$SHONION_BUILD_DIR"
  echo "SHONION_UPDATE=$SHONION_UPDATE"
  echo "SHONION_FORK_TO_LISTENER=$SHONION_FORK_TO_LISTENER"
  echo "SHONION_FORK_TO_CLIENT=$SHONION_FORK_TO_CLIENT"
  echo "SHONION_LISTEN_ROOT=$SHONION_LISTEN_ROOT"
}

_require_deps() {
  _require_dep "base64" "base64"

  # if _is_client ; then
  #   _require_dep "ssh" "openssh-client"
  # fi

  # if _is_listener ; then
  #   _require_dep "sshd" "openssh-server"
  # fi
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

  _fetch_wget() { _log "[FETCH via wget]" && wget -O "$dest" "$url" ; }
  _fetch_curl() { _log "[FETCH via curl]" && curl -L "$url" -o "$dest" ; }

  if _check_dep wget wget ; then
    if ! _fetch_wget ; then
      _log "wget download failed, trying curl..."
      if _check_dep curl curl ; then
        _fetch_curl || _fatal "download failed via wget and via curl"
      else
        _fatal "download failed via wget, and curl is not available"
      fi
    fi
  elif _check_dep curl curl ; then
    if ! _fetch_curl ; then
      _log "curl download failed, trying wget..."
      if _check_dep wget wget ; then
         _fetch_wget || _fatal "download failed via curl and via wget"
      else
        _fatal "download failed via curl, and wget is not available"
      fi
    fi
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


main "$@"
