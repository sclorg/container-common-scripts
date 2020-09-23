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
  export IMAGE_NAME

  if [ -n "${TEST_MODE}" ]; then
    VERSION=$dir test/run
  fi

  if [ -n "${TEST_CONU_MODE}" ]; then
    if [[ -x test/run-conu ]]; then
      if [ -n "${CONU_IMAGE}" ]; then
        echo "-> Running conu tests in a container"
        docker run \
          --net=host \
          -e VERSION="${dir}" \
          -e IMAGE_NAME \
          --rm \
          --security-opt label=disable \
          -ti \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v "${PWD}"/../:/src \
          -w "/src/${dir}/" \
          -ti \
          "${CONU_IMAGE}" \
          ./test/run-conu
      else
        VERSION="${dir}" ./test/run-conu
      fi
    else
      echo "-> conu tests are not present, skipping"
    fi
  fi

  if [ -n "${TEST_OPENSHIFT_4}" ]; then
    if [[ -x test/run-openshift-remote-cluster ]]; then
        VERSION=$dir test/run-openshift-remote-cluster
    else
      echo "-> Tests for OpenShift 4 are not present. Add run-openshift-remote-cluster script, skipping"
    fi
  fi

  if [ -n "${TEST_OPENSHIFT_MODE}" ]; then
    if [[ -x test/run-openshift ]]; then
      VERSION=$dir test/run-openshift
    else
      echo "-> OpenShift 3 tests are not present, skipping"
    fi
  fi

  popd > /dev/null
done
