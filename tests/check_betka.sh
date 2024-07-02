#!/bin/sh

set -x

betka=$(dirname "$(readlink -f "$0")")/../betka.sh

# CentOS7 is not support for make betka
bash $betka OS=centos7
test $? -eq 1

# DOWNSTREAM_NAME is missing
OS=fedora bash $betka
test $? -eq 1

# DOWNSTREAM_NAME is missing
OS=fedora DOWNSTREAM_BRANCH=f32 bash $betka
test $? -eq 1

# DOCKER_IMAGE is missing
bash $betka OS=rhel8
test $? -eq 1

# DOWNSTREAM_NAME is missing
bash $betka OS=rhel8 DOCKER_IMAGE="quay.io/rhscl/dummy"
test $? -eq 1

# DOWNSTREAM_BRANCH is missing
bash $betka OS=rhel8 DOCKER_IMAGE="quay.io/rhscl/dummy" DOWNSTREAM_NAME="foo_test"
test $? -eq 1
