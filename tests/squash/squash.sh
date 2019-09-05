#! /bin/sh

set -e

if grep -q "Red Hat Enterprise Linux release 8" /etc/system-release; then
  # No use testing squash.py on rhel8 for now as it does not work at all
  echo "  ! test case ignored on RHEL8 host"
  exit 0
fi

origin=busybox
squash=$(dirname "$(readlink -f "$0")")/../../squash.py
cd "$(dirname "$0")"

cat > Dockerfile <<EOF
FROM $origin
ENV test=test
CMD /bin/echo test
EOF
out=`docker build . | awk '/Successfully built/{print $NF}'`
echo "$out"
squashed=$("${PYTHON-python3}" "$squash" "$out" "$origin")
output=$(docker run --rm $squashed)
test "$output" = "test"
