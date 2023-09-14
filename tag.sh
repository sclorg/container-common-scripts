#!/bin/bash

# This script is used to tag the OpenShift Docker images.
#
# Resulting image will be tagged: 'name:version' and 'name:latest'. Name and version
#                                  are values of labels from resulted image
#
# VERSIONS - Must be set to a list with possible versions (subdirectories)

set -eE

trap 'echo "errexit on line $LINENO, $0" >&2' ERR

[ -n "${DEBUG:-}" ] && set -x
# This adds backwards compatibility if only single version needs to be tagged
# In CI we would like to test single version but VERSIONS= means, that nothing is tested
# make tag TARGET=<OS> VERSIONS=<something> ... checks single version for CLI
# make tag TARGET=<OS> SINGLE_VERSION=<something> ... checks single version from Testing Farm
VERSIONS=${SINGLE_VERSION:-$VERSIONS}
if [[ "${SINGLE_VERSION}" == *"minimal"* ]]; then
  echo "Adding ${SINGLE_VERSION//-minimal/} because it might be needed for testing $SINGLE_VERSION."
  VERSIONS="$VERSIONS ${SINGLE_VERSION//-minimal/}"
fi
if [[ "${SINGLE_VERSION}" == *"micro"* ]]; then
  echo "Adding ${SINGLE_VERSION//-micro/} because it might be needed for testing $SINGLE_VERSION."
  VERSIONS="$VERSIONS ${SINGLE_VERSION//-micro/}"
fi
echo "Tagged versions are: $VERSIONS"

for dir in ${VERSIONS}; do
  [ ! -e "${dir}/.image-id" ] && echo "-> Image for version $dir not built, skipping tag." && continue
  pushd "${dir}" > /dev/null
  IMAGE_ID=$(cat .image-id)
  name=$(docker inspect -f "{{.Config.Labels.name}}" "$IMAGE_ID")
  version=$(docker inspect -f "{{.Config.Labels.version}}" "$IMAGE_ID")
  # We need to check '.git' dir in root directory
  if [ -d "../.git" ] ; then
    commit_date=$(git show -s HEAD --format=%cd --date=short | sed 's/-//g')
    date_and_hash="${commit_date}-$(git rev-parse --short HEAD)"
  else
    date_and_hash="$(date +%Y%m%d%H%M%S)"
  fi

  full_reg_name="$REGISTRY$name"
  echo "-> Tagging image '$IMAGE_ID' as '$full_reg_name:$version' and '$full_reg_name:latest' and '$full_reg_name:$OS' and '$full_reg_name:$date_and_hash'"

  docker tag "$IMAGE_ID" "$full_reg_name:$OS"
  docker tag "$IMAGE_ID" "$full_reg_name:$version"
  docker tag "$IMAGE_ID" "$full_reg_name:latest"
  docker tag "$IMAGE_ID" "$full_reg_name:$date_and_hash"

  popd > /dev/null
done
