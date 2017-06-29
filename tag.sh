#!/bin/bash -e
# This script is used to tag the OpenShift Docker images.
#
# Resulting image will be tagged: 'name:version' and 'name:latest'. Name and version
#                                  are values of labels from resulted image
#
# TEST_MODE - If set, the script will look for *-candidate images to tag
# VERSIONS - Must be set to a list with possible versions (subdirectories)

for dir in ${VERSIONS}; do
  pushd ${dir} > /dev/null
  IMAGE_ID=$(cat .image-id)
  name=$(docker inspect -f "{{.Config.Labels.name}}" $IMAGE_ID)
  version=$(docker inspect -f "{{.Config.Labels.version}}" $IMAGE_ID)
  IMAGE_NAME=$name
  if [[ -v TEST_MODE ]]; then
    IMAGE_NAME+="-candidate"
  fi
  echo "-> Tagging image '$IMAGE_NAME' as '$name:$version' and '$name:latest'"
  docker tag $IMAGE_NAME "$name:$version"
  docker tag $IMAGE_NAME "$name:latest"

  rm .image-id
  popd > /dev/null
done
