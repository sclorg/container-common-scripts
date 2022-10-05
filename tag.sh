#!/bin/bash

# This script is used to tag the OpenShift Docker images.
#
# Resulting image will be tagged: 'name:version' and 'name:latest'. Name and version
#                                  are values of labels from resulted image
#
# VERSIONS - Must be set to a list with possible versions (subdirectories)

set -e
[ -n "${DEBUG:-}" ] && set -x

for dir in ${VERSIONS}; do
  [ ! -e "${dir}/.image-id" ] && echo "-> Image for version $dir not built, skipping tag." && continue
  pushd "${dir}" > /dev/null
  IMAGE_ID=$(cat .image-id)
  name=$(docker inspect -f "{{.Config.Labels.name}}" "$IMAGE_ID")
  version=$(docker inspect -f "{{.Config.Labels.version}}" "$IMAGE_ID")
  commit_date=$(git show -s HEAD --format=%cd --date=short | sed 's/-//g')
  date_and_hash="${commit_date}-$(git rev-parse --short HEAD)"

  full_reg_name="$REGISTRY$name"
  echo "-> Tagging image '$IMAGE_ID' as '$full_reg_name:$version' and '$full_reg_name:latest' and '$full_reg_name:$OS' and '$full_reg_name:$date_and_hash'"

  docker tag "$IMAGE_ID" "$full_reg_name:$OS"
  docker tag "$IMAGE_ID" "$full_reg_name:$version"
  docker tag "$IMAGE_ID" "$full_reg_name:latest"
  docker tag "$IMAGE_ID" "$full_reg_name:$date_and_hash"

  popd > /dev/null
done
