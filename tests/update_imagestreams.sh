#!/bin/sh

set -x

DOCKER_REGISTRY="docker.registry.io/testing/rhel.json"
TESTING_FILE="./imagestreams/testing_file.json"
UPDATED_FILE="./imagestreams/updated-testing_file.json"
update_imagestreams=$(dirname "$(readlink -f "$0")")/../update_imagestreams.py
"${PYTHON-python3}" "$update_imagestreams" "2.4" "$TESTING_FILE" "$DOCKER_REGISTRY"
test $? -eq 0
grep '"name": "docker.registry.io/testing/rhel.json"' "$UPDATED_FILE"
test $? -eq 0
rm -f "./imagestreams/updated-testing_file.json"
"${PYTHON-python3}" "$update_imagestreams" "2.8" "$TESTING_FILE" "$DOCKER_REGISTRY"
test $? -eq 0
grep '"name": "docker.registry.io/testing/rhel.json"' "$UPDATED_FILE"
test $? -eq 0
grep '"name": "2.8"' "./imagestreams/updated-testing_file.json"
test $? -eq 0
rm -f "./imagestreams/updated-testing_file.json"
"${PYTHON-python3}" "$update_imagestreams" "10" "./imagestreams/wrong_file.json" "$DOCKER_REGISTRY"
test $? -eq 1
test ! -f "$UPDATED_FILE"
