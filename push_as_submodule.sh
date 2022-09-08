#!/bin/bash
# MIT License
#
# Copyright (c) 2022 Red Hat, Inc.

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#----------------------------------
# parameters to configure by the user

declare -a all_sclorg_images=(\
"s2i-base-container"
"mysql-container"
"mariadb-container"
"postgresql-container"
"redis-container"
"s2i-php-container"
"s2i-python-container"
"s2i-perl-container"
"s2i-ruby-container"
"varnish-container"
"nginx-container"
"s2i-nodejs-container"
"httpd-container"
)

branch=master
remote=origin
commit_msg="Update common submodule to current latest $remote/$branch commit"

#----------------------------------

function exit_on_err() {
  local ret=$1
  local reason=${2:-"unknown"}
  if [[ $ret -ne 0 ]]; then
    echo "ERR: Exiting for reason: $reason" 2>&1 && exit 1
  fi
}

function clone_repo() {
  local container=$1
  [[ -z $container ]] && exit_on_err 1 "container name for cloning repository is missing"
  local url="git@github.com:sclorg/${container}.git"
  git clone "$url" "$container"
  exit_on_err $? "git clone failed"
  cd "$container" || return 1
  git submodule update --init
  exit_on_err $? "submodule init failed"
  cd ..
}

function update_submodule() {
  local sha=$1
  [[ -z "$sha" ]] && exit_on_err 1 "commit SHA is missing for updating submodule"
  cd common/ || return 1
  git fetch -a
  git checkout "$sha"
  exit_on_err $? "checkout common on $sha failed"
  cd ..
  git add common/
}

function commit_change() {
  local commit_msg=$1
  [[ -z "$commit_msg" ]] && exit_on_err 1 "commit message is missing"
  git commit -m "$commit_msg"
}

function show_diff() {
  local container=$1
  local answer
  git diff $branch $remote/$branch
  exit_on_err $? "diff failed"
  echo "Are you sure, you want to push the above changes to $remote/$branch of"
  echo "git@github.com:sclorg/${container}.git?"
  echo "Y/n"
  read -r answer
  while [[ $answer != Y && $answer != n ]]; do
    read -r answer
  done
  [[ "$answer" == "n" ]] && return 1
  return 0
}

function push_change() {
  local image=$1
  show_diff "$image"
  [[ $? -eq 1 ]] && echo "WARN: $image will not be pushed." && return 1
  git push
  exit_on_err $? "push failed"
}

function get_remote_branch_hash() {
  git fetch "$remote"
  git rev-parse "$remote"/"$branch"
  exit_on_err $?
}

function cleanup() {
  echo "Updated container images are: $updated_containers"
  # shellcheck disable=SC2164
  cd "$cur_dir"
  rm -rf "$tmp_dir"
  echo "All cleaned!"
  exit 0
}

#----------------------------------

echo "This script is going to pull from and push to multiple git repositories."
echo "Therefore it is recommended to use ssh-agent."
echo "You can pass SHA of commit to update the submodules to as a parameter."
echo "If it is not passed, current HEAD of $remote/$branch is used."
echo "Press Enter to continue." ; read -r

hash=$1; [[ -z $hash ]] && hash=$(get_remote_branch_hash)
cur_dir=$PWD
tmp_dir=$(mktemp -d) && cd "$tmp_dir" || exit 1
updated_containers=""
trap cleanup SIGINT EXIT

echo "Updating common/ submodule in following repositories: ${all_sclorg_images[*]}"
for image in "${all_sclorg_images[@]}"; do
  clone_repo "$image"
  cd "$image" || exit 1
  # following steps count with a fact, that $PWD==$image
  update_submodule "$hash"
  commit_change "$commit_msg"
  push_change "$image" && updated_containers="$updated_containers $image"
  cd ..
done
