"""Read-only IPA preflight. Signature presence is not cryptographic validation."""

import argparse
import json
import plistlib
import struct
import zipfile


class PackageError(ValueError):
    pass


def read_exact(stream, size):
    data = stream.read(size)
    if len(data) != size:
        raise PackageError("Truncated executable")
    return data


def inspect_macho(stream, base=0, extent=None):
    stream.seek(base)
    magic = read_exact(stream, 4)
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        count = struct.unpack(">I", read_exact(stream, 4))[0]
        if count > 64 or base:
            raise PackageError("Invalid universal executable")
        wide = magic[-1] == 0xBF
        slices = []
        for _ in range(count):
            values = struct.unpack(">IIQQII" if wide else ">IIIII", read_exact(stream, 32 if wide else 20))
            if values[2] < 8 + count * (32 if wide else 20) or (
                extent is not None and values[2] + values[3] > extent
            ):
                raise PackageError("Invalid universal executable slice")
            if values[0] == 0x0100000C:  # CPU_TYPE_ARM64
                slices.append((values[2], values[3]))
        if not slices:
            return {"signature": "missing", "issues": ["device_architecture_missing"]}
        results = [inspect_macho(stream, offset, size) for offset, size in slices]
        issues = sorted({issue for result in results for issue in result["issues"]})
        signature = "missing" if any(r["signature"] == "missing" for r in results) else (
            "adhoc" if any(r["signature"] == "adhoc" for r in results) else "present")
        return {"signature": signature, "issues": issues}
    layouts = {
        b"\xcf\xfa\xed\xfe": ("<", 32), b"\xfe\xed\xfa\xcf": (">", 32),
        b"\xce\xfa\xed\xfe": ("<", 28), b"\xfe\xed\xfa\xce": (">", 28),
    }
    if magic not in layouts:
        raise PackageError("Executable is not Mach-O")
    endian, header_size = layouts[magic]
    header = magic + read_exact(stream, header_size - 4)
    cpu, = struct.unpack_from(endian + "I", header, 4)
    count, command_bytes = struct.unpack_from(endian + "II", header, 16)
    if count > 65536 or command_bytes > 16 * 1024 * 1024:
        raise PackageError("Invalid Mach-O load commands")
    if extent is not None and header_size + command_bytes > extent:
        raise PackageError("Load commands exceed executable slice")
    commands = read_exact(stream, command_bytes)
    issues = []
    if cpu != 0x0100000C:
        issues.append("device_architecture_missing")
    signature_range = None
    offset = 0
    for _ in range(count):
        if offset + 8 > len(commands):
            raise PackageError("Truncated load command")
        command, size = struct.unpack_from(endian + "II", commands, offset)
        if size < 8 or offset + size > len(commands):
            raise PackageError("Invalid load command size")
        if command == 0x1D and size >= 16:  # LC_CODE_SIGNATURE
            signature_range = struct.unpack_from(endian + "II", commands, offset + 8)
        if command in (0x21, 0x2C) and size >= 20:
            if struct.unpack_from(endian + "I", commands, offset + 16)[0]:
                issues.append("encrypted_binary")
        if command == 0x32 and size >= 24:  # LC_BUILD_VERSION, PLATFORM_IOS
            if struct.unpack_from(endian + "I", commands, offset + 8)[0] != 2:
                issues.append("not_ios_device")
        offset += size
    if not signature_range or not signature_range[1]:
        return {"signature": "missing", "issues": issues + ["missing_signature"]}
    start, length = signature_range
    if start < header_size + command_bytes or length > 16 * 1024 * 1024 or (
        extent is not None and start + length > extent
    ):
        raise PackageError("Invalid code signature range")
    stream.seek(base + start)
    blob = read_exact(stream, length)
    if len(blob) < 12:
        raise PackageError("Truncated code signature")
    blob_magic, blob_length, slots = struct.unpack_from(">III", blob)
    if blob_magic != 0xFADE0CC0 or blob_length > len(blob) or 12 + slots * 8 > blob_length:
        raise PackageError("Invalid signature superblob")
    cms_present = False
    adhoc = False
    directory_present = False
    for index in range(slots):
        slot, position = struct.unpack_from(">II", blob, 12 + index * 8)
        if position + 8 > blob_length:
            raise PackageError("Invalid signature slot")
        kind, size = struct.unpack_from(">II", blob, position)
        if size < 8 or position + size > blob_length:
            raise PackageError("Truncated signature slot")
        if kind == 0xFADE0C02 and size >= 16:
            directory_present = True
            adhoc |= bool(struct.unpack_from(">I", blob, position + 12)[0] & 2)
        if slot == 0x10000 and kind == 0xFADE0B01 and size > 8:
            cms_present = True
    if not directory_present:
        raise PackageError("Missing CodeDirectory")
    signature = "adhoc" if adhoc or not cms_present else "present"
    if signature == "adhoc":
        issues.append("adhoc_signature")
    return {"signature": signature, "issues": issues}


def inspect_ipa(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise PackageError("Duplicate ZIP entries")
        apps = [n for n in names if n.startswith("Payload/") and n.endswith(".app/Info.plist") and n.count("/") == 2]
        if len(apps) != 1:
            raise PackageError("Expected one Payload/*.app/Info.plist")
        entry = archive.getinfo(apps[0])
        if entry.file_size > 1024 * 1024:
            raise PackageError("Info.plist exceeds size limit")
        info = plistlib.loads(archive.read(entry))
        root = apps[0].rsplit("/", 1)[0] + "/"
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not executable or "/" in executable or "\\" in executable:
            raise PackageError("Invalid CFBundleExecutable")
        binary = archive.getinfo(root + executable)
        with archive.open(binary) as stream:
            result = inspect_macho(stream, extent=binary.file_size)
        return {
            "name": info.get("CFBundleDisplayName") or info.get("CFBundleName") or executable,
            "bundle_id": info.get("CFBundleIdentifier", ""),
            "executable": executable,
            "signature": result["signature"],
            "profile_present": root + "embedded.mobileprovision" in names,
            "resources_present": root + "_CodeSignature/CodeResources" in names,
            "issues": sorted(set(result["issues"])),
            "scope": "main executable only; iOS performs final validation",
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    args = parser.parse_args()
    try:
        result = inspect_ipa(args.ipa)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, RuntimeError, EOFError, struct.error) as exc:
        result = {"signature": "unknown", "issues": ["invalid_package"], "error": str(exc)}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
