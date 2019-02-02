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
  pushd ${dir} > /dev/null

  export IMAGE_NAME="${REGISTRY}${NAMESPACE}${BASE_IMAGE_NAME}-${dir//./}-${OS}"

  VERSION=$dir test/run-openshift-remote-cluster

  popd > /dev/null
done

# vim: set tabstop=2:shiftwidth=2:expandtab:
