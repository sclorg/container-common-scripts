import re
import os
from typing import List, Optional
import requests


def load_makefile_var(var_name: str) -> Optional[List[str]]:
    """
    Returns list of values definied in var_name in Makefile
    """
    with open("../Makefile") as makefile:
        lines = makefile.readlines()
        pattern = var_name + " = "
        for line in lines:
            if re.match(pattern, line):
                line = line.strip()
                return line[len(pattern):].split(" ")
    return None


def get_quay_extensions(dir: str, org: str) -> Optional[List[str]]:
    """
    Return list of extensions for which given container is available in given
    quay organization (so far supports sclorg and centos7)
    """
    org_extension_pattern = {"sclorg": "Dockerfile.c",
                             "centos7": "Dockerfile.centos7"}
    
    pattern = org_extension_pattern.get(org, "")
    if pattern == "":
        return None
    
    files = os.listdir(dir)
    sclorg_files = filter(lambda file_name: re.match(pattern, file_name), files)
    quay_versions = list(map(lambda file_name: file_name.split(".")[1], sclorg_files))
    return quay_versions


def load_readme(dir: str) -> Optional[str]:
    """
    Loads repository README starting from (but not including) Description line
    """
    
    readme_path = os.path.join(dir, "README.md")
    with open(readme_path) as readme:
        lines = readme.readlines()
        for i, line in enumerate(lines):
            if re.match("Description", line):
                output_lines = lines[i + 3:]  # Skip seperator line and empty line
                return "".join(output_lines)
    return None


def update_description(username: str, token: str, org_name: str,
                       version: str, cont_name: str, readme: str) -> int:
    # Remove dot from version
    if "." in version:
        version = version.replace(".", "")
    
    version_dir = f"../{version}"

    extension = get_quay_extensions(version_dir)
    repo_path = f"https://quay.io/api/v1/{org_name}/{cont_name}-{version}-{extension}"

    headers = {"content-type": "application/json", 
               "Authorization": f"{username} {token}"}
    data = {"description": readme}
    r = requests.put(repo_path, headers=headers, data=data)
    return r.status_code()
