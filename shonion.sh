#!/usr/bin/env sh

SHONION_HOME_DIR="${HOME-"/tmp"}/.shonion"
mkdir -p "$SHONION_HOME_DIR"

SHONION_BIN="${SHONION_BIN}"
SHONION_REPO="${SHONION_REPO-"https://github.com/milesrichardson/shonion"}"
SHONION_SCRIPT_PATH="$(pwd)/shonion.sh"
SHONION_SCRIPT_ADDR="${SHONION_REPO}/blob/main/shonion.sh?raw=true"
SHONION_BIN_URL="${SHONION_BIN_URL}"
SHONION_BUILD_DIR="${SHONION_BUILD_DIR-"$HOME/.shonion"}"
SHONION_UPDATE="${SHONION_UPDATE-"0"}"
SHONION_FORK_TO_CLIENT="${SHONION_FORK_TO_CLIENT-"0"}"
SHONION_FORK_TO_LISTENER="${SHONION_FORK_TO_LISTENER-"0"}"
SHONION_LISTENER_ROOT="${SHONION_LISTENER_ROOT-""}"
SHONION_CLIENT_ROOT="${SHONION_CLIENT_ROOT-""}"
SHONION_TORRC="${SHONION_TORRC-""}"

SHONION_STDOUT="$SHONION_BUILD_DIR/shonion.stdout.log"

SHONION_TOR_ROOT="/tmp/tor-rust"

main() {
  _parse_cli_opts "$@"

  _configure && _require_deps && _download_shonion && _validate_env && fork_to_work
}

fork_to_work() {
  _require_dep "nc" "netcat"

  _check_dep "curl" "curl" || { _log "warning: missing curl will break connectivity checks" ; }

  if _should_fork_to_listener ; then
    _require_dep "sshd" "openssh-server"

    _fork_to_listener
  elif _should_fork_to_client ; then
    _require_dep "ssh" "openssh-client"

    _fork_to_client
  else
    _log "Not forking to any new process."
    _log "      to fork to client: SHONION_FORK_TO_CLIENT=1 $0"
    _log "                     or: $0 --connect"
    _log ""
    _log "    to fork to listener: SHONION_FORK_TO_LISTENER=1 $0"
    _log "                     or:    $0 --listen"
  fi
}

PID_SHONION=
PID_SHONION_LOGTAIL=
_cleanup() {
  echo "Kill Shonion ($PID_SHONION)"
  kill "$PID_SHONION" || kill -9 "$PID_SHONION" || true

  echo "Kill Shonion Log Tailer ($PID_SHONION_LOGTAIL)"
  kill "$PID_SHONION_LOGTAIL" || kill -9 "$PID_SHONION_LOGTAIL" || true

  echo "Kill SSHD from from PID file:" "$SHONION_LISTENER_ROOT"/sshd.pid
  xargs kill -9 < "$SHONION_LISTENER_ROOT"/sshd.pid || true
}

_run_shonion_in_background() {

  if test -f "$SHONION_STDOUT" ; then
    echo "deleting existing log file at $SHONION_STDOUT"
    rm "$SHONION_STDOUT"
  fi

  if test -z "$SHONION_TORRC" ; then
    SHONION_TORRC="$HOME/.torrc"
  fi

  if test ! -f "$SHONION_TORRC" ; then
    SHONION_TORRC="$(mktemp)"
    _log "temporary .torrc: $SHONION_TORRC"
    echo "" >> "$SHONION_TORRC"
  fi

  set -x
  ls "$(dirname "$SHONION_BIN")"
  set +x

  $SHONION_BIN --config "$SHONION_TORRC" > "$SHONION_STDOUT" 2>&1 &
  PID_SHONION=$!

  tail -f "$SHONION_STDOUT" &
  PID_SHONION_LOGTAIL=$!

  trap 'echo CLEANUP shonion and logtail ; kill $PID_SHONION || kill -9 $PID_SHONION || true ; kill -9 $PID_SHONION_LOGTAIL || true ;' EXIT
}

_fork_to_listener() {
  _log "[LISTENER] forking to listener ...."

  _setup_listener_dir

  _run_shonion_in_background

  _wait_for_onion_hostname

  _compile_client_script

  _log "sshd.pid: $SHONION_LISTENER_ROOT/sshd.pid"

  _wait_for_tor_bootstrap
  _wait_for_tor_clearnet
  _wait_for_own_onion_service
  _print_client_instructions

  /usr/sbin/sshd -f /dev/null -e -D \
-o ListenAddress=127.0.0.1:5678 \
-o StrictModes=no \
-o HostKey="$SHONION_LISTENER_ROOT"/ssh_host_rsa_key \
-o PidFile="$SHONION_LISTENER_ROOT"/sshd.pid \
-o AuthenticationMethods=publickey \
-o KbdInteractiveAuthentication=no \
-o ChallengeResponseAuthentication=no \
-o PasswordAuthentication=no \
-o UsePAM=no \
-o AuthorizedKeysFile="$SHONION_LISTENER_ROOT"/authorized_keys

  wait "$PID_SHONION"

  _log "Done ."
}


_wait_for_onion_hostname() {
  hostname_file="$SHONION_TOR_ROOT/hs-dir/hostname"
  _log "[WAIT] for generated .onion hostname: $hostname_file ..."
  until [ -f "$hostname_file" ]
  do
    _log "[WAIT] for $hostname_file ..."
    sleep 5
  done
  _log "[OK] found hostname: $(_get_onion_hostname)"
}

_wait_for_tor_bootstrap() {
  while ! grep -q 'Bootstrapped 100%' "$SHONION_STDOUT" ; do
    _log "[WAIT] for tor bootstrap..."
    sleep 5
  done

  _log "[OK] Tor bootstrapped"
}

_wait_for_own_onion_service() {
  onion_hostname="$(_get_onion_hostname)"
  onion_port=34567

  _log "[WAIT] checking onion network connectivity back to self..."
  _log "[WAIT] this might take a few minutes (retry interval is 120 seconds)"
  sentinel_dir="$(mktemp -d)"
  until [ -f "$sentinel_dir/success.txt" ]
  do
    _log "[WAIT] check nc back to localhost via $onion_hostname $onion_port"
    _check_self_onion && touch "$sentinel_dir/success.txt"
    sleep 5
  done

  _log "[OK] $onion_hostname $onion_port looks up (that's us, via 6 proxies)"
}

# note: assumes hardcoded port numbers from shonion defaults (same as other places in this script)
_check_self_onion() {
  start=$(date +%s) ; NC_PID="$(nc -vrl 127.0.0.1 5678 >/dev/null 2>/dev/null & echo $! )" \
    && nc -tvz -x 127.0.0.1:19050 -X 5 "$(cat /tmp/tor-rust/hs-dir/hostname)" 34567 \
    && echo "success in $(($(date +%s)-start)) seconds" \
    && { kill "$NC_PID" || true ; } && return 0

  return 1
}

_wait_for_tor_clearnet() {
  _log "[WAIT] for Tor network clearnet reachability ..."
  sentinel_dir="$(mktemp -d)"
  until [ -f "$sentinel_dir/success.txt" ]
  do
      _log "[WAIT] send HTTP GET via SOCKS proxy to https://www.cloudflare.com/cdn-cgi/trace"
      curl -q --socks5-hostname 127.0.0.1:19050 https://www.cloudflare.com/cdn-cgi/trace && touch "$sentinel_dir/success.txt"
      sleep 5
  done

  _log "[OK] clearnet is reachable via SOCKS proxy"
}

_get_onion_hostname() {
  cat "$SHONION_TOR_ROOT/hs-dir/hostname"
}

_fork_to_client() {
  _log "[CLIENT] forking to client ...."
  _run_shonion_in_background

  test -d "$SHONION_CLIENT_ROOT" || _fatal "forked to client without defined SHONION_CLIENT_ROOT"
  cd "$SHONION_CLIENT_ROOT" || _fatal "failed cd $SHONION_CLIENT_ROOT"

  _wait_for_tor_bootstrap

  _wait_for_tor_clearnet

  _wait_for_own_onion_service

  exec ssh -v \
    -F /dev/null \
    -o IdentityFile="$(pwd)"/id_shonion_client_rsa \
    -o IdentitiesOnly=yes \
    -o ConnectTimeout=120 \
    -o StrictHostKeychecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o "proxyCommand=nc -x 127.0.0.1:19050 -X 5 %h %p" \
"$SHONION_CLIENT_SSH_USER"@"$SHONION_CLIENT_DEST_ONION_HOST" -p "$SHONION_CLIENT_DEST_ONION_PORT"
}

_setup_listener_dir() {
  test -n "$SHONION_LISTENER_ROOT" || SHONION_LISTENER_ROOT="$(mktemp -d)"

  test -n "$SHONION_LISTENER_ROOT" || _fatal "SHONION_LISTENER_ROOT not defined"
  test -d "$SHONION_LISTENER_ROOT" || _fatal "SHONION_LISTENER_ROOT $SHONION_LISTENER_ROOT is not dir"
  mkdir -p "$SHONION_LISTENER_ROOT"

  _log "[LISTENER ROOT] $SHONION_LISTENER_ROOT"

  trap '_cleanup' EXIT

  echo "UseEntryGuards 0" >> "$SHONION_LISTENER_ROOT/.torrc"
  SHONION_TORRC="$SHONION_LISTENER_ROOT/.torrc"

  echo "CWD IS: $(pwd)"
  cd "$SHONION_LISTENER_ROOT" || _fatal "failed cd $SHONION_LISTENER_ROOT"

  touch sshd.pid \
  && ssh-keygen -f id_shonion_client_rsa -N '' \
  && cat id_shonion_client_rsa.pub > authorized_keys \
  && ssh-keygen -f ssh_host_rsa_key -N ''

  cd - || _fatal "failed cd back"

  # sshd "privilege separation directory" is non-configurable location /run/sshd
  # on systems that haven't yet had sshd installed (like many docker containers)
  # this doesn't exist yet, and so we create it. but it needs to be owned by root
  if ! test -d /run/sshd ; then
    if test "$(whoami)" == "root" ; then
      mkdir -p /run/sshd || true
    elif _userland_sudoer ; then
      sudo mkdir -p /run/sshd || { _log "WARN: no /run/sshd directory, sshd might fail to start" ; }
    fi
  fi

  if ! test -d /run/sshd ; then
    _log "WARN: no /run/sshd found, which might cause sshd to fail"
  fi
}

_print_client_instructions() {
  echo
  _log "Ready! Launching sshd to listen on $(cat /tmp/tor-rust/hs-dir/hostname):3456"
  _log "To connect from another machine, paste this into a terminal:"
  _log "----"

  tee <<EOC
bash <(echo "$(base64 -w0 "$SHONION_LISTENER_ROOT"/connect.sh)" | base64 -d)
EOC

  _log "---- Note: Some distributions use base64 -D (capitalized)"
}

_compile_client_script() {

  echo "CWD IS: $(pwd)"
  cd "$SHONION_LISTENER_ROOT" || _fatal "failed cd $SHONION_LISTENER_ROOT"
  echo "CWD IS: $(pwd)"

cat <<EOC > "$SHONION_LISTENER_ROOT/connect.sh"
#!/usr/bin/env bash

set +m

export SHONION_CLIENT_ROOT="\$(mktemp -d)"
cd \$SHONION_CLIENT_ROOT

tee id_shonion_client_rsa <<EOX
$(cat id_shonion_client_rsa)
EOX

tee id_shonion_client_rsa.pub <<EOX
$(cat id_shonion_client_rsa.pub)
EOX

chmod 0400 id_shonion_client_rsa id_shonion_client_rsa.pub

if test -f "\$SHONION_SCRIPT_PATH" ; then
  existing_path="\$SHONION_SCRIPT_PATH"
fi

export SHONION_SCRIPT_PATH="\$(mktemp -d)/shonion.sh"

if test -n "\$existing_path" ; then
  echo "copy existing \$existing_path to \$SHONION_SCRIPT_PATH"
  cp "\$existing_path" "\$SHONION_SCRIPT_PATH"
fi

if ! test -f "\$SHONION_SCRIPT_PATH" ; then
  curl -L "$SHONION_SCRIPT_ADDR" -o "\$SHONION_SCRIPT_PATH" || exit 1
  #scp developer-machine-when-wip:$SHONION_SCRIPT_PATH "\$SHONION_SCRIPT_PATH"
fi

if ! test -x "\$SHONION_SCRIPT_PATH" ; then
  chmod +x "\$SHONION_SCRIPT_PATH"
fi

export SHONION_CLIENT_SSH_USER=$(whoami)
export SHONION_CLIENT_DEST_ONION_HOST=$(cat /tmp/tor-rust/hs-dir/hostname)
export SHONION_CLIENT_DEST_ONION_PORT=34567

exec "\$SHONION_SCRIPT_PATH" --connect "\$@"
EOC

  _log "[CLIENT SCRIPT]" "$SHONION_LISTENER_ROOT/connect.sh"
  _log "---"
  cat "$SHONION_LISTENER_ROOT/connect.sh"
  _log "---"

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

  if _should_fork_to_client ; then
    test -n "$SHONION_CLIENT_SSH_USER" || _fatal "missing SHONION_CLIENT_SSH_USER"
    test -n "$SHONION_CLIENT_DEST_ONION_HOST"  || _fatal "missing SHONION_CLIENT_DEST_ONION_HOST"
    test -n "$SHONION_CLIENT_DEST_ONION_PORT"  || _fatal "missing SHONION_CLIENT_DEST_ONION_PORT"
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
  echo "SHONION_LISTENER_ROOT=$SHONION_LISTENER_ROOT"
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

_userland_sudoer() {
  test "$(whoami)" != "root" \
    && test -x "$(command -v sudo)"  \
    && sudo -l -U "$(whoami)" \
    && return 0
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
    if _userland_sudoer ; then
      _updated_pkg_mgr || sudo apt-get update -qq
      DEBIAN_FRONTEND=noninteractive sudo apt-get install -yy "$@"
    else
      _updated_pkg_mgr || apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -yy "$@"
    fi
  elif test -x "$(command -v apt)" ; then
    if _userland_sudoer ; then
      _updated_pkg_mgr || { sudo apt update ; }
      DEBIAN_FRONTEND=noninteractive sudo apt install -yy "$@"
    else
      _updated_pkg_mgr || { apt update ; }
      DEBIAN_FRONTEND=noninteractive apt install -yy "$@"
    fi
  elif test -x "$(command -v apk)" ; then
    if _userland_sudoer ; then
      _updated_pkg_mgr || sudo apk update
      DEBIAN_FRONTEND=noninteractive sudo apk add "$@"
    else
      _updated_pkg_mgr || apk update
      DEBIAN_FRONTEND=noninteractive apk add "$@"
    fi
  elif test -x "$(command -v yum)" ; then
    if _userland_sudoer ; then
      _updated_pkg_mgr || sudo yum check-update
      sudo yum install "$@"
    else
      _updated_pkg_mgr || yum check-update
      yum install "$@"
    fi
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
    echo "$SHONION_REPO/blob/main/bin/static/$1/shonion?raw=true"
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
