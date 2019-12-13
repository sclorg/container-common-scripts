#! /bin/sh

set -e
test -f auto_targets.mk && rm auto_targets.mk

for version
do
    remove_images=
    for idfile in .image-id.raw .image-id.squashed; do
        # shellcheck disable=SC2039
        test ! -f "$version/$idfile" || remove_images+=" $(cat "$version/$idfile")"
    done

    for image in $remove_images; do
        # shellcheck disable=SC2046
        docker rm -f $(docker ps -q -a -f "ancestor=$image") 2>/dev/null || :
        docker rmi -f "$image" || :
    done

    rm -rf "$version"/.image-id*
done
