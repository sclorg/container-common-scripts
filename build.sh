#!/bin/bash -e
# This script is used to build, test and squash the OpenShift Docker images.
#
# Resulting image will be tagged: 'name:version' and 'name:latest'. Name and version
#                                  are values of labels from resulted image
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

BASE_DIR_NAME=$(echo $(basename `pwd`) | sed -e 's/-[0-9]*$//g')

# Perform docker build but append the LABEL with GIT commit id at the end
function docker_build_with_version {
  local dockerfile="$1"
  echo "-> Version ${dir}: building image from '${dockerfile}' ..."

  git_version=$(git rev-parse --short HEAD)
  BUILD_OPTIONS+=" --label io.openshift.builder-version=\"${git_version}\""
  if [[ "${UPDATE_BASE}" == "1" ]]; then
    BUILD_OPTIONS+=" --pull=true"
  fi

  IMAGE_NAME="$BASE_DIR_NAME-$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1
):${git_version}"
  docker build ${BUILD_OPTIONS} -t ${IMAGE_NAME} -f "${dockerfile}" .

  if [[ "${SKIP_SQUASH}" != "1" ]]; then
    squash "${dockerfile}"
  fi
}

# Install the docker squashing tool[1] and squash the result image
# [1] https://github.com/goldmann/docker-squash
function squash {
  # FIXME: We have to use the exact versions here to avoid Docker client
  #        compatibility issues
  easy_install -q --user docker_py==1.7.2 docker-squash==1.0.1
  base=$(awk '/^FROM/{print $2}' $1)
  ${HOME}/.local/bin/docker-squash -f $base ${IMAGE_NAME}
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

  ok_to_tag=1
  if [[ -v TEST_MODE ]]; then
    VERSION=$dir IMAGE_NAME=${IMAGE_NAME} test/run
    if [[ $? -ne 0 ]] || [[ "${TAG_ON_SUCCESS}" != "true" ]]; then
      ok_to_tag=0
    fi
  fi

  if [[ -v TEST_OPENSHIFT_MODE ]]; then
    if [[ -x test/run-openshift ]]; then
      VERSION=$dir IMAGE_NAME=${IMAGE_NAME} test/run-openshift
    else
      echo "-> OpenShift tests are not present, skipping"
    fi
  fi

  if [[ $ok_to_tag -eq 1 ]]; then
    name=$(docker inspect -f "{{.Config.Labels.name}}" $IMAGE_NAME)
    version=$(docker inspect -f "{{.Config.Labels.version}}" $IMAGE_NAME)

    echo "-> Tagging image to '$name:$version' and '$name:latest'"
    docker tag $IMAGE_NAME "$name:$version"
    docker tag $IMAGE_NAME "$name:latest"
  fi

  docker rmi $IMAGE_NAME

  popd > /dev/null
done
