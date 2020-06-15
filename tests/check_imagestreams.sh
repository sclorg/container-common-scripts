#!/bin/sh

set -x

check_imagestreams=$(dirname "$(readlink -f "$0")")/../check_imagestreams.py
"${PYTHON-python3}" "$check_imagestreams" "2.5"
test $? -eq 1
"${PYTHON-python3}" "$check_imagestreams" "2.4"
test $? -eq 0
