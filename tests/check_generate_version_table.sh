#!/usr/bin/bash

if [ "$(dirname "$0")" != "." ]; then
  echo "You need to run this script from the directory it's located in (./tests)"
  exit 1
fi

# setup
mkdir test-container || exit 1
pushd test-container || exit 1
echo "
BASE_IMAGE_NAME = test
VERSIONS = 1.2 2.3
include ../../common.mk
" > Makefile
export common_dir="../.."

# create base files for the script to work
mkdir 1.2
mkdir 2.3
touch 1.2/Dockerfile.c8s
touch 1.2/Dockerfile.c9s
touch 1.2/Dockerfile.fedora
touch 1.2/Dockerfile.rhel8
touch 1.2/Dockerfile.rhel9
touch 1.2/.exclude-c9s
touch 1.2/.exclude-rhel9
touch 2.3/Dockerfile.c9s
touch 2.3/Dockerfile.c10s
touch 2.3/Dockerfile.fedora
touch 2.3/Dockerfile.rhel9
touch 2.3/Dockerfile.rhel10
touch 2.3/.exclude-fedora

# test README without table tags
touch README.md
make version-table &>/dev/null || exit 1
if [ ! -s "README.md" ]; then
  echo "[PASS] README without table tags not modified"
else
  echo "[FAIL] README without table tags modified"
fi

# test README with table tags
echo "
<!--
Table start
-->
this will be overwritten
<!--
Table end
-->
text outside
" > README.md

echo "
<!--
Table start
-->
||CentOS Stream 9|CentOS Stream 10|Fedora|RHEL 8|RHEL 9|RHEL 10|
|:--|:--:|:--:|:--:|:--:|:--:|:--:|
|1.2|||<details><summary>✓</summary>\`quay.io/fedora/test-12\`</details>|<details><summary>✓</summary>\`registry.redhat.io/rhel8/test-12\`</details>|||
|2.3|<details><summary>✓</summary>\`quay.io/sclorg/test-23-c9s\`</details>|<details><summary>✓</summary>\`quay.io/sclorg/test-23-c10s\`</details>|||<details><summary>✓</summary>\`registry.redhat.io/rhel9/test-23\`</details>|<details><summary>✓</summary>\`registry.redhat.io/rhel10/test-23\`</details>|
<!--
Table end
-->
text outside
" > README.expected
make version-table &>/dev/null || exit 1
if diff README.md README.expected ; then
  echo "[PASS] README with table tags modified correctly"
else
  echo "[FAIL] README with table tags modified incorrectly or not modified"
fi

# test README with multiple pairs of table tags
echo "
<!--
Table start
-->
<!--
Table end
-->
text inbetween
<!--
Table start
-->
<!--
Table end
-->
" > README.md

echo "
<!--
Table start
-->
<!--
Table end
-->
text inbetween
<!--
Table start
-->
<!--
Table end
-->
" > README.expected

make version-table &>/dev/null || exit 1
if diff README.md README.expected ; then
  echo "[PASS] README with multiple pairs of table tags unmodified"
else
  echo "[FAIL] README with multiple pairs of table tags modified"
fi

# cleanup
popd || exit 1
rm -rf test-container