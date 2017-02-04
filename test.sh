#!/bin/bash
# Run tests against Mattermost installation on a Vagrant virtual machine.
#
# The VM is provisioned with a fresh Yunohost install, then snapshotted
# for subsequent runs.

# Fail on first error
set -e

# Configuration constants
TESTS_DIR="/home/vagrant/tests"
APP_DIR="$TESTS_DIR/mattermost_ynh"
VM_ROOT_PASSWORD="alpine"
YUNOHOST_ADMIN_PASSWORD="alpine"

function _usage() {
  echo "Run tests against Mattermost installation on a Vagrant virtual machine."
  echo "Usage: test.sh [--skip-snapshot] [--verbose] [--help]"
}

# Configuration arguments
function _parse_args() {
  VERBOSE=false
  SKIP_SNAPSHOT=false
  while [ "$1" != "" ]; do
    case $1 in
      "-v" | "--verbose")
        shift
        VERBOSE=true;;
      "-s" | "--skip-snapshot")
        shift
        SKIP_SNAPSHOT=true;;
      "--help")
        _usage
        exit;;
      *)
        _usage
        exit 1;;
    esac
    shift
  done
}

# Execute an ssh command on the vagrant box
function _vagrant_ssh() {
  local command="$1"
  local tty_output=$([ $VERBOSE ] && echo '/dev/stdout' || echo '/dev/null')

  [ $VERBOSE == true ] && echo "vagrant ssh -c \"$command\""

  vagrant ssh -c "$command" \
    > $tty_output \
    2> >(grep --invert-match 'Connection to 127.0.0.1 closed.' 1>&2) # Filter out the SSH deconnection message printed on stderr
}

function _assert_success() {
  local message="$1"
  local command="$2"

  local RED=`tput setaf 1`
  local GREEN=`tput setaf 2`
  local BOLD=`tput bold`
  local RESET=`tput sgr0`

  set +e  # Allow continuing the script on failures
  if _vagrant_ssh "$command"; then
    printf "[${GREEN}${BOLD}OK${RESET}] $message\n"
  else
    printf "[${RED}${BOLD}KO${RESET}] $message\n"
  fi
  set -e  # Fail again on first error
}

function setup() {
  if $SKIP_SNAPSHOT; then
    echo "--- Starting Vagrant box ---"
    vagrant up
    echo "--- (Skipping snapshot restore) ---"
    return
  fi

  if (vagrant snapshot list | grep 'yunohost-2.4-pristine' > /dev/null); then
    echo "--- Restoring Vagrant snapshot ---"
    vagrant snapshot restore yunohost-2.4-pristine
  else
    echo "--- Provisioning Vagrant box ---"
    vagrant up --provision
    echo "--- Saving Vagrant snapshot ---"
    vagrant snapshot save yunohost-2.4-pristine
  fi

  echo "--- Copying app content into the box ---"
  if ! [ -d "$APP_DIR" ]; then
    _vagrant_ssh "mkdir -p '$TESTS_DIR'"
    _vagrant_ssh "cp -R '/vagrant' '$APP_DIR'"
  fi
}

function run_tests() {
  echo "--- Running package_check ---"
  _vagrant_ssh "package_check/package_check.sh --bash-mode --no-lxc '$APP_DIR'"
}

function teardown() {
  echo "--- Cleaning up ---"
}

_parse_args $*
setup
run_tests
teardown
