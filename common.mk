# SKIP_SQUASH = 0/1
# =================
# If set to '0', images are automatically squashed.  '1' disables
# squashing.  By default only RHEL containers are squashed.

SHELL := /usr/bin/env bash

ifndef common_dir
    common_dir = common
endif

build = $(SHELL) $(common_dir)/build.sh
test =  $(SHELL) $(common_dir)/test.sh
shellcheck =  $(SHELL) $(common_dir)/run-shellcheck.sh
clean = $(SHELL) $(common_dir)/clean.sh
betka = $(SHELL) $(common_dir)/betka.sh

DG ?= /bin/dg

generator = $(common_dir)/generator.py


# pretty printers
# ---------------
__PROLOG = $(if $(VERBOSE),,@echo "  $(1)   " $@;)
V_LN  = $(call __PROLOG,LN )
V_DG  = $(call __PROLOG,DG )
V_DGM = $(call __PROLOG,DGM)
V_CP  = $(call __PROLOG,CP )

CDIR  = mkdir -p "$$(dirname "$@")" || exit 1 ;

ifeq ($(TARGET),rhel8)
	SKIP_SQUASH ?= 1
	OS := rhel8
	DOCKERFILE ?= Dockerfile.rhel8
else ifeq ($(TARGET),rhel9)
	OS := rhel9
	DOCKERFILE ?= Dockerfile.rhel9
else ifeq ($(TARGET),rhel10)
	OS := rhel10
	DOCKERFILE ?= Dockerfile.rhel10
else ifeq ($(TARGET),rhel11)
	OS := rhel11
	DOCKERFILE ?= Dockerfile.rhel11
else ifeq ($(TARGET),fedora)
	OS := fedora
	DOCKERFILE ?= Dockerfile.fedora
	REGISTRY := quay.io/
else ifeq ($(TARGET),c9s)
	OS := c9s
	DOCKERFILE ?= Dockerfile.c9s
	REGISTRY := quay.io/
else ifeq ($(TARGET),c10s)
	OS := c10s
	DOCKERFILE ?= Dockerfile.c10s
	REGISTRY := quay.io/
else
	OS := c11s
	DOCKERFILE ?= Dockerfile.c11s
	REGISTRY := quay.io/
endif

SKIP_SQUASH ?= 1
DOCKER_BUILD_CONTEXT ?= .
SHELLCHECK_FILES ?= .
REGISTRY ?= ""

script_env = \
	SKIP_SQUASH=$(SKIP_SQUASH)                      \
	OS=$(OS)                                        \
	CLEAN_AFTER=$(CLEAN_AFTER)                      \
	DOCKER_BUILD_CONTEXT=$(DOCKER_BUILD_CONTEXT)    \
	OPENSHIFT_NAMESPACES="$(OPENSHIFT_NAMESPACES)"  \
	CUSTOM_REPO="$(CUSTOM_REPO)" \
	REGISTRY="$(REGISTRY)"

# TODO: switch to 'build: build-all' once parallel builds are relatively safe
.PHONY: build build-serial build-all
build: build-serial
build-serial:
	@$(MAKE) -j1 build-all

build-all: $(VERSIONS)
	@for i in $(VERSIONS); do \
	    test -f $$i/.image-id || continue ; \
	    echo -n "$(BASE_IMAGE_NAME) $$i => " ; \
	    cat $$i/.image-id ; \
	done

.PHONY: $(VERSIONS)
$(VERSIONS): copy_md_files
	VERSION="$@" $(script_env) $(build)

.PHONY: test check
check: test

test: script_env += TEST_MODE=true

# The tests should ideally depend on $IMAGE_ID only, but see PR#19 for more info
test: build
	VERSIONS="$(VERSIONS)" $(script_env) $(test)

.PHONY: test-openshift-4
test-openshift-4: script_env += TEST_OPENSHIFT_4=true
test-openshift-4: build
	VERSIONS="$(VERSIONS)" BASE_IMAGE_NAME="$(BASE_IMAGE_NAME)" $(script_env) $(test)

.PHONY: test-openshift
test-openshift: script_env += TEST_OPENSHIFT_MODE=true
test-openshift: build
	VERSIONS="$(VERSIONS)" BASE_IMAGE_NAME="$(BASE_IMAGE_NAME)" $(script_env) $(test)

.PHONY: test-openshift-pytest
test-openshift-pytest: script_env += TEST_OPENSHIFT_PYTEST=true
test-openshift-pytest: build
	VERSIONS="$(VERSIONS)" BASE_IMAGE_NAME="$(BASE_IMAGE_NAME)" $(script_env) $(test)

.PHONY: test-pytest
test-pytest: script_env += TEST_PYTEST=true
test-pytest: build
	VERSIONS="$(VERSIONS)" BASE_IMAGE_NAME="$(BASE_IMAGE_NAME)" $(script_env) $(test)


.PHONY: shellcheck
shellcheck:
	$(shellcheck) $(SHELLCHECK_FILES)

.PHOHY: betka
betka:
	VERSIONS="$(VERSIONS)" \
    DOWNSTREAM_NAME="$(DOWNSTREAM_NAME)" \
    DOCKER_IMAGE="$(DOCKER_IMAGE)" \
    $(script_env) $(betka)

.PHONY: clean clean-hook clean-images clean-versions
clean: remove_md_files clean-images
	@$(MAKE) --no-print-directory clean-hook

clean-images:
	$(clean) $(VERSIONS)

clean-versions:
	rm -rf $(VERSIONS)

# Copy also all .md files from version directory to the root of
# container images, so that they are available in the image
# Currently there is only README.md, but there may be more in the future
copy_md_files:
	@for version in $(VERSIONS); do \
		mkdir -p "$$version/root" ; \
		if ls $$version/*.md 1> /dev/null 2>&1; then \
			cp -v $$version/*.md "$$version/root" ; \
			chmod a+r $$version/root/*.md ; \
		fi ; \
	done

remove_md_files:
	@for version in $(VERSIONS); do \
		if ls $$version/*.md 1> /dev/null 2>&1; then \
			rm -fv $$version/root/*.md ; \
		fi ; \
	done

generate-all: generate

.PHOHY: generate
generate:
	for version in ${VERSIONS} ; do \
		if [[ "$$version" == *-minimal ]]; then \
			$(generator) -v $$version -m manifest-minimal.yml -s specs/multispec.yml ; \
		else \
			$(generator) -v $$version -m manifest.yml -s specs/multispec.yml ; \
		fi \
	done

version-table:
	$(common_dir)/generate_version_table.py "$(BASE_IMAGE_NAME)"
