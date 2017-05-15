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
	VERSIONS="$(VERSIONS)"                          \
	OS=$(OS)                                        \
	VERSION="$(VERSION)"                            \
	BASE_IMAGE_NAME=$(BASE_IMAGE_NAME)              \
	OPENSHIFT_NAMESPACES="$(OPENSHIFT_NAMESPACES)"

.PHONY: build
build: manpages
	$(script_env) $(build)

.PHONY: test
test: manpages
	$(script_env) TAG_ON_SUCCESS=$(TAG_ON_SUCCESS) TEST_MODE=true $(build)

.PHONY: test-openshift
test-openshift: manpages
	$(script_env) TAG_ON_SUCCESS=$(TAG_ON_SUCCESS) TEST_OPENSHIFT_MODE=true $(build)

manpages = $(shell for version in $(if $(VERSION), $(VERSION), $(VERSIONS)); \
		do echo "$$version/root/help.1"; done)
manpages: $(manpages)
$(manpages): %root/help.1: %README.md
	mkdir -p $(@D)
	go-md2man -in "$^" -out "$@"
