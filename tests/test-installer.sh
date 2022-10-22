#!/usr/bin/env bash
# Script to automate running shonion.sh on multiple platforms.
# Does not make any assertions.
#

cd "$(dirname "$(git rev-parse --git-dir)")" || { echo "bad cd" ; exit 2 ; }

PASSED=()
FAILED=()

RESULTS="$(mktemp -d)"

main() {

  if test "$#" -gt 0 ; then
    while test "$#" -gt 0 ; do
      run_installer "$1"
      shift
    done
  else
    run_tests "$@"
  fi

  report_results
}

run_tests() {
  run_installer alpine:latest "$@"
  run_installer ubuntu:latest "$@"
}

report_results() {

  num_passed=${#PASSED[@]}
  num_failed=${#FAILED[@]}

  _log ""
  _log "---"

  if test "$num_passed" -gt 0 ; then
    _log "PASSED  ($num_passed) >" "${PASSED[@]}"
  fi

  if test "$num_failed" -gt 0 ; then
    _log "FAILED  ($num_failed) >" "${FAILED[@]}"
    if test "$num_passed" -gt 0 ; then
      _log "RESULTS     : some tests failed"
    else
      _log "RESULTS     : all tests failed"
    fi
  else
    _log "RESULTS     : all tests passed"
  fi

  _log ""
  _log "Logs saved to disk:"
  find "$RESULTS" -type f
}

run_installer() {
  local docker_ref="$1"
  shift

  _log "[RUN INSTALLER]" "$docker_ref" sh shonion.sh

  set -o pipefail
  if docker run --rm -it -v "$(pwd)":/app -w /app "$docker_ref" sh shonion.sh "$@" | tee "$(_log_to "$docker_ref")" ; then
    PASSED+=("$docker_ref")
  else
    FAILED+=("$docker_ref")
  fi
  set +o pipefail
}

_log_to() {
  local docker_ref="$1"
  echo -n "$RESULTS/${docker_ref//:/__}".stdout.log
}

_log() { echo "$@" >&2 ; }

main "$@"



