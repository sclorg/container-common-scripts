#! /bin/sh

[ -n "${DEBUG:-}" ] && set -x

test -f auto_targets.mk && rm auto_targets.mk

for version; do
  for id_file in .image-id .image-id-from; do
    if [ -f "$version"/"$id_file" ]; then
      image="$(cat "$version"/"$id_file")"
      test -n "$image" || continue
      containers="$(docker ps -q -a -f ancestor="$image")"
      docker rm -f "$containers" 2>/dev/null
      docker rmi -f "$image"
      rm -f "$version"/"$id_file"
    fi
  done
done
