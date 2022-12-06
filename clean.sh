#! /bin/sh

[ -n "${DEBUG:-}" ] && set -x

test -f auto_targets.mk && rm auto_targets.mk

for version; do
  for id_file in .image-id .image-id-from; do
    id_path="$version"/"$id_file"
    if [ -f "$id_path" ]; then
      image="$(cat "$id_path")"
      test -n "$image" || continue
      docker inspect "$image" > /dev/null 2>&1 || continue
      containers="$(docker ps -q -a -f ancestor="$image")"
      if [ -n "$containers" ]; then
        docker stop "$containers"
        docker rm -f "$containers"
      fi
      docker rmi -f "$image"
      rm -f "$id_path"
    fi
  done
done
