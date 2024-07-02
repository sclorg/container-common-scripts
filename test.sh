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
    VERSION=$dir test/run
    failed_version "$?" "$dir"
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
