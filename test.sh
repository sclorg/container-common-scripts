#!/bin/bash

# This script is used to test the OpenShift Docker images.
#
# TEST_MODE - If set, run regular test suite
# TEST_OPENSHIFT_MODE - If set, run OpenShift tests (if present)
# VERSIONS - Must be set to a list with possible versions (subdirectories)

[ -n "${DEBUG:-}" ] && set -x

FAILED_VERSIONS=""

# failed_version
# -----------------------------
# Check if testcase ended in error and update FAILED_VERSIONS variable
# Argument: result - testcase result value
#           version - version that failed
failed_version() {
  local result="$1"
  local version="$2"
  if [[ "$result" != "0" ]]; then
    FAILED_VERSIONS="${FAILED_VERSIONS} ${version}"
  fi
  return "$result"
}

analyze_logs_by_logdetective() {
  local log_file_name="$1"
  echo "Sending failed log by fpaste command to paste bin."
  paste_bin_link=$(fpaste "$log_file_name")
  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to send log file to private bin: ${log_file_name}"
    return
  fi
  # pastebin link is "https://paste.centos.org/view/ee98ba05"
  # We need a raw link that is "https://paste.centos.org/view/raw/ee98ba05"
  raw_paste_bin_link="${paste_bin_link//view/view\/raw}"
  echo "Sending log file to logdetective server: ${raw_paste_bin_link}"
  echo "-------- LOGDETECTIVE TEST LOG ANALYSIS START --------"
  # shellcheck disable=SC2181
  if ! curl -k --insecure --header "Content-Type: application/json" --request POST --data "{\"url\":\"${raw_paste_bin_link}\"}" "$LOGDETECTIVE_SERVER/analyze" > /tmp/logdetective_test_output.txt; then
    echo "ERROR: Failed to analyze log file by logdetective server."
    cat "/tmp/logdetective_test_output.txt"
    echo "-------- LOGDETECTIVE TEST LOG ANALYSIS FAILED --------"
    return
  fi
  jq -rC '.explanation.text' < "/tmp/logdetective_test_output.txt"
  echo "-------- LOGDETECTIVE TEST LOG ANALYSIS FINISHED --------"
}

# This adds backwards compatibility if only single version needs to be testing
# In CI we would like to test single version but VERSIONS= means, that nothing is tested
# make test TARGET=<OS> VERSIONS=<something> ... checks single version for CLI
# make test TARGET=<OS> SINGLE_VERSION=<something> ... checks single version from Testing Farm
VERSIONS=${SINGLE_VERSION:-$VERSIONS}
echo "Tested versions are: $VERSIONS"

for dir in ${VERSIONS}; do
  [ ! -e "${dir}/.image-id" ] && echo "-> Image for version $dir not built, skipping tests." && continue
  pushd "${dir}" > /dev/null || exit 1
  IMAGE_ID=$(cat .image-id)
  export IMAGE_ID
  IMAGE_VERSION=$(docker inspect -f "{{.Config.Labels.version}}" "$IMAGE_ID")
  # Kept also IMAGE_NAME as some tests might still use that.
  IMAGE_NAME="$(docker inspect -f "{{.Config.Labels.name}}" "$IMAGE_ID"):$IMAGE_VERSION"
    # shellcheck disable=SC2268
  if [ "${OS}" == "c9s" ] || [ "${OS}" == "c10s" ] || [ "${OS}" == "fedora" ]; then
    export IMAGE_NAME="$REGISTRY$IMAGE_NAME"
  else
    export IMAGE_NAME
  fi

  if [ -n "${TEST_MODE}" ]; then
    tmp_file=$(mktemp "/tmp/${IMAGE_NAME}-${OS}-${dir}.XXXXXX")
    VERSION=$dir test/run 2>&1 | tee "$tmp_file"
    ret_code=$?
    analyze_logs_by_logdetective "$tmp_file"
    failed_version "$ret_code" "$dir"
    rm -f "$tmp_file"
  fi

  if [ -n "${TEST_OPENSHIFT_4}" ]; then
    # In case only imagestream is deprecated
    # and the other tests should be working
    if [ -e ".exclude-openshift" ]; then
      echo "-> .exclude-openshift file exists for version $dir, skipping OpenShift-4 tests."
    else
      if [ -x test/run-openshift-remote-cluster ]; then
        VERSION=$dir test/run-openshift-remote-cluster
        failed_version "$?" "$dir"
      else
        echo "-> Tests for OpenShift 4 are not present. Add run-openshift-remote-cluster script, skipping"
      fi
    fi

  fi

  if [ -n "${TEST_UPSTREAM}" ]; then
    if [ -x test/run-upstream ]; then
      VERSION=$dir test/run-upstream
      failed_version "$?" "$dir"
    else
      echo "-> Upstream tests are not present, skipping"
    fi
  fi

  if [ -n "${TEST_OPENSHIFT_PYTEST}" ]; then
    if [ -x test/run-openshift-pytest ]; then
      VERSION=$dir test/run-openshift-pytest
      failed_version "$?" "$dir"
    else
      echo "-> PyTest tests are not present, skipping"
    fi
  fi

  popd > /dev/null || exit 1
done

if [[ -n "$FAILED_VERSIONS" ]]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Test for image ${IMAGE_NAME} FAILED in these versions ${FAILED_VERSIONS}."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi
