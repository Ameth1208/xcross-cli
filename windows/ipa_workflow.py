"""Prepare an unsigned IPA copy for the native XCross signing/install engine."""

import argparse
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import subprocess
import tempfile
import uuid
import zipfile

from ipa_inspect import PackageError, inspect_ipa


def prepare(ipa, destination):
    """Extract regular files only, rejecting links, traversal and oversized ZIPs."""
    modes = {}
    with zipfile.ZipFile(ipa) as archive:
        if sum(entry.file_size for entry in archive.infolist()) > 8 * 1024**3:
            raise PackageError("Uncompressed IPA exceeds 8 GiB")
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            if (path.is_absolute() or ".." in path.parts or "\\" in entry.filename
                    or any(":" in part for part in path.parts)):
                raise PackageError("Unsafe archive path")
            mode = entry.external_attr >> 16
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise PackageError("IPA contains links or special files; automatic signing refused")
            if not path.parts or path.parts[0] != "Payload":
                continue
            target = destination.joinpath(*path.parts)
            modes[entry.filename] = mode
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)
        apps = list((destination / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise PackageError("Expected one app")
        # XCross's plist mutation pipeline reads XML, including embedded bundles.
        for path in apps[0].rglob("Info.plist"):
            path.write_bytes(plistlib.dumps(plistlib.loads(path.read_bytes()), fmt=plistlib.FMT_XML))
        return apps[0], modes


def pack_signed(payload, output, modes):
    # Exclusive output creation protects both the input and any earlier result.
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(payload.rglob("*")):
            if path.is_symlink():
                raise PackageError("Signing generated a linked file")
            if not path.is_file():
                continue
            name = path.relative_to(payload.parent).as_posix()
            entry = zipfile.ZipInfo(name)
            entry.create_system = 3
            entry.external_attr = (modes.get(name) or (stat.S_IFREG | 0o755)) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            with path.open("rb") as source, archive.open(entry, "w") as target:
                shutil.copyfileobj(source, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--dart", required=True)
    parser.add_argument("--packages", required=True)
    parser.add_argument("--bridge", required=True)
    parser.add_argument("--udid", required=True)
    args = parser.parse_args()
    try:
        report = inspect_ipa(args.ipa)
        if report["signature"] != "missing" or report["issues"] != ["missing_signature"]:
            raise PackageError("Automatic signing is only allowed for an unsigned iPhone IPA")
        original = Path(args.ipa).resolve()
        output = original.with_name(original.stem + "-xcross-signed.ipa")
        if output.exists():
            output = original.with_name(original.stem + "-xcross-signed-" + uuid.uuid4().hex[:8] + ".ipa")
        with tempfile.TemporaryDirectory(prefix="xcm-sign-") as temporary:
            directory = Path(temporary)
            app, modes = prepare(original, directory)
            result = subprocess.run([
                args.dart, "--packages=" + args.packages, args.bridge,
                str(app), args.udid, report["bundle_id"],
            ], check=False)
            # Save a signed copy even when a subsequent device install fails.
            executable = app / report["executable"]
            from ipa_inspect import inspect_macho
            with executable.open("rb") as stream:
                signature = inspect_macho(stream, extent=executable.stat().st_size)
            if signature["signature"] == "present":
                pack_signed(directory / "Payload", output, modes)
                print(f"Signed IPA: {output}", flush=True)
            return result.returncode
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as exc:
        print(f"IPA signing: {exc}", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
