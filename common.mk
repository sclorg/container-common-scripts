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
testr = $(SHELL) $(common_dir)/test-remote-cluster.sh
shellcheck =  $(SHELL) $(common_dir)/run-shellcheck.sh
tag =   $(SHELL) $(common_dir)/tag.sh
clean = $(SHELL) $(common_dir)/clean.sh

DG ?= /bin/dg

generator = DG="$(DG)" $(SHELL) $(common_dir)/generate.sh


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
else ifeq ($(TARGET),rhel7)
	SKIP_SQUASH ?= 0
	OS := rhel7
	DOCKERFILE ?= Dockerfile.rhel7
else ifeq ($(TARGET),fedora)
	OS := fedora
	DOCKERFILE ?= Dockerfile.fedora
else ifeq ($(TARGET),centos6)
	OS := centos6
	DOCKERFILE ?= Dockerfile.centos6
else ifeq ($(TARGET),centos8)
	OS := centos8
	DOCKERFILE ?= Dockerfile.centos8
else
	OS := centos7
	DOCKERFILE ?= Dockerfile
endif

SKIP_SQUASH ?= 1
DOCKER_BUILD_CONTEXT ?= .
SHELLCHECK_FILES ?= .

script_env = \
	SKIP_SQUASH=$(SKIP_SQUASH)                      \
	UPDATE_BASE=$(UPDATE_BASE)                      \
	OS=$(OS)                                        \
	CLEAN_AFTER=$(CLEAN_AFTER)                      \
	DOCKER_BUILD_CONTEXT=$(DOCKER_BUILD_CONTEXT)    \
	OPENSHIFT_NAMESPACES="$(OPENSHIFT_NAMESPACES)"  \
	CUSTOM_REPO="$(CUSTOM_REPO)"

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
$(VERSIONS): % : %/root/help.1
	VERSION="$@" $(script_env) $(build)

.PHONY: test check
check: test

test: script_env += TEST_MODE=true

# The tests should ideally depend on $IMAGE_ID only, but see PR#19 for more info
# while we need to depend on 'tag' instead of 'build'.
test: tag
	VERSIONS="$(VERSIONS)" $(script_env) $(test)

.PHONY: test-with-conu
test-with-conu: script_env += TEST_CONU_MODE=true
test-with-conu: tag
	VERSIONS="$(VERSIONS)" $(script_env) $(test)

.PHONY: test-openshift-4
test-openshift-4: script_env += TEST_OPENSHIFT_4=true
test-openshift-4: tag
	VERSIONS="$(VERSIONS)" BASE_IMAGE_NAME="$(BASE_IMAGE_NAME)" $(script_env) $(test)

.PHONY: test-openshift
test-openshift: script_env += TEST_OPENSHIFT_MODE=true
test-openshift: tag
	VERSIONS="$(VERSIONS)" BASE_IMAGE_NAME="$(BASE_IMAGE_NAME)" $(script_env) $(test)

.PHONY: shellcheck
shellcheck:
	$(shellcheck) $(SHELLCHECK_FILES)

.PHONY: tag
tag: build
	VERSIONS="$(VERSIONS)" $(script_env) $(tag)

.PHONY: clean clean-hook clean-images clean-versions
clean: clean-images
	@$(MAKE) --no-print-directory clean-hook

clean-images:
	$(clean) $(VERSIONS)

clean-versions:
	rm -rf $(VERSIONS)

%root/help.1: %README.md
	mkdir -p $(@D)
	go-md2man -in "$^" -out "$@"
	chmod a+r "$@"

generate-all: generate

MANIFEST_FILE ?= manifest.sh

auto_targets.mk: $(MANIFEST_FILE)
	MANIFEST_FILE="$(MANIFEST_FILE)" \
	VERSIONS="$(VERSIONS)" \
	$(generator)

# triggers build of auto_targets.mk automatically
-include auto_targets.mk

# We have to remove auto_targets.mk here, otherwise subsequent make calls
# with different VERSIONS=* option keeps the auto_targets.mk unchanged.
.PHONY: generate
generate: $(DISTGEN_TARGETS) $(DISTGEN_MULTI_TARGETS) $(COPY_TARGETS) $(SYMLINK_TARGETS)
	rm auto_targets.mk
