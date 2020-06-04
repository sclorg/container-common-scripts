SHELL := /usr/bin/env bash

all:
	@echo >&2 "Only 'make check' allowed"


TESTED_IMAGES = \
	postgresql-container \
	s2i-python-container \
	s2i-nodejs-container

.PHONY: check test all check-failures


TEST_LIB_TESTS = \
	path_foreach \
	random_string \
	test_npm \
	image_availability \
	public_image_name

$(TEST_LIB_TESTS):
	@echo "  RUN TEST '$@'" ; \
	$(SHELL) tests/test-lib/$@ || $(SHELL) -x tests/lib/$@

test-lib-foreach:

check-test-lib: $(TEST_LIB_TESTS)

test: check

shellcheck:
	./run-shellcheck.sh `git ls-files *.sh`

check-failures: check-test-lib
	cd tests/failures/check && make tag && ! make check && make clean
	grep -q "Red Hat Enterprise Linux release 8" /etc/system-release || cd tests/failures/check && make tag SKIP_SQUASH=0

check-squash:
	./tests/squash/squash.sh

check-latest-imagestream:
	cd tests && ./check_imagestreams.sh

check: check-failures check-squash check-latest-imagestream
	TESTED_IMAGES="$(TESTED_IMAGES)" tests/remote-containers.sh
