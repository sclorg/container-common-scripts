#!/usr/bin/python3
import os
import re
import sys
from natsort import natsorted

distro_names = {
    "c9s": ["CentOS Stream 9", "quay.io/sclorg/%s-c9s"],
    "c10s": ["CentOS Stream 10", "quay.io/sclorg/%s-c10s"],
    "fedora": ["Fedora", "quay.io/fedora/%s"],
    "rhel8": ["RHEL 8", "registry.redhat.io/rhel8/%s"],
    "rhel9": ["RHEL 9", "registry.redhat.io/rhel9/%s"],
    "rhel10": ["RHEL 10", "registry.redhat.io/rhel10/%s"],
}
version_regex = re.compile(r"^VERSIONS\s*=\s*(.*)$")
docker_file_regex = re.compile(r"(?<=Dockerfile\.).+")
exclude_file_regex = re.compile(r"(?<=\.exclude-).+")

table_regex = re.compile(
    r"(<!--\nTable start\n-->\n).*?(<!--\nTable end\n-->\n)", re.DOTALL
)


def main(name: str) -> None:
    docker_distros = {}
    all_distros = set()

    versions = _get_versions()
    if len(versions) == 0:
        print(
            "No VERSIONS variable found in Makefile, please make sure the syntax is correct",
            file=sys.stderr,
        )
        exit(2)

    # goes through all the versions and gets their dockerfile
    # and 'exclude-' distros
    for version in versions:
        files = "\n".join(os.listdir(version))
        available_distros: set[str] = set(re.findall(docker_file_regex, files))
        exclude_distros = set(re.findall(exclude_file_regex, files))
        unsupported = available_distros - distro_names.keys()
        if len(unsupported) > 0:
            print(
                f"WARNING: Distros {list(unsupported)} in version "
                + f"{version} are unsupported and Dockerfiles for them should be deleted",
                file=sys.stderr,
            )
        all_distros |= available_distros
        docker_distros[version] = (
            available_distros - exclude_distros
        ) & distro_names.keys()
    all_distros &= distro_names.keys()

    table = _create_table(natsorted(all_distros), versions, docker_distros, name)
    _replace_in_readme(table)


# gets the versions of the container from the Makefile
def _get_versions() -> list[str]:
    try:
        with open("Makefile", "r") as f:
            for line in f:
                match = re.search(version_regex, line)
                if match:
                    return match.group(1).split(" ")
    except Exception as e:
        print(
            f"An exception occurred when trying to read the Makefile: {e}",
            file=sys.stderr,
        )
        exit(1)
    return []


# generates the table string
def _create_table(
    distros: list[str],
    versions: list[str],
    docker_distros: dict[str, set[str]],
    name: str,
) -> str:
    # table header
    table = f"||{'|'.join([distro_names[distro][0] for distro in distros])}|\n"
    # prints the table column separator
    # align the versions to left and ticks to center
    table += f"|:--|{':--:|' * len(distros)}\n"
    for version in versions:
        # prints the version line header
        table += f"|{version}"
        # goes over the distros and prints a tick and repo address
        # if the image is available
        for distro in distros:
            table += "|"
            if distro in docker_distros[version]:
                table += (
                    "<details><summary>✓</summary>"
                    + f"`{distro_names[distro][1] % (name + "-" + version.replace('.', ''))}`</details>"
                )
        # end the table line
        table += "|\n"
    return table


# reads the README.md, finds the Table start and Table end comments
# replaces any string between them with the table string
# and writes it back to the README.md file
def _replace_in_readme(table: str) -> None:
    try:
        with open("README.md", "r+") as readme:
            original_readme = readme.read()
            new_readme, subs = re.subn(table_regex, f"\\1{table}\\2", original_readme)
            if subs == 0:
                print(
                    "The Table start and Table end tag not found, not modifying README.md",
                    file=sys.stderr,
                )
                exit(0)
            if subs > 1:
                print(
                    "More than one Table start and Table end tag found, not modifying README.md",
                    file=sys.stderr,
                )
                exit(0)
            readme.seek(0)
            readme.write(new_readme)
            readme.truncate()
    except Exception as e:
        print(f"An error occurred while trying to open README.md: {e}", file=sys.stderr)
        exit(1)


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) != 1:
        print("Usage: ./generate_table.py NAME\nThe NAME of the image is required")
        exit(2)
    main(args[0])
