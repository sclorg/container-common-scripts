#!/bin/bash

# This script is used to build images for dist-git repositories.
#
# The result directory will contain generated sources from upstream directories
#

set -eE

trap 'echo "errexit on line $LINENO, $0" >&2' ERR

function load_configuration() {
  # shellcheck disable=SC2268
  if [[ x"$OS" == "xfedora" ]]; then
    HTTP_CODE=$(curl --output cwt_config --silent --write-out "%{http_code}" -L https://raw.githubusercontent.com/sclorg/container-workflow-tool/master/cwt_generator.config)
    if [[ ${HTTP_CODE} == 404 ]]; then
      exit 1
    fi
  else
    HTTP_CODE=$(curl --output cwt_config --silent --write-out "%{http_code}" -L https://url.corp.redhat.com/rhcwt-config)
    if [[ ${HTTP_CODE} == 404 ]]; then
      exit 1
    fi
  fi
  # shellcheck disable=SC1091
  source cwt_config
}

function pull_cwt_image() {
  if ! docker images "${CWT_DOCKER_IMAGE}" &>/dev/null; then
    echo "Docker image ${CWT_DOCKER_IMAGE} does not exist on the system. Let's pull it."
    docker pull "${CWT_DOCKER_IMAGE}"
  fi
}
TEST_DIR="$(dirname "${BASH_SOURCE[0]}")"

load_configuration
pull_cwt_image

python3 "${TEST_DIR}/betka.py"
