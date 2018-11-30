#! /bin/sh

set -e

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
