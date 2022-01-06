#!/bin/bash

# This script is used to test the OpenShift Docker images.
#
# TEST_MODE - If set, run regular test suite
# TEST_OPENSHIFT_MODE - If set, run OpenShift tests (if present)
# VERSIONS - Must be set to a list with possible versions (subdirectories)

set -e

for dir in ${VERSIONS}; do
  [ ! -e "${dir}/.image-id" ] && echo "-> Image for version $dir not built, skipping tests." && continue
  pushd "${dir}" > /dev/null
  IMAGE_ID=$(cat .image-id)
  export IMAGE_ID
  IMAGE_VERSION=$(docker inspect -f "{{.Config.Labels.version}}" "$IMAGE_ID")
  # Kept also IMAGE_NAME as some tests might still use that.
  IMAGE_NAME="$(docker inspect -f "{{.Config.Labels.name}}" "$IMAGE_ID"):$IMAGE_VERSION"
    # shellcheck disable=SC2268
  if [ "${OS}" == "centos7" ] || [ "${OS}" == "c9s" ]; then
    export IMAGE_NAME="$REGISTRY$IMAGE_NAME"
  else
    export IMAGE_NAME
  fi

  if [ -n "${TEST_MODE}" ]; then
    VERSION=$dir test/run
  fi

  if [ -n "${TEST_OPENSHIFT_4}" ]; then
    # In case only imagestream is deprecated
    # and the other tests should be working
    if [ -e ".exclude-openshift" ]; then
      echo "-> .exclude-openshift file exists for version $dir, skipping OpenShift-4 tests."
    else
      if [[ -x test/run-openshift-remote-cluster ]]; then
        VERSION=$dir test/run-openshift-remote-cluster
      else
        echo "-> Tests for OpenShift 4 are not present. Add run-openshift-remote-cluster script, skipping"
      fi
    fi

  fi

  if [ -n "${TEST_OPENSHIFT_MODE}" ]; then
    # In case only imagestream is deprecated
    # and the other tests should be working
    if [ -e ".exclude-openshift" ]; then
      echo "-> .exclude-openshift file exists for version $dir, skipping OpenShift tests."
    else
      if [[ -x test/run-openshift ]]; then
        VERSION=$dir test/run-openshift
      else
        echo "-> OpenShift 3 tests are not present, skipping"
      fi
    fi
  fi

  popd > /dev/null
done
