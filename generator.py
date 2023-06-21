#!/usr/bin/env python3

import argparse
import re
from collections import defaultdict
from os import chmod, makedirs, mkdir, symlink, unlink
from pathlib import Path
from shutil import copy2, rmtree
from subprocess import CalledProcessError, check_output
from typing import Dict, List, TextIO

import yaml
from distgen.multispec import Multispec


def run_distgen(
    src: str,
    dest: Path,
    multispec_path: str,
    distro_config: str,
    version: str,
) -> None:
    cmd = [
        "dg",
        "--multispec",
        multispec_path,
        "--template",
        src,
        "--distro",
        distro_config,
        "--multispec-selector",
        f"version={version}",
        "--output",
        str(dest),
    ]

    try:
        check_output(cmd)
    except CalledProcessError as e:
        # Exit code 2 is a special code for non existing matrix combinations
        # It's not an actual error, hence don't print out its error message
        if e.returncode != 2:
            print("[ERROR] distgen failed:", e)


def get_version_distro_mapping(
    multispec_file: TextIO,
) -> Dict[str, List[str]]:
    """Get all combinations from multispec file like:

    [{"distro": "rhel-8-x86_64.yaml", "version": "3.9"},
     {"distro": "rhel-8-x86_64.yaml", "version": "3.8"},
     {"distro": "centos-7-x86_64.yaml", "version": "3.8"},
     {"distro": "centos-stream-9-x86_64.yaml", "version": "3.9"}]

    and transfer them to:

    {"3.8": ["rhel-8-x86_64.yaml", "centos-7-x86_64.yaml"],
     "3.9": ["rhel-8-x86_64.yaml", "centos-stream-9-x86_64.yaml"]}
    """
    multispec_yaml = yaml.load(multispec_file.read(), Loader=yaml.SafeLoader)
    multispec = Multispec(data=multispec_yaml)
    mapping = defaultdict(list)
    for combination in multispec.get_all_combinations():
        mapping[combination["version"]].append(combination["distro"])
    return mapping


def filename_to_distro_config(
    filename: str, version: str, mapping: Dict[str, List[str]]
) -> str:
    """Find distgen distro config from a filename.

    This is usually needed only for dockerfiles.
    - Dockerfile.rhelXX → rhel-XX-x86_64.yaml
    - Dockerfile.cXXs → centos-stream-XX-x86_64.yaml
    - Dockerfile.centosX → centos-X-x86_64.yaml
    - Dockerfile.fedora → the newest fedora-XX-x86_64.yaml

    If not found, empty string is returned indicating that the
    combination of distro and version is not included
    in distgen configuration (multispec).
    """
    rhel_match = re.match(r".*\.rhel(\d+)$", filename)
    centos_stream_match = re.match(r".*\.c(\d+)s$", filename)
    centos_match = re.match(r".*\.centos(\d+)$", filename)

    if rhel_match:
        config = f"rhel-{rhel_match.group(1)}-x86_64.yaml"
    elif centos_stream_match:
        config = f"centos-stream-{centos_stream_match.group(1)}-x86_64.yaml"
    elif centos_match:
        config = f"centos-{centos_match.group(1)}-x86_64.yaml"
    elif filename.endswith(".fedora"):
        sorted_configs = sorted(c for c in mapping[version] if c.startswith("fedora"))
        if len(sorted_configs) > 1:
            raise RuntimeError(
                "Multiple Fedora configs for single version exist:", sorted_configs
            )
        elif len(sorted_configs) == 1:
            config = sorted_configs[0]
        else:
            config = ""
    else:
        raise RuntimeError(
            f"File {filename} does not match any of the known suffixes: .rhelXX, .cXs, .centosX or .fedora"
        )

    return config


def parse_args() -> argparse.Namespace:
    arg_parser = argparse.ArgumentParser(
        description="Helper script for distgen in S2I container images"
    )
    arg_parser.add_argument(
        "-v",
        "--version",
        dest="version",
        help="Version of image to generate sources for",
        required=True,
    )
    arg_parser.add_argument(
        "-m",
        "--manifest",
        dest="manifest",
        help="Path to manifest YAML file",
        type=argparse.FileType("r"),
        required=True,
    )
    arg_parser.add_argument(
        "-s",
        "--multispec",
        dest="multispec",
        help="Path to multispec YAML file",
        type=argparse.FileType("r"),
        required=True,
    )

    return arg_parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = yaml.load(args.manifest, Loader=yaml.SafeLoader)
    version_distro_map = get_version_distro_mapping(args.multispec)

    rmtree(args.version, ignore_errors=True)
    mkdir(args.version)

    for section in manifest:
        for spec in manifest[section]:
            # Prepend {version}/ to all destination paths
            spec["dest"] = Path(args.version) / spec["dest"]

            if not spec["dest"].parent.exists():
                makedirs(spec["dest"].parent)

            if section == "COPY_RULES":
                print(f"CP\t{spec['src']} → {spec['dest']}")
                copy2(spec["src"], spec["dest"])

            elif section == "SYMLINK_RULES":
                print(f"LN\t{spec['src']} → {spec['dest']}")
                symlink(spec["src"], spec["dest"])
                # Remove dead symlinks
                # This is needed for backward-compatible symlink Dockerfile → Dockerfile.centos7
                # because we want to delete it when Dockerfile.centos7 does not exist.
                # When we drop Centos 7, we can stop doing this.
                # In the meantime, if you need to create a dead symlink on purpose,
                # use check_symlink: false in manifest.yml config file.
                # It's easier to remove dead symlinks than checking
                # the relative path of the destination beforehand.
                if spec.get("check_symlink", True) and not spec["dest"].exists():
                    print(f"WARN: {spec['dest']} is a dead symlink, removed.")
                    unlink(spec["dest"])

            elif section == "DISTGEN_RULES":
                print(f"DG\t{spec['src']} → {spec['dest']}")
                # For common files like README.md or test/run
                # we need to run distgen only once and it does not
                # matter which distro config we use.
                # Sorting is here to make it deterministic.
                distro_config = sorted(version_distro_map[args.version])[-1]
                run_distgen(
                    spec["src"],
                    spec["dest"],
                    args.multispec.name,
                    distro_config,
                    args.version,
                )

            elif section == "DISTGEN_MULTI_RULES":
                distro_config = filename_to_distro_config(
                    spec["dest"].name, args.version, version_distro_map
                )
                if distro_config:
                    print(f"DGM\t{spec['src']} → {spec['dest']}")
                    run_distgen(
                        spec["src"],
                        spec["dest"],
                        args.multispec.name,
                        distro_config,
                        args.version,
                    )

            else:
                print("[WARNING] Unexpected section:", section)

            if "mode" in spec:
                chmod(spec["dest"], int(spec["mode"], base=8))
                pass


if __name__ == "__main__":
    main()
