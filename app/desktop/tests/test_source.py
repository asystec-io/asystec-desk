import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("prepare", ROOT / "desktop/prepare.py")
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class SourceSafetyTests(unittest.TestCase):
    def test_tampered_download_cache_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / "rustdesk-commit.zip").write_bytes(b"altered")
            with self.assertRaisesRegex(ValueError, "Cache alterado"):
                prepare.fetch("rustdesk", "commit", "0" * 64, cache)

    def test_zip_cannot_escape_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "malicious.zip"
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr("../escaped.txt", "not allowed")
            with self.assertRaisesRegex(ValueError, "Ruta insegura"):
                prepare.unpack(archive, root / "output")
            self.assertFalse((root / "escaped.txt").exists())

    def test_existing_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            marker = output / "keep.txt"
            marker.write_text("keep")
            with self.assertRaises(FileExistsError):
                prepare.prepare(output)
            self.assertEqual(marker.read_text(), "keep")

    def test_prepared_sources_are_intact_and_attributed(self):
        source = ROOT / ".build/asystec-desk-source"
        manifest = json.loads((source / "ASYSTEC-SOURCE-MANIFEST.json").read_text())
        for name, expected in manifest["files"].items():
            with self.subTest(file=name):
                self.assertEqual(prepare.sha256(source / name), expected)
        original = (ROOT / "clients/windows/LICENSE-RUSTDESK.txt").read_text(encoding="utf-8-sig")
        self.assertEqual((source / "LICENCE").read_text(encoding="utf-8-sig"), original)
        config = (source / "libs/hbb_common/src/config.rs").read_text()
        self.assertNotIn('"rs-ny.rustdesk.com"', config)
        self.assertIn(manifest["profile"]["public_key"], config)
        injected = config.split('// Asystec Desk:', 1)[1].split(']));', 1)[0]
        self.assertNotIn('("password".to_owned()', injected)
        rc = (source / "flutter/windows/runner/Runner.rc").read_text(encoding="utf-8")
        self.assertIn('"ProductName", "Asystec Desk"', rc)
        self.assertIn("Copyright © 2026 Purslane Tech Pte. Ltd.", rc)

    def test_upstream_drift_fails_before_patching(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            file = source / "libs/hbb_common/src/config.rs"
            file.parent.mkdir(parents=True)
            file.write_text("upstream changed")
            profile = json.loads((ROOT / "desktop/profile.json").read_text())
            with self.assertRaisesRegex(ValueError, "Upstream cambio"):
                prepare.brand(source, profile, ROOT / "desktop/assets")


if __name__ == "__main__":
    unittest.main()
