#!/bin/bash

set -ex

SOURCE_BRANCH=${1:-master}
GENERATED_BRANCH=${2:-generated}

git clean -f -d

# checkout source branch
git checkout "$SOURCE_BRANCH" && git submodule update
tag=$(git rev-parse HEAD)

# copy the branch content into source/
rsync -a ./* source
VERSIONS=$(sed -n 's/^VERSIONS[[:space:]]*=//p' source/Makefile)

git checkout "$GENERATED_BRANCH" && git submodule update
for i in *; do
    case "$i" in
    # Do not remove the update script or common submodule
    update|common|source)
        continue
        ;;
    *)
        rm -rf "$i"
        ;;
    esac
done

# Generate the sources inside source/ and copy them to root
(
    cd source
    make generate-all
    for i in $VERSIONS; do
        cp -r "$i" ../
    done
)
rm -rf source

git add $VERSIONS

# Add deleted files to the index as well
(
    IFS=$'\n'
    for i in $(git ls-files --deleted) ;do
        git add "$i"
    done
)

if ! git diff --cached --exit-code --quiet ; then
    git commit -m "auto-sync: master commit $tag"
else
    echo "Nothing changed"
fi
