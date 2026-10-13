#!/usr/bin/env python3
import argparse
import plistlib
from pathlib import Path
import re


def marketing_version(version):
    match = re.fullmatch(r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:[.-][A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?", version)
    if not match:
        raise ValueError("Expected a version such as 1.2.3 or v1.2.3-rc.1")
    return ".".join(match.groups())


def verify_app_version(plist_path, version):
    with Path(plist_path).open("rb") as stream:
        info = plistlib.load(stream)
    expected = marketing_version(version)
    if info.get("CFBundleShortVersionString") != expected:
        raise ValueError(f"Application version {info.get('CFBundleShortVersionString')!r} does not match release {expected}")
    return expected


def main():
    parser = argparse.ArgumentParser(description="Validate release and application versions")
    parser.add_argument("version")
    parser.add_argument("--plist", type=Path)
    args = parser.parse_args()
    try:
        version = verify_app_version(args.plist, args.version) if args.plist else marketing_version(args.version)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, str(error) + "\n")
    print(version)


if __name__ == "__main__":
    main()
