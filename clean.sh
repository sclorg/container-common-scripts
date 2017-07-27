#! /bin/sh

set -e
for version
do
    remove_images=
    for idfile in .image-id.raw .image-id.squashed; do
        test ! -f "$version/$idfile" || remove_images+=" $(cat "$version/$idfile")"
    done

    for image in $remove_images; do
        docker rm -f $(docker ps -q -a -f "ancestor=$image") 2>/dev/null || :
        docker rmi -f "$image" || :
    done

    rm -rf "$version"/.image-id*
done
