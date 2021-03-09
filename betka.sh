#!/bin/bash

# This script is used to build images for dist-git repositories.
#
# The result directory will contain generated sources from upstream directories
#

set -ex

CUR_DIR=$(pwd)
TMP_DIR=$(mktemp -d)
UPSTREAM_IMAGE_NAME=$(basename "$CUR_DIR")

echo "Temporary dir is ${TMP_DIR}."
echo "Upstream image name is: $UPSTREAM_IMAGE_NAME."

function create_temp_dir() {
  CURDIR_RESULTS="${CUR_DIR}/results-${dir}"
  if [[ -d "${CURDIR_RESULTS}" ]]; then
    echo "results directory already exist. Delete it."
    rm -rf "${CURDIR_RESULTS}"
  fi
}

function check_os() {
  if [[ x"${OS}" == "xcentos7" ]]; then
    echo "Target has to be specified."
    echo "CentOS7 is not supported."
    echo "e.g. make betka TARGET=fedora VERSIONS=XY"
    exit 1
  fi
}

function load_configuration() {
  if [[ x"${OS}" == "xfedora" ]]; then
    curl -L https://raw.githubusercontent.com/sclorg/container-workflow-tool/master/cwt_generator.config > cwt_config
  else
    curl -L https://url.corp.redhat.com/rhcwt_config > cwt_config
  fi
  # shellcheck disable=SC1091
  source cwt_config
}

function check_os_and_parameters() {
  if [[ x"${OS}" == "xfedora" ]]; then
    echo "For generating dist-git sources to Fedora ${CWT_DOCKER_IMAGE} is used."
    echo "'make betka' will try to sync main branch in Fedora land."
    echo "If you want to change it then specify it by parameter DOWNSTREAM_BRANCH, like"
    echo "'make betka TARGET=fedora DOWNSTREAM_BRANCH=f32'"
  else
    if [[ x"${CWT_DOCKER_IMAGE}" == "x" ]]; then
      echo "Docker image for generating dist-git sources for RHEL has to be specified."
      echo "Ask pkubat@redhat.com, hhorak@redhat.com or phracek@redhat.com for the name."
      exit 1
    fi
  fi

  if [[ x"${dir}" == "x" ]]; then
    echo "VERSIONS has to be specified."
    echo "Like: make betka TARGET=rhel7 VERSIONS=12 for s2i-nodejs-container."
    exit 1
  fi

}

function convert_branch_to_cwt_tool() {
  local cwt_config
  if [ x"${OS}" == x"rhel7" ]; then
    # Example branch name rhscl-3.6-rhel-7 converted to rhscl360
    IFS='-' read -ra branch_list <<<"${DOWNSTREAM_BRANCH}"
    cwt_config="rhel7.yaml:${branch_list[0]}${branch_list[1]//.}0"
  else
    # Example branch name rhel-8.3.0 -> converted to rhel8.3
    IFS='-' read -ra branch_list <<<"${DOWNSTREAM_BRANCH}"
    IFS='.' read -ra release_list <<< "${branch_list[1]}"
    cwt_config="rhel8.yaml:${branch_list[0]}${release_list[0]}.${release_list[1]}"
  fi
  echo "${cwt_config}"
}

function switch_to_branch() {
  echo "Cloning downstream repo '${CLONE_URL}/${DOWNSTREAM_NAME} to ${RESULTS_DIR}."
  git clone "${CLONE_URL}/${DOWNSTREAM_NAME}" "${RESULTS_DIR}"
  pushd "${RESULTS_DIR}" >/dev/null
  git checkout "${DOWNSTREAM_BRANCH}"
  popd >/dev/null
}

function pull_cwt_image() {
  if ! docker images "${CWT_DOCKER_IMAGE}" &>/dev/null; then
    echo "Docker image ${CWT_DOCKER_IMAGE} does not exist on the system. Let's pull it."
    docker pull "${CWT_DOCKER_IMAGE}"
  fi
}

function get_downstream_name_and_branch() {
  local cwt_output
  if [[ x"${OS}" == "xfedora" ]]; then
    command="cwt"
    if [[ x"${DOWNSTREAM_BRANCH}" == "x" ]]; then
      CWT_CONFIG="default".yaml
    fi
  else
    command="rhcwt"
    if [[ x"${DOWNSTREAM_BRANCH}" == "x" ]]; then
      echo "DOWNSTREAM_BRANCH is not specified."
      echo "Examples:"
      echo "rhel-8.3.0 for RHEL8"
      echo "rhscl-3.6-rhel7 for RHEL7"
      echo "For more details ask pkubat@redhat.com or phracek@redhat.com"
      exit 1
    fi
    CWT_CONFIG=$(convert_branch_to_cwt_tool "${DOWNSTREAM_BRANCH}")
  fi
  cwt_output="${command}_output"
  # Run CWT tool in order to get downstream name for specific version
  if ! docker run -it --rm "${CWT_DOCKER_IMAGE}" "${command}" \
    --config="${CWT_CONFIG}" utils listupstream >"${cwt_output}"; then
    echo "${command} tool does not get any information about upstream list. Something is wrong."
    echo "Please report it into https:///github.com/sclorg/container-worklow-tool"
    exit 1
  fi
  # Print for debugging proposes
  cat ${cwt_output}
  # shellcheck disable=SC2002
  output=$(cat ${cwt_output} | grep "${UPSTREAM_IMAGE_NAME}" | grep "${dir}")
  output=$(echo "$output" | tr -d "\n\r")
  if [[ x"${output}" == "x" ]]; then
    echo "For package ${UPSTREAM_IMAGE_NAME},branch ${DOWNSTREAM_BRANCH} and VERSIONS=${dir}"
    echo "${command} did not find proper version"
    echo "Specify correct VERSIONS and DOWNSTREAM_BRANCH respectivelly."
    return 1
  fi
  read -ra cwt_list <<<"${output}"
  DOWNSTREAM_NAME="${cwt_list[0]}"
  if [[ -n "${cwt_list[5]}" ]]; then
    DOWNSTREAM_BRANCH="${cwt_list[5]}"
  else
    echo "${command} tool does not return branch name."
    echo "Specify branch in command 'make betka TARGET=<OS> DOWNSTREAM_BRANCH=<something>"
    return 1
  fi
  echo "Downstream name is '${DOWNSTREAM_NAME}'"
}

function generate_sources() {
  # Copy upstream sources from current dir into temporary dir
  local mount_points
  rsync -azP "${CUR_DIR}" "${TMP_DIR}" >/dev/null

  if [[ ! -f "$HOME/.gitconfig" ]]; then
    echo "File $HOME/.gitconfig is mandatory for using CWT tool."
    echo "Create it by commands:"
    echo "git config --global user.mail <your mail>"
    echo "git config --global user.name <your name>"
    exit 1
  fi
  # Run CWT tool in order to convert upstream sources into downstream source

  mount_points="-v $HOME/.gitconfig:/root/.gitconfig:ro,Z -v ${TMP_DIR}:${TMP_DIR}:rw,Z"
  docker run -it --rm \
    "${mount_points}" \
    -e WORKDIR="${TMP_DIR}" \
    -e DOWNSTREAM_IMAGE_NAME="${DOWNSTREAM_NAME}" \
    -e UPSTREAM_IMAGE_NAME="${UPSTREAM_IMAGE_NAME}" \
    "${CWT_DOCKER_IMAGE}"

  echo "Copy results from temporary directory to results directory."
  rsync -azP "${RESULTS_DIR}" "${CUR_DIR}" >/dev/null
  mv "${CUR_DIR}/results" "${CUR_DIR}/results-${dir}"
}

for dir in ${VERSIONS}; do
  echo "Let's generate sources for version '${dir}'"
  RESULTS_DIR="${TMP_DIR}/results"
  # First of all create temporary directory
  create_temp_dir

  # Check if OS is supported. All except CentOS 7 are supported
  check_os

  load_configuration

  # Check if all parameters are filled
  check_os_and_parameters

  # Pull CWT image
  pull_cwt_image

  # Get downstream name
  if ! get_downstream_name_and_branch; then
    continue
  fi

  # Switch do proper downstream branch
  switch_to_branch

  # We are ready to generate downstream source
  generate_sources

  echo "To show changes in results directory do:"
  echo "cd ./results-${dir} && git status"
  rm -rf "${RESULTS_DIR}"
done
rm -rf "${TMP_DIR:?}/*"
