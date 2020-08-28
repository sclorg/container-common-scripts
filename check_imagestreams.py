#!/bin/env python3

import sys
import json
import logging

from pathlib import Path
from typing import Dict

IMAGESTREAMS_DIR: str = "imagestreams"


class ImageStreamChecker(object):
    version: str = ""
    results: Dict = {}

    def __init__(self, version: str):
        self.version = version

    def load_json_file(self, filename: Path):
        with open(str(filename)) as f:
            return json.load(f)

    def check_version(self, json_dict: Dict):
        res = []
        for tags in json_dict["spec"]["tags"]:
            # The name can be"<stream>" or "<stream>-elX" or "<stream>-ubiX"
            if (tags["name"] == self.version or
                    tags["name"].startswith(self.version + '-')):
                res.append(tags)
        return res

    def check_latest_tag(self, json_dict: Dict):
        latest_tag_correct: bool = False
        for tags in json_dict["spec"]["tags"]:
            if tags["name"] != "latest":
                continue
            # The latest can link to either "<stream>" or "<stream>-elX" or "<stream>-ubiX"
            if tags["from"]["name"] == self.version or tags["from"]["name"].startswith(self.version + '-'):
                latest_tag_correct = True
        return latest_tag_correct

    def check_imagestreams(self):
        p = Path(".")
        json_files = p.glob(f"{IMAGESTREAMS_DIR}/*.json")
        if not json_files:
            print(f"No json files present in {IMAGESTREAMS_DIR}.")
            return 0
        for f in json_files:
            print(f"Checking file {str(f)}.")
            json_dict = self.load_json_file(f)
            if not (self.check_version(json_dict) and self.check_latest_tag(json_dict)):
                print(f"The latest version is not present in {str(f)} or in latest tag.")
                self.results[f] = False
        if self.results:
            return 1
        print("Imagestreams contains the latest version.")
        return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        logging.fatal("%s: %s", sys.argv[0], "VERSION as an argument was not provided")
        sys.exit(1)

    print(f"Version to check is {sys.argv[1]}.")
    isc = ImageStreamChecker(version=sys.argv[1])
    sys.exit(isc.check_imagestreams())

