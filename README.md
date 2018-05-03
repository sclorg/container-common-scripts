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
Similar to `make test` but runs testsuite for Openshift, expected to be found at
`$gitroot/$version/test/run-openshift`

`make clean`  
Runs scripts that clean-up the working dir. Depends on the `clean-images` rule by default
and additional clean rules can be provided through the `clean-hook` variable.

`make clean-images`  
Best-effort to remove the last set of images that have been built using the scripts.

**There are additional variables that you can use that the default rules are prepared to
work with:**

`VERSIONS`  
Names of the directories in which the Dockerfiles are contained. Needs to be defined in your
Dockerfile for the scripts to know which versions to build.

`OS`  
OS version you want to build the images for. Currently the scripts are able to build for
centos (default), centos6, rhel7 and fedora.

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

`clean-hook`  
Append Makefile rules to this variable to make sure additional cleaning actions are run
when `make clean` is called.

Regression tests
----------------

Just run `make check`

Dependencies for testsuite:

- docker
- docker-squash (version 1.0.5)
- git
- go-md2man
- make
- source-to-image
