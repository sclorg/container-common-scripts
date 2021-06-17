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
import pathlib
import subprocess
import sys
import shutil

from typing import List
from pathlib import Path
from contextlib import contextmanager
from os import getenv
from tempfile import TemporaryDirectory


def run_cmd(cmd, return_output=False, ignore_error=False, shell=False, **kwargs):
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
    print(f"command: {cmd}")
    try:
        if return_output:
            return subprocess.check_output(
                cmd,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                shell=shell,
                **kwargs,
            )
        else:
            return subprocess.check_call(cmd, shell=shell, **kwargs)
    except subprocess.CalledProcessError as cpe:
        if ignore_error:
            if return_output:
                return cpe.output
            else:
                return cpe.returncode
        else:
            print(f"ERROR: failed with code {cpe.returncode} and output:\n{cpe.output}")
            raise cpe


@contextmanager
def cwd(target):
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


class BetkaGenerator(object):

    def __init__(self):
        self.betka_tmp_dir = None
        self.os_env: str = getenv("OS")
        self.versions_env: str = getenv("VERSIONS")
        self.cwt_docker_image: str = getenv("CWT_DOCKER_IMAGE")
        self.downstream_branch: str = getenv("DOWNSTREAM_BRANCH")
        self.clone_url: str = getenv("CLONE_URL")
        self.cur_dir: Path = Path.cwd()
        self.cwt_command = "cwt"
        self.cwt_config = "default.yaml"
        self.upstream_image_name = self.cur_dir.name
        self.ups_sources = ""

    def check_requirements(self) -> bool:
        if self.os_env == "centos7":
            msg = f"Target has to be specified.\n"\
                  "CentOS7 is not supported.\n"\
                  "e.g. make betka TARGET=fedora VERSIONS=XY\n"
            print(msg)
            return False
        if self.cwt_docker_image == "":
            msg = f"Docker image for generating dist-git sources for RHEL has to be specified.\n"\
                  "Ask pkubat@redhat.com, hhorak@redhat.com or phracek@redhat.com for the name."
            print(msg)
            return False
        if self.os_env == "fedora":
            if not self.downstream_branch:
                self.cwt_config = "default.yaml"
            else:
                # Examples config for F34 is f34.yaml
                # For more configs see
                # https://github.com/sclorg/container-workflow-tool/tree/master/container_workflow_tool/config
                self.cwt_config = f"{self.downstream_branch}.yaml"
        else:
            if not self.downstream_branch:
                msg = f"DOWNSTREAM_BRANCH is not specified.\n" \
                      f"Examples:\n" \
                      f"rhel-8.3.0 for RHEL8\n" \
                      f"rhscl-3.6-rhel7 for RHEL7\n" \
                      f"For more details ask pkubat@redhat.com or phracek@redhat.com\n"
                print(msg)
                return False
            self.cwt_command = "rhcwt"
        git_config = Path(pathlib.Path.home()) / ".gitconfig"
        if not git_config.exists():
            msg = f"File {git_config} is mandatory for using CWT tool." \
                  f"Create it by commands:" \
                  f"git config --global user.mail <your mail>" \
                  f"git config --global user.name <your name>"
            print(msg)
            return False
        return True

    def delete_generated_dirs(self, ver: str):
        results_dir: Path = self.cur_dir / f"results-{ver}"
        if results_dir.exists():
            print(f"Results dir {results_dir} already exists. Delete it.")
            shutil.rmtree(results_dir)

    def get_valid_images(self, ver) -> List[str]:
        if self.os_env != "fedora":
            self.convert_branch_to_cwt_tool()
        cmd = f"docker run -it --rm {self.cwt_docker_image} bash -c '{self.cwt_command}" \
              f" --config={self.cwt_config} utils listupstream'"
        docker_output = run_cmd(cmd, return_output=True, shell=True)
        valid_images = []
        for x in docker_output.split('\n'):
            # Fields are:
            # python-27 python-27 s2i-python-container https://github.com/sclorg/s2i-python-container.git 2.7 rhel-8.4.0
            if self.upstream_image_name in x and ver == x.split(' ')[4]:
                valid_images.append(x)
        print(f"Valid images {valid_images}")
        return valid_images

    def convert_branch_to_cwt_tool(self):
        fields = self.downstream_branch.split('-')
        if self.os_env == "rhel7":
            self.cwt_config = f"rhel7.yaml:{fields[0]}{fields[1].replace('.','')}"
        else:
            release_fields = fields[1].split('.')
            self.cwt_config = f"rhel8.yaml:{fields[0]}{release_fields[0]}.{release_fields[1]}"

    def check_parameters(self):
        if self.os_env == "fedora":
            msg = f"For generating dist-git sources to Fedora {self.cwt_docker_image} is used." \
                  f"'make betka' will try to sync main branch in Fedora land." \
                  f"If you want to change it then specify it by parameter DOWNSTREAM_BRANCH," \
                  f"like 'make betka TARGET=fedora DOWNSTREAM_BRANCH=f32'"
            print(msg)
        if self.os_env == "centos7":
            return 1

    def clone_and_switch_to_branch(self, downstream_name: str, branch_name: str):
        cmd = f"git clone {self.clone_url}/{downstream_name} {self.betka_tmp_dir.name}/results"
        run_cmd(cmd, shell=True)
        with cwd(f"{self.betka_tmp_dir.name}/results"):
            cmd = f"git checkout {branch_name}"
            run_cmd(cmd, shell=True)

    def copy_upstream_sources(self):
        p = Path(f"{self.betka_tmp_dir.name}/{self.upstream_image_name}")
        if not p.exists():
            print(f"Upstream sources are copied to {p}")
            shutil.copytree(self.cur_dir, f"{p}", symlinks=True)

    def generate_sources(self, downstream_name: str):
        cmd = f"docker run -it --rm -v {Path.home()}/.gitconfig:/root/.gitconfig:ro,Z " \
              f"-v {self.betka_tmp_dir.name}:{self.betka_tmp_dir.name}:rw,Z -e WORKDIR={self.betka_tmp_dir.name} " \
              f"-e DOWNSTREAM_IMAGE_NAME={downstream_name} " \
              f"-e UPSTREAM_IMAGE_NAME={self.upstream_image_name} {self.cwt_docker_image}"
        run_cmd(cmd, shell=True)

    def copy_generated_source(self, ver: str):
        shutil.copytree(self.ups_sources, self.cur_dir / f"results-{ver}", symlinks=True)

    def convert_sources(self):
        generated_sources = []
        if not self.versions_env:
            return 1
        for ver in self.versions_env.split(' '):
            with cwd(str(self.cur_dir / ver)):
                self.delete_generated_dirs(ver)
                valid_images = self.get_valid_images(ver)
                for img in valid_images:
                    self.betka_tmp_dir = TemporaryDirectory()
                    img_fields = img.split()
                    self.ups_sources = f"{self.betka_tmp_dir.name}/{self.upstream_image_name}"
                    self.copy_upstream_sources()
                    self.clone_and_switch_to_branch(downstream_name=img_fields[0], branch_name=img_fields[5])
                    self.generate_sources(downstream_name=img_fields[0])
                    self.copy_generated_source(ver=img_fields[4])
                    generated_sources.append(f"results-{ver}")
                    self.betka_tmp_dir.cleanup()
        if generated_sources:
            print("Dist-git sources generated by 'make betka' are stored in this/these directories:")
            print('\n'.join(generated_sources))


if __name__ == "__main__":
    bg = BetkaGenerator()
    if not bg.check_requirements():
        sys.exit(1)
    sys.exit(bg.convert_sources())
