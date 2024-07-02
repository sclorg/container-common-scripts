#!/bin/env python3

# MIT License
#
# Copyright (c) 2018-2019 Red Hat, Inc.

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import os
import subprocess
import sys
import shutil
import logging
from typing import List, Any, Optional
from pathlib import Path
from contextlib import contextmanager
from os import getenv
from tempfile import TemporaryDirectory
from collections import namedtuple


if getenv("DEBUG_MODE") == "true":
    logging.basicConfig(format="%(levelname)s:%(message)s", level=logging.DEBUG)
else:
    logging.basicConfig(format="%(message)s", level=logging.INFO)


def run_cmd(
    cmd: str,
    return_output: bool = False,
    ignore_error: bool = False,
    shell: bool = False,
) -> Any:
    """
    Run provided command on host system using the same user as invoked this code.
    Raises subprocess.CalledProcessError if it fails.
    :param cmd: list or str
    :param return_output: bool, return output of the command
    :param ignore_error: bool, do not fail in case nonzero return code
    :param shell: bool, run command in shell
    :param kwargs: pass keyword arguments to subprocess.check_* functions; for more info,
            please check `help(subprocess.Popen)`
    :return: None or str
    """
    logging.debug(f"command: {cmd}")
    try:
        if return_output:
            return subprocess.check_output(
                cmd, stderr=subprocess.STDOUT, universal_newlines=True, shell=shell
            )
        else:
            return subprocess.check_call(cmd, shell=shell)
    except subprocess.CalledProcessError as cpe:
        if ignore_error:
            if return_output:
                return cpe.output
            else:
                return cpe.returncode
        else:
            logging.error(
                f"ERROR: failed with code {cpe.returncode} and output:\n{cpe.output}"
            )
            raise cpe


@contextmanager
def cwd(target: str) -> Any:
    """
    Manage cwd in a pushd/popd fashion.
    Usage:
    with cwd(tmpdir):
      do something in tmpdir
    """
    curdir = os.getcwd()
    os.chdir(target)
    try:
        yield
    finally:
        os.chdir(curdir)


# ['rh-nodejs14 nodejs-14 s2i-nodejs-container https://github.com/sclorg/s2i-nodejs-container.git 14 rhscl-3.6-rhel-7']
ImageInfo = namedtuple(
    "ImageInfo",
    ["downstream_name", "image_name", "upstream_name", "git_url", "ver", "branch"],
)


class BetkaGenerator(object):
    def __init__(self) -> None:
        self.os_env: Optional[str] = getenv("OS")
        self.versions_env: Optional[str] = getenv("VERSIONS")
        self.cwt_docker_image: Optional[str] = getenv("CWT_DOCKER_IMAGE")
        self.downstream_branch: Optional[str] = getenv("DOWNSTREAM_BRANCH")
        self.clone_url: Optional[str] = getenv("CLONE_URL")
        self.cur_dir: Path = Path.cwd()
        self.cwt_command = "cwt"
        self.cwt_config = "default.yaml"
        self.upstream_image_name = self.cur_dir.name
        self.ups_sources = ""

    def check_requirements(self) -> bool:
        if not self.cwt_docker_image:
            msg = """
Docker image for generating dist-git sources for RHEL has to be specified.
Ask pkubat@redhat.com, hhorak@redhat.com or phracek@redhat.com for the name.
            """
            logging.info(msg)
            return False
        if self.os_env == "fedora":
            if not self.downstream_branch:
                msg = """The DOWNSTREAM_BRANCH parameter is not specified.
Sources are synced to main branch. If you want to change it, specify DOWNSTREAM_BRANCH parameter
like 'make betka TARGET=fedora DOWNSTREAM_BRANCH=f32'
                """
                logging.info(msg)
                self.cwt_config = "default.yaml"
            else:
                # Examples config for F34 is f34.yaml
                # For more configs see
                # https://github.com/sclorg/container-workflow-tool/tree/master/container_workflow_tool/config
                self.cwt_config = f"{self.downstream_branch}.yaml"
        else:
            if not self.downstream_branch:
                msg = """
DOWNSTREAM_BRANCH is not specified.
Examples:
rhel-9.4.0 for RHEL9
rhel-8.8.0 for RHEL8
For more details ask pkubat@redhat.com or phracek@redhat.com
                """
                logging.info(msg)
                return False
            self.cwt_command = "rhcwt"
        git_config = Path.home() / ".gitconfig"
        if not git_config.exists():
            msg = f"""
File {git_config} is mandatory for using CWT tool.
Create it by commands:
git config --global user.mail <your mail>
git config --global user.name <your name>
            """
            logging.info(msg)
            return False
        return True

    def delete_generated_dirs(self, ver: str) -> Any:
        results_dir: Path = self.cur_dir / f"results-{ver}"
        if results_dir.exists():
            logging.debug(
                f"results-{ver} dir was previously generated. Delete it to generate new sources."
            )
            shutil.rmtree(results_dir)

    def get_valid_images(self, ver: str) -> List[str]:
        if self.os_env != "fedora":
            if not self.convert_branch_to_cwt_tool():
                return []
        cmd = f"""docker run -it --rm {self.cwt_docker_image} bash -c '{self.cwt_command} \
--config={self.cwt_config} utils listupstream'
"""
        docker_output = run_cmd(cmd, return_output=True, shell=True)
        valid_images = []
        for line in docker_output.split("\n"):
            # Fields are:
            # python-27 python-27 s2i-python-container https://github.com/sclorg/s2i-python-container.git 2.7 rhel-8.4.0
            if self.upstream_image_name in line and ver == line.split(" ")[4]:
                valid_images.append(line)
        logging.debug(f"Valid images {valid_images}")
        return valid_images

    def convert_branch_to_cwt_tool(self) -> bool:
        assert isinstance(self.downstream_branch, str)
        fields = self.downstream_branch.split("-")
        if self.os_env == "rhel8":
            release_fields = fields[1].split(".")
            self.cwt_config = (
                f"rhel8.yaml:{fields[0]}{release_fields[0]}.{release_fields[1]}"
            )
        elif self.os_env == "rhel9":
            release_fields = fields[1].split(".")
            self.cwt_config = (
                f"rhel9.yaml:{fields[0]}{release_fields[0]}.{release_fields[1]}"
            )
        else:
            logging.info(
                f"No proper OS target was selected {self.os_env}. Possible are 'rhel8, and rhel9."
            )
            return False
        return True

    def clone_and_switch_to_branch(self, downstream_name: str, branch_name: str) -> Any:
        cmd = f"git clone --branch {branch_name} {self.clone_url}/{downstream_name} {self.betka_tmp_dir.name}/results"
        run_cmd(cmd, shell=True)

    def copy_upstream_sources(self) -> Any:
        p = Path(f"{self.betka_tmp_dir.name}/{self.upstream_image_name}")
        if p.exists():
            shutil.rmtree(p)
        logging.debug(f"Upstream sources are copied to {p}")
        shutil.copytree(self.cur_dir, f"{p}", symlinks=True)

    def generate_sources(self, downstream_name: str) -> Any:
        cmd = f"""docker run -it --rm -v {Path.home()}/.gitconfig:/root/.gitconfig:ro,Z \
-v {self.betka_tmp_dir.name}:{self.betka_tmp_dir.name}:rw,Z -e WORKDIR={self.betka_tmp_dir.name} \
-e DOWNSTREAM_IMAGE_NAME={downstream_name} \
-e UPSTREAM_IMAGE_NAME={self.upstream_image_name} {self.cwt_docker_image}
"""
        run_cmd(cmd, shell=True)

    def copy_generated_source(self, ver: str) -> Any:
        shutil.copytree(
            Path(f"{self.betka_tmp_dir.name}/results"),
            self.cur_dir / f"results-{ver}",
            symlinks=True,
        )

    def convert_sources(self) -> int:
        generated_sources = []
        if not self.versions_env:
            return 1
        for ver in self.versions_env.split():
            with cwd(str(self.cur_dir / ver)):
                self.delete_generated_dirs(ver)
                valid_images = self.get_valid_images(ver)
                if not valid_images:
                    logging.info(
                        f"'{self.cwt_command}' did not detect any valid images by command 'utils listupstream'."
                    )
                    return 0
                for img in valid_images:
                    self.betka_tmp_dir = TemporaryDirectory()
                    img_info = ImageInfo._make(img.split())
                    self.ups_sources = (
                        f"{self.betka_tmp_dir.name}/{self.upstream_image_name}"
                    )
                    self.copy_upstream_sources()
                    self.clone_and_switch_to_branch(
                        downstream_name=img_info.downstream_name,
                        branch_name=img_info.branch,
                    )
                    self.generate_sources(downstream_name=img_info.downstream_name)
                    self.copy_generated_source(ver=img_info.ver)
                    generated_sources.append(f"results-{ver}")
                    self.betka_tmp_dir.cleanup()
        if generated_sources:
            logging.info(
                "Dist-git sources generated by 'make betka' are stored in this/these directories:"
            )
            logging.info("\n".join(generated_sources))
        return 0


if __name__ == "__main__":
    bg = BetkaGenerator()
    if not bg.check_requirements():
        sys.exit(1)
    sys.exit(bg.convert_sources())
