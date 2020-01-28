#!/bin/bash

# This script is used to tag the OpenShift Docker images.
#
# Resulting image will be tagged: 'name:version' and 'name:latest'. Name and version
#                                  are values of labels from resulted image
#
# VERSIONS - Must be set to a list with possible versions (subdirectories)

set -e

for dir in ${VERSIONS}; do
  [ ! -e "${dir}/.image-id" ] && echo "-> Image for version $dir not built, skipping tag." && continue
  pushd "${dir}" > /dev/null
  IMAGE_ID=$(cat .image-id)
  name=$(docker inspect -f "{{.Config.Labels.name}}" "$IMAGE_ID")
  version=$(docker inspect -f "{{.Config.Labels.version}}" "$IMAGE_ID")
  commit_date=$(git show -s HEAD --format=%cd --date=short | sed 's/-//g')
  date_and_hash="${commit_date}-$(git rev-parse --short HEAD)"

  echo "-> Tagging image '$IMAGE_ID' as '$name:$version' and '$name:latest' and '$name:$date_and_hash'"
  docker tag "$IMAGE_ID" "$name:$version"
  docker tag "$IMAGE_ID" "$name:latest"
  docker tag "$IMAGE_ID" "$name:$date_and_hash"

  for suffix in squashed raw; do
    id_file=.image-id.$suffix
    if test -f "$id_file"; then
        docker tag "$(cat "$id_file")" "$name:$suffix" || rm .image-id."$suffix"
    fi
  done

  popd > /dev/null
done
