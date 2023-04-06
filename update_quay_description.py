import re
import os
import requests
import sys
from typing import List, Optional


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


def get_quay_extensions(version_dir: str, org: str) -> Optional[List[str]]:
    """
    Return list of extensions for which given version of container is available 
    in given quay organization (so far supports sclorg and centos7)
    """
    org_dockerfile_patterns = {"sclorg": "Dockerfile.c[89]s",
                               "centos7": "Dockerfile.centos7"}
    
    pattern = org_dockerfile_patterns.get(org, "")
    if pattern == "":
        return None
    
    files = os.listdir(version_dir)
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
                if i + 3 >= len(lines):
                    break
                output_lines = lines[i + 3:]  # Skip seperator line and empty line
                return "".join(output_lines)
    return None


def update_description(username: str, token: str, org_name: str, extension: str,
                       version: str, cont_name: str, readme: str) -> int:
    repo_path = f"{org_name}/{cont_name}-{version}-{extension}"
    print(f"Now updating description of {repo_path}")
    # Remove dot from version
    if "." in version:
        version = version.replace(".", "")
    
    api_request_path = f"https://quay.io/api/v1/{repo_path}"

    headers = {"content-type": "application/json", 
               "Authorization": f"{username} {token}"}
    data = {"description": readme}
    r = requests.put(api_request_path, headers=headers, data=data)
    return r.status_code()


if __name__ == "__main__":
    if len(sys.argv != 4):
        print("Organization name, username and token are required as arguments", file=sys.stderr)
        sys.exit(1)

    org_name = sys.argv[1]
    username = sys.argv[2]
    token = sys.argv[3]

    if org_name not in {"sclorg", "centos7"}:
        print("Invalid organization name", file=sys.stderr)
    
    versions = load_makefile_var("VERSIONS")
    cont_name = load_makefile_var("BASE_IMAGE_NAME")
    if versions is None or cont_name is None:
        print("Makefile has invalid format", file=sys.stderr)
        sys.exit(1)

    cont_name = cont_name[0]
    for version in versions:
        version_dir = f"../{version}"
        readme = load_readme(version_dir)
        if readme is None:
            print("Invalid README format", file=sys.stderr)

        extensions = get_quay_extensions(version_dir, org_name)
        for extension in extensions:
            update_description(username, token, org_name, extension,
                               version, cont_name, readme)
