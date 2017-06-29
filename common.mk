SKIP_SQUASH?=0

ifndef common_dir
    common_dir = common
endif

build = $(common_dir)/build.sh

ifeq ($(TARGET),rhel7)
	OS := rhel7
else ifeq ($(TARGET),fedora)
	OS := fedora
else
	OS := centos7
endif

script_env = \
	SKIP_SQUASH=$(SKIP_SQUASH)                      \
	UPDATE_BASE=$(UPDATE_BASE)                      \
	OS=$(OS)                                        \
	OPENSHIFT_NAMESPACES="$(OPENSHIFT_NAMESPACES)"

.PHONY: build
build: $(VERSIONS)

.PHONY: $(VERSIONS)
$(VERSIONS): % : %/root/help.1
	VERSION="$@" $(script_env) $(build)

.PHONY: test
test: script_env += TEST_MODE=true
test: $(VERSIONS)

.PHONY: test-openshift
test-openshift: script_env += TEST_OPENSHIFT_MODE=true
test-openshift: $(VERSIONS)

%root/help.1: %README.md
	mkdir -p $(@D)
	go-md2man -in "$^" -out "$@"
