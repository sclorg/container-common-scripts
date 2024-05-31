#!/bin/sh

set -x

check_imagestreams=$(dirname "$(readlink -f "$0")")/../check_imagestreams.py
show_all_imagestreams=$(dirname "$(readlink -f "$0")")/../show_all_imagestreams.py
"${PYTHON-python3}" "$check_imagestreams" "2.5"
test $? -eq 1
"${PYTHON-python3}" "$check_imagestreams" "2.4"
test $? -eq 0

echo "This tests check if 'show_all_imagestreams.py' returns proper output"
output=$("${PYTHON-python3}" "$show_all_imagestreams")
test "${output#*"- latest -> 2.4"}" != "$output" && echo "latest found in the output"
test "${output#*"- 2.4 -> registry.redhat.io/rhscl/httpd-24-rhel7"}" != "$output" && echo "2.4 found in the output"
