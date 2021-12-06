#! /bin/bash

declare -A IMAGES

for image in ${TESTED_IMAGES}; do
    IMAGES[$image]=master
done

test -n "${OS-}" || false 'make sure $OS is defined'

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
        || die "Please rebase the commit '$(git rev-parse --short HEAD)'" \
               "to allow --ff merge into '$MERGE_INTO' branch"

    while read line; do
        case $line in
            Required-by:\ *)
                set -- $line
                old_IFS=$IFS
                IFS=\#
                set -- $2
                IFS=$old_IFS
                set -- $1 $2
                info "PR commits ask for testing $1 from PR $2"
                IMAGES[$1]=$2
                ;;
        esac
    done < <(git log --format=%B --reverse "$MERGE_INTO"..HEAD)
}

analyse_commits

test_short_summary=""
TESTSUITE_RESULT=0

for image in "${!IMAGES[@]}"; do
    # We don't want to remove user's WIP stuff.
    test -e "$image" && die "directory '$image' exists"

    (   testdir=$PWD
        cleanup () {
            set -x
            # Ensure the cleanup finishes!
            trap '' INT
            # Go back, wherever we are.
            cd "$testdir"
            # Try to cleanup, if available (and if needed).
            make clean -C "$image" || :
            # Drop the image sources.
            test ! -d "$image" || rm -rf "$image"
        }
        trap cleanup EXIT

        info "Testing $image image"

        # Use --recursive even if we remove 'common', because there might be
        # other git submodules which need to be tested.
        git clone --recursive -q https://github.com/sclorg/"$image".git
        cd "$image"

        revision=${IMAGES[$image]}
        if ! test "$revision" = master; then
            info "Fetching $image PR $revision"
            git fetch origin "pull/$revision/head":PR_BRANCH
            git checkout PR_BRANCH
            git submodule update
        fi

        # We fail if the 'common' directory doesn't exist.
        test -d common
        rm -rf common
        info "Replacing common with PR's version"
        ln -s ../ common

        # TODO: Do we have to test all $(VERSION)s?
        # TODO: The PS4 hack doesn't work if we run the testsuite as UID=0.
        PS4="+ [$image] " make TARGET="$OS" test
        test_ret_value=$?
        # Cleanup.
        make clean

        if test $test_ret_value -eq 0 ; then
          info "Tests for $image succeeded."
          exit 0
        else
          info "Tests for $image failed."
          exit 1
        fi
    )
    if test $? -eq 0 ; then
      printf -v test_short_summary "${test_short_summary}[PASSED] $image\n"
    else
      printf -v test_short_summary "${test_short_summary}[FAILED] $image\n"
      TESTSUITE_RESULT=1
    fi
done

echo "$test_short_summary"
if [ $TESTSUITE_RESULT -eq 0 ] ; then
  echo "Tests for 'container-common-scripts' succeeded."
else
  echo "Tests for 'container-common-scripts' failed."
fi

exit $TESTSUITE_RESULT
