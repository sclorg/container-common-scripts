#! /bin/bash

declare -A IMAGES

for image in ${TESTED_IMAGES}; do
    IMAGES[$image]=master
done

OS=centos7

MERGE_INTO=origin/master

# This is the Fedora default, some users' boxes have more strict
# defaults (e.g. 0077).
umask 0022

die ()   { echo >&2 " # FATAL: $*"; exit 1; }
info ()  { echo     " * $*"; }
error () { echo >&2 " # ERROR: $*"; }

test -f common.mk -a -f build.sh -a -d .git \
    || die "Doesn't seem to be run from common's git directory"

analyse_commits ()
{
    # TODO: If we wanted to test "after PR merge", this needs to take some
    # argument specifying how long we should look in the commit history.
    git merge-base --is-ancestor "$MERGE_INTO" HEAD \
        || die "Can not be --ff merged into $MERGE_INTO"

    for commit in `git log --pretty=format:"%H" --reverse "$MERGE_INTO"..HEAD`
    do
        while read line; do
            case $line in
                Required-by:\ *)
                    set -- $line
                    old_IFS=$IFS
                    IFS=\#
                    set -- $2
                    IFS=$old_IFS
                    set -- $1 $2
                    info "Commit $commit sets $1 to PR $2"
                    IMAGES[$1]=$2
                    ;;
            esac
        done < <(git show "$commit" --no-patch --pretty="%B")
    done
}

analyse_commits

rc=true
for container in "${!IMAGES[@]}"; do
    if test -e "$container"; then
        rc=false
        error "directory '$container' exists"
        continue
    fi

    (   set -e
        cleanup () { rm -rf "$container"; }
        trap cleanup EXIT

        info "Testing $container container"
        # Use --recursive even if we remove 'common', because there might be
        # other git submodules which need to be tested.

        git clone --recursive -q https://github.com/sclorg/"$container".git
        cd "$container"

        revision=${IMAGES[$container]}
        if ! test "$revision" = master; then
            info "Fetching $container PR $revision"
            git fetch origin "pull/$revision/head":PR_BRANCH
            git checkout PR_BRANCH --recurse-submodules
        fi

        # We fail if the 'common' directory doesn't exist.
        test -d common
        rm -rf common
        ln -s ../ common

        # TODO: Do we have to test everything?
        PS4="+ [$container] " make TARGET="$OS" test
    )

    # Note that '( set -e ; false ) || blah' doesn't work as one expects.
    if test $? -ne 0; then
        rc=false
        error "Tests for $container failed"
    fi
done

$rc
