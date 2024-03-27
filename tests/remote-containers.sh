#! /bin/bash

IMAGE_REVISION=master
test_short_summary=""
TESTSUITE_RESULT=1

test -n "${OS-}" || (echo 'make sure $OS is defined' >&2 ; exit 1)
test -n "${TESTED_IMAGE-}" || (echo 'make sure $TESTED_IMAGE is defined' >&2 ; exit 1)
test -n "${TESTED_SCENARIO-}" || (echo 'make sure $TESTED_SCENARIO is defined' >&2 ; exit 1)

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

archive_common()
{
  local archive=$1
  tar czf $archive --exclude=".git" .
}

final_cleanup() {
  rm $common_archive
  if [[ $TESTSUITE_RESULT -eq 0 ]]; then
    info "Tests for $TESTED_IMAGE succeeded."
  else
    info "Tests for $TESTED_IMAGE failed."
  fi
  exit $TESTSUITE_RESULT
}

trap final_cleanup EXIT SIGINT
analyse_commits
common_archive=/tmp/common-$RANDOM.tar.gz
archive_common $common_archive

# We don't want to remove user's WIP stuff.
test -e "$TESTED_IMAGE" && die "directory '$TESTED_IMAGE' exists"

(   testdir=$PWD
    _cleanup () {
        set -x
        # Ensure the cleanup finishes!
        trap '' INT
        # Go back, wherever we are.
        cd "$testdir"
        # Try to cleanup, if available (and if needed).
        make clean -C "$TESTED_IMAGE" || :
        # Drop the image sources.
        test ! -d "$TESTED_IMAGE" || rm -rf "$TESTED_IMAGE"
    }

    info "Testing $TESTED_IMAGE image"

    # Use --recursive even if we remove 'common', because there might be
    # other git submodules which need to be tested.
    git clone --recursive -q https://github.com/sclorg/"$TESTED_IMAGE".git
    cd "$TESTED_IMAGE"

    if ! test "${IMAGE_REVISION}" = master; then
        info "Fetching $TESTED_IMAGE PR ${IMAGE_REVISION}"
        git fetch origin "pull/${IMAGE_REVISION}/head":PR_BRANCH
        git checkout PR_BRANCH
        git submodule update
    fi

    # We fail if the 'common' directory doesn't exist.
    test -d common
    rm -rf common && mkdir common
    info "Replacing common with PR's version"
    tar xvf $common_archive --directory=./common/ > /dev/null
    # Check if the current version is already GA
    # This directory is cloned from TMT plan repo 'sclorg-tmt-plans'
    devel_file="/root/sclorg-tmt-plans/devel_images"
    VERSIONS=$(grep "^VERSIONS" Makefile | cut -d'=' -f 2)
    echo "VERSIONS are: ${VERSIONS}"
    for dir in ${VERSIONS}; do
      if [ -f "${devel_file}" ]; then
        if grep -q "^${OS}=${TESTED_IMAGE}=${dir}" "$devel_file" ; then
          echo "Adding .devel-repo-${OS} for container ${TESTED_IMAGE}"
          touch "${dir}/.devel-repo-${OS}"
        fi
      fi
    done
    # TODO: The PS4 hack doesn't work if we run the testsuite as UID=0.
    PS4="+ [$TESTED_IMAGE] " make TARGET="$OS" $TESTED_SCENARIO
    result=$?

    _cleanup
    exit $result
)
TESTSUITE_RESULT=$?
