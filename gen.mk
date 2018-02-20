# Helper for generating image repository files

ifndef common_dir
    common_dir = common
endif

generator = $(common_dir)/generate.sh
# default path for dg binary from package distgen
DISTGEN_BIN ?= /usr/bin/dg
MANIFEST_FILE ?= manifest.sh

generation_env = \
	DG=$(DISTGEN_BIN) \
	MANIFEST_FILE=$(MANIFEST_FILE)

.PHONY: gen
gen: auto_targets.mk exec-gen-rules
	rm auto_targets.mk


auto_targets.mk: $(generator) $(MANIFEST_FILE)
	VERSIONS="$(VERSIONS)" DG_CONF="$(DG_CONF)" $(generation_env) $(generator)

include auto_targets.mk

.PHONY: exec-gen-rules
exec-gen-rules: $(DISTGEN_TARGETS) $(COPY_TARGETS) $(SYMLINK_TARGETS)
