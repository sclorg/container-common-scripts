import re
import os

from typing import List, Optional

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


def load_readme(dir: str) -> Optional[str]:
    """
    Loads repository README starting from (but not including) Description line
    """
    
    readme_path = os.path.join(dir, "README.md")
    with open(readme_path) as readme:
        lines = readme.readlines()
        for i, line in enumerate(lines):
            if re.match("Description", line):
                output_lines = lines[i + 3:]
                return "".join(output_lines)  # Skip seperator line and empty line
    return None

