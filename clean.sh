#! /bin/sh

test -f auto_targets.mk && rm auto_targets.mk

for version
do
    remove_images=
    # shellcheck disable=SC2039,SC3024
    test ! -f "$version/.image-id" || remove_images+=" $(cat "$version/.image-id")"
    for image in $remove_images; do
        # shellcheck disable=SC2046
        docker rm -f $(docker ps -q -a -f "ancestor=$image") 2>/dev/null
        docker rmi -f "$image"
    done

    rm -rf "$version"/.image-id*
done
