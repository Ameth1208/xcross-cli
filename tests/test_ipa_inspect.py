"""Host-side archive/parser regressions; no phone or signing credentials used."""
import io
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "windows"))
from ipa_inspect import PackageError, inspect_ipa, inspect_macho
from ipa_workflow import prepare


def executable(signature=None):
    commands = b""
    blob = b""
    if signature:
        directory = struct.pack(">IIII", 0xFADE0C02, 16, 0x20000, 2 if signature == "adhoc" else 0)
        cms = struct.pack(">II", 0xFADE0B01, 9) + b"x"
        slots = 1 if signature == "adhoc" else 2
        start = 12 + 8 * slots
        index = struct.pack(">II", 0, start)
        if slots == 2:
            index += struct.pack(">II", 0x10000, start + len(directory))
        content = directory + (cms if slots == 2 else b"")
        blob = struct.pack(">III", 0xFADE0CC0, start + len(content), slots) + index + content
        commands = struct.pack("<IIII", 0x1D, 16, 48, len(blob))
    return struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, bool(commands), len(commands), 0, 0) + commands + blob


class IpaInspectionTests(unittest.TestCase):
    def test_unsigned_executable(self):
        self.assertEqual(inspect_macho(io.BytesIO(executable()))["issues"], ["missing_signature"])

    def test_adhoc_is_not_device_identity(self):
        self.assertEqual(inspect_macho(io.BytesIO(executable("adhoc")))["signature"], "adhoc")

    def test_cms_presence_is_only_structural(self):
        # Deliberately fake CMS: preflight must describe presence, never validity.
        self.assertEqual(inspect_macho(io.BytesIO(executable("cms")))["signature"], "present")

    def test_truncated_signature_rejected(self):
        with self.assertRaises(PackageError):
            inspect_macho(io.BytesIO(executable("cms")[:-2]))

    def test_zero_size_command_rejected(self):
        data = bytearray(executable("cms"))
        struct.pack_into("<I", data, 36, 0)
        with self.assertRaises(PackageError):
            inspect_macho(io.BytesIO(data))

    def test_archive_metadata_and_no_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "file with spaces.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/App.app/Info.plist", plistlib.dumps({"CFBundleExecutable": "App", "CFBundleIdentifier": "com.example.app"}))
                archive.writestr("Payload/App.app/App", executable())
            before = ipa.read_bytes()
            self.assertEqual(inspect_ipa(ipa)["bundle_id"], "com.example.app")
            self.assertEqual(ipa.read_bytes(), before)
            self.assertEqual(len(list(Path(directory).iterdir())), 1)

    def test_unsafe_extraction_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "unsafe.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/../../escape", b"no")
            with self.assertRaises(PackageError):
                prepare(ipa, Path(directory) / "output")
            self.assertFalse((Path(directory) / "escape").exists())


if __name__ == "__main__":
    unittest.main()
