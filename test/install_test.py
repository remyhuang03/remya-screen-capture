"""Exercise installation only inside temporary XDG roots."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("capture_install", ROOT / "tool/install.py")
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class InstallTest(unittest.TestCase):
    def test_core_requirement_registration_and_settings_action(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "source"
            data = base / "data"
            home = base / "home"
            environment = {
                "HOME": str(home), "XDG_DATA_HOME": str(data),
                "XDG_DATA_DIRS": str(base / "system"),
            }
            bundle = root / "build/linux/x64/release/bundle"
            bundle.mkdir(parents=True)
            (bundle / installer.APP_ID).touch()
            (root / "linux").symlink_to(ROOT / "linux", target_is_directory=True)
            (root / "assets").symlink_to(ROOT / "assets", target_is_directory=True)
            with patch.object(installer, "require_inter_font"), patch.object(
                installer.shutil, "which", return_value=None
            ):
                with self.assertRaisesRegex(RuntimeError, "Install Remya Core first"):
                    installer.install(root, environment)
                self.assertFalse(data.exists())
                activation = base / "system/dbus-1/services/top.remya.Core1.service"
                activation.parent.mkdir(parents=True)
                activation.touch()
                installer.install(root, environment)
            registration = data / "remya/apps/remya-screen-capture.json"
            self.assertEqual(registration.read_bytes(), (
                ROOT / "linux/packaging/remya-screen-capture.json"
            ).read_bytes())
            entry = (data / f"applications/{installer.PACKAGE}.desktop").read_text()
            self.assertIn("Actions=PickColor;settings;", entry)
            self.assertIn("[Desktop Action settings]", entry)
            self.assertIn(f'Exec=/usr/bin/env "{data}/remya/{installer.APP_ID}/{installer.APP_ID}" --settings', entry)
            self.assertEqual(json.loads(registration.read_text())["config"], "screen-capture")
