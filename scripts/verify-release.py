#!/usr/bin/env python3
import argparse
import hashlib
from pathlib import Path
import re


def read_metadata(path):
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 65536:
        raise ValueError(f"Metadata must be a nonempty regular file under 64 KiB: {path.name}")
    return path.read_text(encoding="utf-8")


def verify_release(directory, version):
    if not re.fullmatch(r"v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:[.-][A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?", version):
        raise ValueError("Invalid release version")
    directory = Path(directory)
    release_files = set()
    for architecture, platform in (("arm64", "AppleSilicon"), ("x86_64", "Intel")):
        stem = f"MediaForge-{version}-{architecture}"
        expected = {f"MediaForge-macOS-14+-{platform}.zip", f"MediaForge-macOS-14+-{platform}.dmg",
                    f"{stem}-FFmpeg-source.zip", f"{stem}-status.txt"}
        release_files.update(expected | {f"{stem}-SHA256SUMS.txt"})
        entries = {}
        for line in read_metadata(directory / f"{stem}-SHA256SUMS.txt").splitlines():
            match = re.fullmatch(r"([0-9a-f]{64}) [ *](.+)", line)
            if not match or match[2] in entries or match[2] not in expected:
                raise ValueError(f"Invalid or unexpected checksum entry: {line}")
            entries[match[2]] = match[1]
        if set(entries) != expected:
            raise ValueError(f"Incomplete artifact manifest for {architecture}")
        for name, digest in entries.items():
            artifact = directory / name
            if artifact.is_symlink() or not artifact.is_file() or artifact.stat().st_size == 0:
                raise ValueError(f"Artifact must be a nonempty regular file: {name}")
            checksum = hashlib.sha256()
            with artifact.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    checksum.update(chunk)
            actual = checksum.hexdigest()
            if actual != digest:
                raise ValueError(f"Checksum mismatch: {name}")
        status = {}
        for line in read_metadata(directory / f"{stem}-status.txt").splitlines():
            key, separator, value = line.partition("=")
            if not separator or key in status:
                raise ValueError(f"Malformed release status: {line}")
            status[key] = value
        if set(status) != {"architecture", "version", "signing", "notarized"}:
            raise ValueError("Incomplete or unexpected release status fields")
        if status["architecture"] != architecture or status["version"] != version:
            raise ValueError("Release status architecture/version mismatch")
        if status["signing"] not in {"ad-hoc", "developer-id"} or status["notarized"] not in {"true", "false"}:
            raise ValueError("Invalid signing/notarization status")
        if status["notarized"] == "true" and status["signing"] != "developer-id":
            raise ValueError("Notarization requires Developer ID signing")
    unexpected = {path.name for path in directory.glob("MediaForge-*")} - release_files
    if unexpected:
        raise ValueError("Unverified release assets: " + ", ".join(sorted(unexpected)))


def main():
    parser = argparse.ArgumentParser(description="Verify both architecture release artifact sets")
    parser.add_argument("directory", type=Path)
    parser.add_argument("version")
    arguments = parser.parse_args()
    try:
        verify_release(arguments.directory, arguments.version)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print("Both architecture artifact sets and release metadata verified.")


if __name__ == "__main__":
    main()
