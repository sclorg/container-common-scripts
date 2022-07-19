#!/bin/bash

set -e

if grep -q "Red Hat Enterprise Linux release 8" /etc/system-release || grep -q "Red Hat Enterprise Linux release 9" /etc/system-release ; then
  echo "make tag SKIP_SQUASH=0 is skipped on RHEL8 and RHEL 9."
  exit 0
fi

make tag SKIP_SQUASH=0
