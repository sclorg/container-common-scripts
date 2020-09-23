Common build helpers for sclorg containers
==========================================

This repository is aimed to be added as git submodule into particular
containers' source repositories.  By default, the path to submodule should be
named 'common'.

Usage
-----

This section explains the usage of the shared scripts in this repository when
it is used as a submodule in a container source repository.

Once you have the repository set as a submodule include `common.mk` into your
root Makefile in order to access the default rules used to call shared scripts.

**Default rules:**

`make` or `make build`  
This rule will build an image without tagging it with any tags after it is built.
After the image finishes building the scripts will squash the image using `docker-squash`.
`make build` will also expect a `README.md` so that it can transfrom it into
a man page that gets added to the image so make sure it is available and that
you have the `go-md2man` tool installed on your host.


`make tag`  
Use this rule if you want to tag an image after it is built. It will be tagged with
two tags - name:latest and name:version.
Depends on `build`

`make test` or `make check`  
This rule will run the testsuite scripts contained in the container source repositories.
It expects the test to be available at `$gitroot/$version/test/run`
Depends on `tag` as some tests might need to have the images tagged (s2i).

`make test-openshift`  
Similar to `make test` but runs testsuite for Openshift 3, expected to be found at
`$gitroot/$version/test/run-openshift`

`make test-openshift-4`
Similar to `make test` but runs testsuite for Openshift 4, expected to be found at
`$gitroot/$version/test/run-openshift-remote-cluster`

`make test-with-conu`  
The rule is similar to `make test`. It runs a test suite written using [conu
library](https://github.com/user-cont/conu). The path to the test script is
meant to be at `$gitroot/$version/test/run-conu`. By default the test suite is
being run in the current environment. You can also run the tests in a container
by defining variable `CONU_IMAGE`. Container images with conu are available in
[this docker hub repository](docker.io/usercont/conu:0.6.2), a good value for
the variable is `docker.io/usercont/conu:0.6.2`.

`make clean`  
Runs scripts that clean-up the working dir. Depends on the `clean-images` rule by default
and additional clean rules can be provided through the `clean-hook` variable.

`make clean-images`  
Best-effort to remove the last set of images that have been built using the scripts.

`make shellcheck`  
Check the shell syntax of the files specified by `$SHELLCHECK_FILES` variable.
See `SHELLCHECK_FILES` variable description below for more info (default is `.`).
The files matching this specification are then filtered, to not show results twice
for symlinks. Only files with a suffix `.sh` or shell shebang are scanned with
the `shellcheck` utility. See [run-shellcheck.sh](./run-shellcheck.sh) in this repo for more detailed info.
Once the shell syntax issues are fixed, CI that runs `make shellcheck` for each PR can be
turned on by putting [.travis.yml](.travis.yml) file into the root of the image's repository.
[.travis.yml](https://github.com/sclorg/container-common-scripts/blob/master/.travis.yml)
for its content.

**There are additional variables that you can use that the default rules are prepared to
work with:**

`VERSIONS`  
Names of the directories in which the Dockerfiles are contained. Needs to be defined in your
Dockerfile for the scripts to know which versions to build.

`OS`  
OS version you want to build the images for. Currently the scripts are able to build for
centos (default), centos6, centos8, rhel7, rhel8 and fedora.

`SKIP_SQUASH`  
When set to 1 the build script will skip the squash phase of the build.

`CUSTOM_REPO`  
Set this variable to the path to your local .repo files you want to have available inside
the image while building. Useful for building rhel-based images on an unsubscribed box.
Be aware that you cannot write to any .repo files used this way inside the image as they
will be mounted into the image as read-only.

`UPDATE_BASE`  
Set to 1 if you want the build script to always pull the base image when available.

`DOCKER_BUILD_CONTEXT`  
Use this variable in case you want to have a different context for your builds. By default
the context of the build is the versioned directory the Dockerfiles are contained in.

`SHELLCHECK_FILES`  
One or more files or directories to be scanned by the shellcheck, default is `.`, which
means a whole repository directory. If a directory is provided then all of its content
is scanned as well.

`clean-hook`  
Append Makefile rules to this variable to make sure additional cleaning actions are run
when `make clean` is called.

Regression tests
----------------

`make check`  
Runs the tests of few images that use this set of scripts. If the tests of those
images pass, this repo is considered to be working.

`make shellcheck`  
Check the shell syntax of all `*.sh` files tracked by the git in this repository.

Dependencies for testsuite:

- docker
- docker-squash
- git
- go-md2man
- make
- source-to-image
- shellcheck
