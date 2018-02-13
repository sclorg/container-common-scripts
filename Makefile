all:
	@echo >&2 "Only 'make check' allowed"


TESTED_IMAGES = \
	postgresql-container \
	s2i-python-container

.PHONY: check test all check-failures


check-failures:
	cd tests/failures/check && make tag && ! make check && make clean

test: check
check: check-failures
	TESTED_IMAGES="$(TESTED_IMAGES)" tests/remote-containers.sh
