all:
	@echo >&2 "Only 'make check' allowed"


TESTED_IMAGES = \
	postgresql-container \
	s2i-python-container

.PHONY: check test all
test: check
check:
	TESTED_IMAGES="$(TESTED_IMAGES)" tests/remote-containers.sh
