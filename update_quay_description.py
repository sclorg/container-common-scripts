import sys
import re
import os

from typing import List

def get_versions() -> List[str]:
    """
    Loads readme from repository versions define in VERSIONS as list of strings
    """
    versions = []
    with open("../Makefile") as makefile:
        lines = makefile.readlines()
        pattern = "VERSIONS = "
        for line in lines:
            if re.match(pattern, line):
                line = line.strip()
                versions = line[len(pattern):].split(" ")
    return versions


def load_readme(dir: str) -> str:
    """
    Loads repository README starting from (but not including) Description line
    """
    
    readme_path = os.path.join(dir, "README.md")
    with open(readme_path) as readme:
        lines = readme.readlines()
        for i, line in enumerate(lines):
            if re.match("Description", line):
                return lines[i + 3:] # Skip seperator line and empty line
