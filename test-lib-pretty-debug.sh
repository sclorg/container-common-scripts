# shellcheck shell=bash
#
# Pretty debug framework
# ----------------------
# Purpose of the framework
# This concept helps debugging the tests, by seeing what commands were run
# before the failure and printing the verbose log only for test cases that
# failed.
# It also allows to run all tests even in if one of them fails, or run one
# test separately.
#
# Principles of the Pretty debug concept:
# The framework is based on a simple concept, that requires few things:
# * all individual test cases are in a separate file (why functions do not
# work is demonstrated in https://github.com/sclorg/postgresql-container/pull/363,
# it is caused by the implementation details about how 'set -o errexit' works)
# * instead of writing debug/info messages directly, functions ct_info,
#   ct_verbose, and ct_error are used
# * all important commands that should be run for reproducing the test case
#   should be wrapped with ct_run call, which stores those commands and prints
#   them in case of failure. That helps reproducing the test failure
# * the tests list is defined in a main runner and all test cases are run
#   separately, storing commands for reproducing and verbose output to a
#   separate file
# * these files are created for each test case:
#   * <tmp_dir>/.verbose_stream_<test_case> that stores all messages and their output
#   * <tmp_dir>/.journal_stream_<test_case> that stores all commands for reproducing
# * and one file for all test:
#   * <tmp_dir>/.pretty_debug that aggregates output of particular journal+verbose
#     logs from *failed* test cases
# * each test case should run ct_init at the beggining and ct_finish at the end
# * the main runner might be as simple as this:
#     TEST_LIST="testA testB" ; ct_init ; ct_run_all_tests $TEST_LIST ; ct_finish
# * an example how this can work is visible in the example-tests/ directory
#
# Level of detail for debugging can be changed by setting these variables:
# * CT_FAIL_QUICKLY=1  for debugging purposes, do not run anything more once
#                      one test fails
# * CT_VERBOSE=1       print the verbose log directly to stdout
# * CT_DEBUG=1         set when there is a problem in tests

# ct_init
# --------------------
# Enables Pretty debug mode, checks whether expected variables are defined and
# sets what needs to be set for Pretty debug mode.
# This function must be called in the beginning of the test case and also in
# the main wrapper script that runs all other test cases.
function ct_init() {
  set -o nounset
  shopt -s nullglob
  set -o errexit

  if [[ -v CT_DEBUG ]] ; then
    CT_FAIL_QUICKLY=1
    set -x
  fi

  # if this variable is already set, it means the test is already run through
  # a different script (usually the wrapper that runs all scripts)
  if [ -n "${__CT_TEST_NAME:-}" ] ; then
    # each test case needs to end ASAP
    set -o errexit
    # this function should be called in each test case, which means the test
    # case name changed, so we need to create new files
    _ct_open_pretty_debug
    return 0
  else
    __CT_TEST_NAME=$(basename "$0")
  fi

  TESTS_DIR=$(dirname "$0")
  _CT_VERBOSE_INDENT=''

  if [ "${CT_FAIL_QUICKLY:-0}" -eq 1 ]; then
    set -o errexit
  fi

  # shellcheck disable=SC2016
  test -n "${IMAGE_NAME-}" || false 'make sure $IMAGE_NAME is defined'
  # shellcheck disable=SC2016
  test -n "${VERSION-}" || false 'make sure $VERSION is defined'
  # shellcheck disable=SC2016
  test -n "${OS-}" || false 'make sure $OS is defined'

  CID_FILE_DIR=$(mktemp --suffix=test_cidfiles -d)
  __CT_PRETTY_DEBUG_DIR=$(mktemp --suffix=ct_pretty_debug -d)

  _ct_open_pretty_debug
  echo "Pretty debug enabled: using dir $__CT_PRETTY_DEBUG_DIR"

  # Export the variables for sub-commands (test cases)
  export __CT_PRETTY_DEBUG_DIR \
         CID_FILE_DIR \
         OS \
         VERSION \
         IMAGE_NAME \
         CT_FAIL_QUICKLY \
         CT_DEBUG \
         CT_VERBOSE \
         TESTS_DIR


  # This changes what ct_enable_cleanup usually does
  trap _ct_cleanup_with_pretty_debug EXIT SIGINT

  _CT_SHORT_SUMMARY=''
  _CT_TESTSUITE_RESULT=1
}

# ct_finish
# --------------------
# Function is supposed to be called at the end of the test case.
function ct_finish() {
  _CT_TESTSUITE_RESULT=0
}

# _ct_cleanup_with_pretty_debug
# --------------------
# Calls the standard ct_cleanup and then also prints the Pretty debug report.
function _ct_cleanup_with_pretty_debug() {
  ct_cleanup
  _ct_report_overall_results
}

# _ct_report_overall_results
# --------------------
# Prints overall results of all the tests, and prints the information for
# easier debugging using the Pretty debug framework.
function _ct_report_overall_results() {
  if [ -n "${_CT_SHORT_SUMMARY:-}" ] ; then
    if [ "${_CT_TESTSUITE_RESULT:-1}" -eq 0 ] ; then
      echo
      echo "Overall results:"
      echo "$_CT_SHORT_SUMMARY"
      echo "Tests for ${IMAGE_NAME} succeeded."
    else
      _ct_print_pretty_debug
      echo
      echo "Overall results:"
      echo "$_CT_SHORT_SUMMARY"
      echo "Tests for ${IMAGE_NAME} failed."
    fi
  fi
}

# ct_run_all_tests
# --------------------
# Loops through all the test cases that are given as arguments and runs them.
function ct_run_all_tests() {
  local suite_result=0

  # main test script must define this variable to not guess location of the tests
  if [ -z "${TESTS_DIR:-}" ] ; then
    echo "ERROR: TESTS_DIR variable not set."
    return 1
  fi

  if [ $# -eq 1 ] && [ "${1-}" == '--list' ] ; then
    echo "$TEST_LIST"
    exit 0
  fi

  # How to get list of test cases:
  # TESTS environment variable has the biggest priority
  # If TESTS is not defined, arguments of the script is taken
  # If no arguments specified, then TEST_LIST is used
  TESTS=${TESTS:-$@}
  TEST_LIST=${TESTS:-$TEST_LIST}

  # shellcheck disable=SC2068
  for test_case in $TEST_LIST; do
    export __CT_TEST_NAME=$test_case
    _ct_open_pretty_debug
    echo
    ct_info "Running test $test_case"
    _ct_write_journal "# Running test $test_case"

    if ! [ -e "$TESTS_DIR/$test_case" ] ; then
      printf -v _CT_SHORT_SUMMARY "%s[FAILED] %s not found or not executable (CWD: %s)\n" "${_CT_SHORT_SUMMARY}" "${test_case}" "$(pwd)"
      suite_result=1

    elif _CT_VERBOSE_INDENT='  ' "$TESTS_DIR/$test_case" ; then
      printf -v _CT_SHORT_SUMMARY "%s[PASSED] %s\n" "${_CT_SHORT_SUMMARY}" "${test_case}"
      ct_info "Tests for ${test_case} passed."

    else
      suite_result=$?
      printf -v _CT_SHORT_SUMMARY "%s[FAILED] %s\n" "${_CT_SHORT_SUMMARY}" "${test_case}"
      ct_error "Tests for ${test_case} failed with $suite_result."
      _ct_aggregate_pretty_debug >>"$(_ct_pretty_debug_file)"
      [ -n "${CT_FAIL_QUICKLY:-}" ] && return $suite_result
    fi
  done;

  return $suite_result
}

# ct_run
# --------------------
# Execs a command and stores it to the journal. All commands that should be
# used for reproducing a failed tests should use this wrapper instead of
# calling the command directly.
# Argument: --no-redirect  If set, output is not redirected. Usefule when
#                          ct_run output is important.
function ct_run() {
  local redirect=1
  [ $# -gt 0 ] && [ "$1" == '--no-redirect' ] && redirect=0 && shift
  _ct_write_journal "$@"
  _CT_VERBOSE_PREFIX="${_CT_VERBOSE_INDENT:-}$> " _ct_write_verbose_stream "$@"
  if ! _ct_pretty_debug_enabled || [ "$redirect" -eq 0 ] ; then
    # shellcheck disable=SC2068
    eval "$@"
  else
    # shellcheck disable=SC2068
    eval "$@" >>"$(_ct_verbose_file)" 2>&1
  fi
}

# ct_error
# --------------------
# Arguments are printed with an ERROR prefix and also stored into the verbose log.
function ct_error() {
  echo "${_CT_VERBOSE_INDENT:-}ERROR: $*" >&2
  _ct_write_verbose_stream "ERROR: $*"
}

# ct_verbose
# --------------------
# Arguments are not printed unless verbose mode is enabled by setting
# CT_VERBOSE variable, but they are stored into the verbose log every-time.
function ct_verbose() {
  [[ -v CT_VERBOSE ]] && echo "${_CT_VERBOSE_INDENT:-}$*" >&2
  _ct_write_verbose_stream "$*"
}

# ct_info
# --------------------
# Arguments are printed and also stored into the verbose log.
function ct_info() {
  echo "${_CT_VERBOSE_INDENT:-}$*" >&2
  _ct_write_verbose_stream "$*"
}

# _ct_open_pretty_debug
# --------------------
# Makes sure the files that other functions write to exist.
# Internal function, should not be called outside of this script.
function _ct_open_pretty_debug() {
  touch "$(_ct_journal_file)"
  touch "$(_ct_verbose_file)"
  touch "$(_ct_pretty_debug_file)"
}

# _ct_pretty_debug_enabled
# --------------------
# Returns 0 if the concept of 'Pretty debug' is used.
# Internal function, should not be called outside of this script.
function _ct_pretty_debug_enabled() {
  [ -n "${__CT_TEST_NAME:-}" ]
}

# _ct_print_pretty_debug
# --------------------
# Prints the content of the pretty debug file.
# Internal function, should not be called outside of this script.
function _ct_print_pretty_debug() {
  [ -f "$(_ct_pretty_debug_file)" ] && cat "$(_ct_pretty_debug_file)"
}

# _ct_aggregate_pretty_debug
# --------------------
# Takes content of the journal and verbose log files and generates a report for each test case.
# Internal function, should not be called outside of this script.
function _ct_aggregate_pretty_debug() {
  echo
  echo "========== [Pretty debug] Test case ${__CT_TEST_NAME} BEGIN =========="
  echo "----- [Pretty debug] reproducer / commands run:"
  cat "$(_ct_journal_file)"
  echo "----- [Pretty debug] verbose output:"
  cat "$(_ct_verbose_file)"
  echo "---------- [Pretty debug] Test case ${__CT_TEST_NAME} END ----------"
}

# _ct_journal_file
# --------------------
# Returns name of the file that stores commands run in each test case.
# Internal function, should not be called outside of this script.
function _ct_journal_file() {
  echo "${__CT_PRETTY_DEBUG_DIR:-}/.journal_stream_${__CT_TEST_NAME:-}"
}

# _ct_verbose_file
# --------------------
# Returns name of the file that stores verbose output for each test case.
# Internal function, should not be called outside of this script.
function _ct_verbose_file() {
  echo "${__CT_PRETTY_DEBUG_DIR:-}/.verbose_stream_${__CT_TEST_NAME:-}"
}


# _ct_pretty_debug_file
# --------------------
# Prints everything that was previously stored into the pretty debug log.
# Internal function, should not be called outside of this script.
function _ct_pretty_debug_file() {
  echo "${__CT_PRETTY_DEBUG_DIR:-}/.pretty_debug"
}

# _ct_write_journal [message]
# --------------------
# All arguments are written to the journal log that is should keep the steps for reproducing.
# Doing nothing if the file does not exist (i.e. Pretty debug not used)
function _ct_write_journal() {
  # shellcheck disable=SC2015
  [ -f "$(_ct_journal_file)" ] && echo "${_CT_VERBOSE_INDENT:-}$*" >>"$(_ct_journal_file)" || :
}

# _ct_write_verbose_stream [message]
# --------------------
# All arguments are written to the verbose log that is printed in case of failure.
# If _CT_VERBOSE_PREFIX variable is set, it is used instead of default '  # '.
# Doing nothing if the file does not exist (i.e. Pretty debug not used)
function _ct_write_verbose_stream() {
  # shellcheck disable=SC2015
  [ -f "$(_ct_verbose_file)" ] && echo "${_CT_VERBOSE_PREFIX:-${_CT_VERBOSE_INDENT:-}# }$*" >>"$(_ct_verbose_file)" || :
}

# vim: set tabstop=2:shiftwidth=2:expandtab:
