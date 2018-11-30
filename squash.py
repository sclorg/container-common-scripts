#! /bin/python

import sys
import logging
from platform import python_version

try:
    from docker_squash import squash
except ImportError:
    logging.fatal("please install 'docker_squash' for Python {0}".format(python_version()))
    sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        logging.fatal("%s: %s", sys.argv[0], msg)
        sys.exit(1)

    print(squash.Squash(
        log=logging.getLogger(),
        image=sys.argv[1],
        from_layer=sys.argv[2]).run()
    )
