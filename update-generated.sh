#!/bin/bash

set -ex
shopt -s extglob

COMMIT=$(git rev-parse HEAD)

# import generated content from this git reference ..
SOURCE_BRANCH=${1:-$COMMIT}

# into this git branch
GENERATED_BRANCH=${2:-generated}

git clean -f -d

# switch to generated branch for working env; and switch back later
git checkout "$GENERATED_BRANCH"
git submodule update

# Clean everything in generated branch.
rm -rf -- *

srcdir=srcdir

cleanup ()
{
    exit_status=$?
    rm -rf "$srcdir"

    # switch back to initial ranch
    git checkout "$SOURCE_BRANCH"
    git submodule update

    return $exit_status
}
trap cleanup EXIT

(
    # Copy the actual repo into $srcdir, and generate there
    mkdir "$srcdir"
    cd "$srcdir"
    git clone .. .
    git checkout "$SOURCE_BRANCH"
    git submodule update --init
    make generate-all
)

# copy the relevant (generated) content from $srcdir
versions=$(sed -n 's/^VERSIONS[[:space:]]*=//p' "$srcdir"/Makefile)
for i in $versions; do
    cp -r "$srcdir/$i" .
done

# source directory is not needed anymore
rm -rf "$srcdir"

# shellcheck disable=SC2086
git add $versions

# Add deleted files to the index as well
(
    IFS=$'\n'
    for i in $(git ls-files --deleted) ;do
        git add --all "$i"
    done
)

if ! git diff --cached --exit-code --quiet ; then
    git commit -m "auto-sync: master commit $COMMIT"
else
    echo "Nothing changed"
fi
