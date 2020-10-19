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


import sys
import json
import logging
import copy

from pathlib import Path
from typing import Dict


class UpdateImageStream(object):
    version: str = ""
    json_file: str = ""
    image_registry: str = ""

    def __init__(self, version: str, json_file: str, image_registry: str):
        self.version = version
        self.json_file = json_file
        self.image_registry = image_registry

    def load_json_file(self, filename: Path):
        with open(str(filename)) as f:
            return json.load(f)

    def save_json_file(self, filename: Path, json_dict: Dict):
        update_file = f"{filename.parent}/updated-{filename.name}"
        with open(str(update_file), "w") as f:
            json.dump(json_dict, f, indent=5)
        print(f"Imagestream {filename} was updated to "
              f"{update_file} "
              f"with new {self.image_registry}")

    def create_or_update_version_tag(self, json_dict: Dict):
        found_tag: bool = False
        template_dict: Dict = None
        for tag in json_dict["spec"]["tags"]:
            if tag["name"] == "latest":
                continue
            if not template_dict:
                template_dict = copy.deepcopy(tag)
            if tag["name"] != self.version:
                continue
            print(f"Tag {self.version} is present in {self.json_file}.")
            found_tag = True
            tag["from"]["name"] = self.image_registry
        if not found_tag:
            print(f"Tag {self.version} is not present in {self.json_file}.")
            print(f"Tag is created based on {template_dict['name']}")
            template_dict["name"] = f"{self.version}"
            template_dict["from"]["name"] = self.image_registry
            json_dict["spec"]["tags"].append(template_dict)
        return json_dict

    def update(self):
        p = Path.cwd()
        json_file = p / self.json_file
        if not json_file.exists():
            print(f"Json file {json_file} does not exist.")
            return 1
        json_dict = self.load_json_file(json_file)
        json_dict = self.create_or_update_version_tag(json_dict=json_dict)
        self.save_json_file(json_file, json_dict)
        return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        logging.fatal(f"Correct usage for {sys.argv[0]} is")
        logging.fatal("update_imagestreams.py "
                      "<VERSION> <JSON_FILE> <NEW_IMAGE_REGISTRY>")
        sys.exit(1)

    print(f"Update imagestream for test with our registry.")
    print(f"Version: {sys.argv[1]}, json file {sys.argv[2]}, image_registry {sys.argv[3]}")
    uis = UpdateImageStream(
        version=sys.argv[1],
        json_file=sys.argv[2],
        image_registry=sys.argv[3],
    )
    sys.exit(uis.update())
