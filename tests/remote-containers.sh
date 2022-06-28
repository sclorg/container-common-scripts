#! /bin/bash

IMAGE_REVISION=master

test -n "${OS-}" || false 'make sure $OS is defined'
test -n "${TESTED_IMAGE-}" || false 'make sure $TESTED_IMAGE is defined'
test -n "${TESTED_SCENARIO-}" || false 'make sure $TESTED_SCENARIO is defined'

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
                IMAGE_REVISION=$2
                ;;
        esac
    done < <(git log --format=%B --reverse "$MERGE_INTO"..HEAD)
}

analyse_commits

test_short_summary=""
TESTSUITE_RESULT=0

# We don't want to remove user's WIP stuff.
test -e "$TESTED_IMAGE" && die "directory '$TESTED_IMAGE' exists"

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

    info "Testing $TESTED_IMAGE image"

    # Use --recursive even if we remove 'common', because there might be
    # other git submodules which need to be tested.
    git clone --recursive -q https://github.com/sclorg/"$TESTED_IMAGE".git
    cd "$TESTED_IMAGE"

    if ! test "${IMAGE_REVISION}" = master; then
        info "Fetching $image PR ${IMAGE_REVISION}"
        git fetch origin "pull/${IMAGE_REVISION}/head":PR_BRANCH
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
    PS4="+ [$TESTED_IMAGE] " make TARGET="$OS" $TESTED_SCENARIO
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
  printf -v test_short_summary "${test_short_summary}[PASSED] $TESTED_IMAGE\n"
else
  printf -v test_short_summary "${test_short_summary}[FAILED] $TESTED_IMAGE\n"
  TESTSUITE_RESULT=1
fi

echo "$test_short_summary"
if [ $TESTSUITE_RESULT -eq 0 ] ; then
  echo "Tests for 'container-common-scripts' succeeded."
else
  echo "Tests for 'container-common-scripts' failed."
fi

exit $TESTSUITE_RESULT
