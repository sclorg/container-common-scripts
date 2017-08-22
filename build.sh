#!/bin/bash -e
# This script is used to build the OpenShift Docker images.
#
# OS - Specifies distribution - "rhel7", "centos7" or "fedora"
# VERSION - Specifies the image version - (must match with subdirectory in repo)
# TEST_MODE - If set, build a candidate image and test it
# TAG_ON_SUCCESS - If set, tested image will be re-tagged as a non-candidate
#       image, if the tests pass.
# VERSIONS - Must be set to a list with possible versions (subdirectories)

OS=${1-$OS}
VERSION=${2-$VERSION}

DOCKERFILE_PATH=""

error() { echo "ERROR: $*" ; false ; }

# parse_output COMMAND FILTER_COMMAND OUTVAR [STREAM={stderr|stdout}]
# -------------------------------------------------------------------
# Parse standard (error) output of COMMAND with FILTER_COMMAND and store the
# output into variable named OUTVAR.  STREAM might be 'stdout' or 'stderr',
# defaults to 'stdout'.  The filtered output stays (live) printed to terminal.
# This method doesn't create any explicit temporary files.
# Defines:
#   ${$OUTVAR}: Set to FILTER_COMMAND output.
parse_output ()
{
  local command=$1 filter=$2 var=$3 stream=$4
  local raw_output= rc=0
  {
      raw_output=$(
        set -o pipefail
        {
            case $stream in
            stdout|1|"")
                eval "$command" | tee >(cat - >&$stdout_fd)
                 ;;
            stderr|2)
                set +x # avoid stderr pollution
                eval "$command" {free_fd}>&1 1>&$stdout_fd 2>&$free_fd | tee >(cat - >&$stderr_fd)
                ;;
            esac
            # Inherit correct exit status.
            (exit ${PIPESTATUS[0]})
        } | eval "$filter"
      )
  } {stdout_fd}>&1 {stderr_fd}>&2
  rc=$?
  eval "$var=\$raw_output"
  (exit $rc)
}

# Perform docker build but append the LABEL with GIT commit id at the end
function docker_build_with_version {
  local dockerfile="$1"
  local exclude=.exclude-${OS}
  [ -e $exclude ] && echo "-> $exclude file exists for version $dir, skipping build." && return
  [ ! -e "$dockerfile" ] && echo "-> $dockerfile for version $dir does not exist, skipping build." && return
  echo "-> Version ${dir}: building image from '${dockerfile}' ..."

  git_version=$(git rev-parse --short HEAD)
  BUILD_OPTIONS+=" --label io.openshift.builder-version=\"${git_version}\""
  if [[ "${UPDATE_BASE}" == "1" ]]; then
    BUILD_OPTIONS+=" --pull=true"
  fi

  parse_output 'docker build $BUILD_OPTIONS -f "$dockerfile" .' \
               "awk '/Successfully built/{print \$NF}'" \
               IMAGE_ID

  name=$(docker inspect -f "{{.Config.Labels.name}}" $IMAGE_ID)

  IMAGE_NAME=$name
  if [ -n "${TEST_MODE}" ]; then
    IMAGE_NAME+="-candidate"
  fi
  echo "-> Image ${IMAGE_ID} tagged as ${IMAGE_NAME}"
  docker tag $IMAGE_ID $IMAGE_NAME

  if [[ "${SKIP_SQUASH}" != "1" ]]; then
    docker tag $IMAGE_ID "${IMAGE_NAME}-unsquashed"
    squash "${dockerfile}"
  fi
  # Narrow by repo:tag first and then grep out the exact match
  docker images "${IMAGE_NAME}:latest" --format="{{.Repository}} {{.ID}}" | grep "^${IMAGE_NAME}" | awk '{print $2}' >.image-id
}

# Install the docker squashing tool[1] and squash the result image
# [1] https://github.com/goldmann/docker-squash
function squash {
  # FIXME: We have to use the exact versions here to avoid Docker client
  #        compatibility issues
  local squash_version=1.0.5
  test "$(docker-squash --version 2>&1)" = "$squash_version" || \
      error "docker-squash $squash_version required"
  base=$(awk '/^FROM/{print $2}' $1)
  docker-squash -f $base ${IMAGE_NAME} -t ${IMAGE_NAME}
}

# Versions are stored in subdirectories. You can specify VERSION variable
# to build just one single version. By default we build all versions
dirs=${VERSION:-$VERSIONS}

for dir in ${dirs}; do
  pushd ${dir} > /dev/null
  if [ "$OS" == "rhel7" -o "$OS" == "rhel7-candidate" ]; then
    docker_build_with_version Dockerfile.rhel7
  elif [ "$OS" == "fedora" -o "$OS" == "fedora-candidate" ]; then
    docker_build_with_version Dockerfile.fedora
  else
    docker_build_with_version Dockerfile
  fi

  popd > /dev/null
done
