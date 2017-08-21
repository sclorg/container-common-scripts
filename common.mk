# SKIP_SQUASH = 0/1
# =================
# If set to '0', images are automatically squashed.  '1' disables
# squashing.  By default only RHEL containers are squashed.

ifndef common_dir
    common_dir = common
endif

build = $(common_dir)/build.sh
test = $(common_dir)/test.sh
tag = $(common_dir)/tag.sh
clean = $(common_dir)/clean.sh

ifeq ($(TARGET),rhel7)
	SKIP_SQUASH ?= 0
	OS := rhel7
	DOCKERFILE ?= Dockerfile.rhel7
else ifeq ($(TARGET),fedora)
	OS := fedora
	DOCKERFILE ?= Dockerfile.fedora
else
	OS := centos7
	DOCKERFILE ?= Dockerfile
endif

SKIP_SQUASH ?= 1

script_env = \
	SKIP_SQUASH=$(SKIP_SQUASH)                      \
	UPDATE_BASE=$(UPDATE_BASE)                      \
	OS=$(OS)                                        \
	CLEAN_AFTER=$(CLEAN_AFTER)                      \
	OPENSHIFT_NAMESPACES="$(OPENSHIFT_NAMESPACES)"

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

.PHONY: test-openshift
test-openshift: script_env += TEST_OPENSHIFT_MODE=true
test-openshift: tag
	VERSIONS="$(VERSIONS)" $(script_env) $(test)

.PHONY: tag
tag: build
	VERSIONS="$(VERSIONS)" $(script_env) $(tag)

.PHONY: clean
clean:
	$(clean) $(VERSIONS)

%root/help.1: %README.md
	mkdir -p $(@D)
	go-md2man -in "$^" -out "$@"
	chmod a+r "$@"
