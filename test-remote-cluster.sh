#!/bin/bash

# This script is used to test container images integrated in the OpenShift.
#
# VERSIONS - Must be set to a list with possible versions (subdirectories)
#
# This script expects oc command to exist and logged in to a working cluster.

set -e

export OS=${OS:-rhel7}

if [ "${OS}" == "rhel7" ] ; then
  NAMESPACE=${NAMESPACE:-rhscl/}
  REGISTRY=${REGISTRY:-registry.access.redhat.com/}
else
  NAMESPACE=${NAMESPACE:-centos/}
fi

export NAMESPACE
export REGISTRY

for dir in ${VERSIONS}; do
  [ ! -e "${dir}/.image-id" ] && echo "-> Image for version $dir not built, skipping OpenShift 4 tests." && continue
  pushd "${dir}" > /dev/null

  export IMAGE_NAME="${NAMESPACE}${BASE_IMAGE_NAME}-${dir//./}-${OS}"

  if [[ -x test/run-openshift-remote-cluster ]]; then
    VERSION="${dir}" test/run-openshift-remote-cluster
  else
    echo "-> Tests for OpenShift 4 are not present. Add run-openshift-remote-cluster script, skipping"
  fi

  popd > /dev/null
done

# vim: set tabstop=2:shiftwidth=2:expandtab:
