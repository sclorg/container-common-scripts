#!/bin/bash -e
# This script is used to test the OpenShift Docker images.
#
# TEST_MODE - If set, run regular test suite
# TEST_OPENSHIFT_MODE - If set, run OpenShift tests (if present)
# VERSIONS - Must be set to a list with possible versions (subdirectories)

for dir in ${VERSIONS}; do
  [ ! -e "${dir}/.image-id" ] && echo "-> Image for version $dir not built, skipping tests." && continue
  pushd ${dir} > /dev/null
  export IMAGE_ID=$(cat .image-id)
  # Kept also IMAGE_NAME as some tests might still use that.
  export IMAGE_NAME=$(docker inspect -f "{{.Config.Labels.name}}" $IMAGE_ID)

  if [ -n "${TEST_MODE}" ]; then
    VERSION=$dir test/run
  fi

  if [ -n "${TEST_OPENSHIFT_MODE}" ]; then
    if [[ -x test/run-openshift ]]; then
      VERSION=$dir test/run-openshift
    else
      echo "-> OpenShift tests are not present, skipping"
    fi
  fi

  popd > /dev/null
done
