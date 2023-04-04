import sys
import re

from typing import List

def get_versions() -> List[str]:
    versions = []
    with open("../Makefile") as makefile:
        lines = makefile.readlines()
        pattern = "VERSIONS = "
        for line in lines:
            if re.match(pattern, line):
                line = line.strip()
                versions = line[len(pattern):].split(" ")
    return versions
