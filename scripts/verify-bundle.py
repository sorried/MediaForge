#!/usr/bin/env python3
import hashlib
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys


def output(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, timeout=60)


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def version_tuple(version):
    parts = [int(part) for part in version.split(".")]
    return tuple((parts + [0, 0, 0])[:3])


def verify_engine_version(version_text, tool, expected):
    match = re.search(rf"^{re.escape(tool)} version ([^\s]+)", version_text, re.M)
    require(match is not None and match.group(1) == expected,
            f"Bundled {tool} does not match pinned version {expected}")


def verify_license_configuration(configuration):
    flags = set(shlex.split(configuration))
    for flag in ("--disable-gpl", "--disable-nonfree", "--disable-version3", "--disable-autodetect", "--disable-network"):
        require(flag in flags, f"Missing license isolation flag {flag}")
    require(not any(re.fullmatch(r"--enable-(?:gpl|nonfree|version3|network|lib\w+)(?:=.*)?", flag) for flag in flags),
            "Unapproved FFmpeg license/external library configuration")


def verify_deployment_platform(load_commands, binary):
    commands = re.findall(r"cmd LC_(BUILD_VERSION|VERSION_MIN_MACOSX)\b(.*?)(?=Load command|\Z)", load_commands, re.S)
    require(bool(commands), f"Missing deployment load command: {binary}")
    for command, block in commands:
        field = "minos" if command == "BUILD_VERSION" else "version"
        minimum = re.search(rf"\b{field}\s+(\d+\.\d+(?:\.\d+)?)\b", block)
        require(minimum is not None, f"Missing deployment minimum: {binary}")
        require(version_tuple(minimum.group(1)) <= (14, 0, 0),
                f"Deployment target exceeds macOS 14: {binary}")
        if command == "BUILD_VERSION":
            match = re.search(r"\bplatform\s+(\S+)", block)
            require(match is not None and match.group(1) in {"1", "macos", "MACOS"},
                    f"Non-macOS deployment platform: {binary}")


def codec_names(table):
    return {parts[1] for line in table.splitlines()
            if len(parts := line.split()) >= 2 and re.fullmatch(r"[VAS][A-Z.]{5}", parts[0])}


def verify_encoders(encoders):
    names = codec_names(encoders)
    for encoder in ("aac", "h264_videotoolbox", "hevc_videotoolbox", "png", "mjpeg"):
        require(encoder in names, f"Missing encoder {encoder}")
    require(not names.intersection({"libx264", "libx265"}), "GPL encoder found")


def verify_decode_components(decoders, muxers):
    decoder_names = codec_names(decoders)
    muxer_names = {name for line in muxers.splitlines()
                   if len(parts := line.split()) >= 2 and parts[0] == "E"
                   for name in parts[1].split(",")}
    for decoder in ("h264", "hevc", "aac", "png", "mjpeg", "mpeg4"):
        require(decoder in decoder_names, f"Missing output-verification decoder {decoder}")
    require("null" in muxer_names, "Missing output-verification null muxer")


def resolve_dependency(dependency, binary, executable, contents):
    if dependency.startswith("@loader_path/"):
        resolved = binary.parent / dependency.removeprefix("@loader_path/")
    elif dependency.startswith("@executable_path/"):
        resolved = executable.parent / dependency.removeprefix("@executable_path/")
    else:
        raise SystemExit(f"Non-system or unresolved dependency: {binary}: {dependency}")
    require(resolved.resolve().is_relative_to(contents.resolve()) and resolved.is_file(),
            f"Unresolved bundle dependency: {binary}: {dependency}")
    return resolved


def verify(app, architecture):
    require(sys.platform == "darwin", "Bundle verification requires macOS Mach-O tools.")
    require(architecture in {"arm64", "x86_64"}, "Unsupported architecture")
    app = app.resolve(strict=True)
    contents = app / "Contents"
    with (contents / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(version_tuple(info.get("LSMinimumSystemVersion", "99")) <= (14, 0, 0),
            "App minimum OS exceeds macOS 14")
    executable = contents / "MacOS" / info["CFBundleExecutable"]
    tools = contents / "Resources" / "Tools"
    licenses = contents / "Resources" / "Licenses" / "FFmpeg"
    require(executable.is_file(), "Missing application executable")
    for name in ("ffmpeg", "ffprobe"):
        require((tools / name).is_file(), f"Missing bundled {name}")
    binaries = []
    for path in contents.rglob("*"):
        if path.is_symlink():
            require(path.resolve().is_relative_to(contents), f"Escaping symlink: {path}")
            require(path.exists(), f"Broken symlink: {path}")
        if path.is_file() and not path.is_symlink() and "Mach-O" in output("file", "-b", str(path)):
            binaries.append(path)
    for required_binary in (executable, tools / "ffmpeg", tools / "ffprobe"):
        require(required_binary in binaries and required_binary.stat().st_mode & 0o111,
                f"Required executable is not an executable Mach-O: {required_binary}")
    for binary in binaries:
        require(output("lipo", "-archs", str(binary)).strip() == architecture,
                f"Incorrect architecture: {binary}")
        load_commands = output("otool", "-l", str(binary))
        verify_deployment_platform(load_commands, binary)
        dependencies = output("otool", "-L", str(binary)).splitlines()[1:]
        if binary.suffix == ".dylib":
            dependencies = dependencies[1:]
        for line in dependencies:
            dependency = line.strip().split(" (", 1)[0]
            if dependency.startswith(("/System/Library/", "/usr/lib/")):
                continue
            if dependency.startswith("@rpath/libswift") and binary == executable:
                # Swift's stable ABI runtime is part of macOS 14; Xcode emits its OS rpath.
                require("/usr/lib/swift" in load_commands, f"Missing Swift system rpath: {binary}")
                continue
            process_executable = binary if binary in (tools / "ffmpeg", tools / "ffprobe") else executable
            if binary.is_relative_to(tools / "lib"):
                process_executable = tools / "ffmpeg"
            resolve_dependency(dependency, binary, process_executable, contents)
        require("/opt/homebrew" not in load_commands and "/usr/local/" not in load_commands,
                f"Homebrew/build-host load command: {binary}")
    ffmpeg = str(tools / "ffmpeg")
    configuration = output(ffmpeg, "-hide_banner", "-buildconf")
    verify_license_configuration(configuration)
    license_text = output(ffmpeg, "-L")
    require("Lesser General Public" in license_text and "version 2.1" in license_text, "Unexpected FFmpeg runtime license")
    encoders = output(ffmpeg, "-hide_banner", "-encoders")
    verify_encoders(encoders)
    decoders = output(ffmpeg, "-hide_banner", "-decoders")
    muxers = output(ffmpeg, "-hide_banner", "-muxers")
    verify_decode_components(decoders, muxers)
    probe_version = output(str(tools / "ffprobe"), "-version")
    pin = dict(line.split("=", 1) for line in (Path(__file__).resolve().parent.parent / "Config" / "ffmpeg.env").read_text().splitlines())
    verify_engine_version(output(ffmpeg, "-version"), "ffmpeg", pin["FFMPEG_VERSION"])
    verify_engine_version(probe_version, "ffprobe", pin["FFMPEG_VERSION"])
    archive = licenses / f"ffmpeg-{pin['FFMPEG_VERSION']}.tar.xz"
    require(archive.is_file(), "Missing corresponding source archive")
    require(hashlib.sha256(archive.read_bytes()).hexdigest() == pin["FFMPEG_SHA256"], "Source archive checksum mismatch")
    shipped_pin = licenses / "ffmpeg.env"
    require(shipped_pin.is_file(), "Missing bundled source pin")
    source_pin = dict(line.split("=", 1) for line in shipped_pin.read_text().splitlines())
    require(source_pin == pin, "Bundled source pin differs from build pin")
    for name in ("COPYING.LGPLv2.1", "LICENSE.md", "config.mak", "config.h", "CHANGES.txt", "build-ffmpeg.sh", "ffmpeg.env"):
        require((licenses / name).is_file(), f"Missing redistribution record {name}")
    print(f"Verified {len(binaries)} Mach-O files, {architecture}, macOS 14, LGPL FFmpeg and corresponding source.")


if __name__ == "__main__":
    require(len(sys.argv) == 3, "Usage: verify-bundle.py MediaForge.app arm64|x86_64")
    verify(Path(sys.argv[1]), sys.argv[2])
