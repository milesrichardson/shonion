

_get_tini_version() {

  local latest="v0.19.0"
  local arch="$(_get_tini_arch)"

  _pass_via_stdout "https://github.com/krallin/tini/releases/download/$latest/tini-$arch"
}

_get_tini_arch() {

}


TINI_VERSION=get_tini_version

wget --no-check-certificate --no-cookies --quiet https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-amd64 \
    && wget --no-check-certificate --no-cookies --quiet https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-amd64.sha256sum \
    && echo "$(cat tini-amd64.sha256sum)" | sha256sum -c



_log() { >&2 echo "$@" ; }
_pass_via_stdout() { echo -n "$@" ; }
