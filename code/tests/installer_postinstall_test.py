"""Exercise installer branches without launching apps or changing system state."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


CODE = Path(__file__).resolve().parents[1]


class PostinstallTests(unittest.TestCase):
    def run_preinstall(self, *, current_id="org.local.adblocker", current_version="0.0.2", current_build="5", app_exists=True, target="/"):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            app = root / "Ad Blocker.app"
            if app_exists:
                (app / "Contents").mkdir(parents=True)
                (app / "Contents/Info.plist").write_text("placeholder")
            mock = root / "PlistBuddy"
            mock.write_text('''#!/usr/bin/env python3
import os, sys
if "CFBundleIdentifier" in sys.argv[2]: print(os.environ["MOCK_BUNDLE_ID"])
elif "CFBundleShortVersionString" in sys.argv[2]: print(os.environ["MOCK_VERSION"])
elif "CFBundleVersion" in sys.argv[2]: print(os.environ["MOCK_BUILD"])
else: sys.exit(1)
''')
            mock.chmod(0o755)
            source = (CODE / "installer/preinstall").read_text()
            source = source.replace("__ADBLOCKER_BUNDLE_ID__", "org.local.adblocker")
            source = source.replace("__ADBLOCKER_MARKETING_VERSION__", "0.0.2")
            source = source.replace("__ADBLOCKER_BUNDLE_BUILD__", "5")
            source = source.replace("/Applications/Ad Blocker.app", str(app))
            source = source.replace("/usr/libexec/PlistBuddy", str(mock))
            script = root / "preinstall"
            script.write_text(source)
            result = subprocess.run(["/bin/bash", str(script), "package.pkg", "/", target],
                                    env={**os.environ, "MOCK_BUNDLE_ID": current_id, "MOCK_VERSION": current_version, "MOCK_BUILD": current_build},
                                    capture_output=True, text=True)
            return result

    def test_preinstall_allows_equal_or_newer_build_and_rejects_downgrade(self):
        for current in ("4", "5", "4.9"):
            with self.subTest(current=current):
                self.assertEqual(self.run_preinstall(current_build=current).returncode, 0)
        result = self.run_preinstall(current_build="6")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("downgrade", result.stderr)
        self.assertNotEqual(self.run_preinstall(current_id="org.other.app").returncode, 0)
        self.assertNotEqual(self.run_preinstall(current_build="not-a-version").returncode, 0)
        self.assertNotEqual(self.run_preinstall(current_version="0.0.3", current_build="1").returncode, 0)
        self.assertEqual(self.run_preinstall(current_version="0.0.1", current_build="999").returncode, 0)
        self.assertNotEqual(self.run_preinstall(target="/Volumes/Other").returncode, 0)

    def run_installer(self, *, user="desktopuser", uid="501", target="/",
                      app_exists=True, stat_status=0, id_status=0,
                      launch_status=0, open_status=0):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            app = root / "Ad Blocker.app"
            if app_exists:
                app.mkdir()
            log = root / "calls.jsonl"
            mock = '''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ["MOCK_LOG"], "a") as out:
    out.write(json.dumps([name] + sys.argv[1:]) + "\\n")
if name == "stat":
    print(os.environ["MOCK_USER"])
    sys.exit(int(os.environ["MOCK_STAT_STATUS"]))
if name == "id":
    print(os.environ["MOCK_UID"])
    sys.exit(int(os.environ["MOCK_ID_STATUS"]))
if name == "launchctl":
    if int(os.environ["MOCK_LAUNCH_STATUS"]):
        sys.exit(int(os.environ["MOCK_LAUNCH_STATUS"]))
    sys.exit(subprocess.run(sys.argv[3:]).returncode)
if name == "sudo":
    sys.exit(subprocess.run(sys.argv[4:]).returncode)
if name == "open":
    sys.exit(int(os.environ["MOCK_OPEN_STATUS"]))
sys.exit(99)
'''
            source = (CODE / "installer/postinstall").read_text()
            # Rewrite only this temporary test copy; production paths stay absolute.
            for command in ("/usr/bin/stat", "/usr/bin/id", "/bin/launchctl",
                            "/usr/bin/sudo", "/usr/bin/open"):
                replacement = root / Path(command).name
                replacement.write_text(mock)
                replacement.chmod(0o755)
                self.assertIn(command, source)
                source = source.replace(command, str(replacement))
            source = source.replace("/Applications/Ad Blocker.app", str(app))
            script = root / "postinstall"
            script.write_text(source)
            env = dict(os.environ, MOCK_LOG=str(log), MOCK_USER=user, MOCK_UID=uid,
                       MOCK_STAT_STATUS=str(stat_status), MOCK_ID_STATUS=str(id_status),
                       MOCK_LAUNCH_STATUS=str(launch_status), MOCK_OPEN_STATUS=str(open_status))
            result = subprocess.run(["/bin/bash", str(script), "package.pkg", "/", target],
                                    env=env, capture_output=True, text=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout, calls, str(app)

    def test_active_user_launches_with_both_session_and_uid(self):
        output, calls, app = self.run_installer()
        launch = next(call for call in calls if call[0] == "launchctl")
        self.assertEqual(launch[1:3], ["asuser", "501"])
        self.assertEqual(Path(launch[3]).name, "sudo")
        sudo = next(call for call in calls if call[0] == "sudo")
        self.assertEqual(sudo[1:4], ["-u", "desktopuser", "--"])
        self.assertEqual(Path(sudo[4]).name, "open")
        self.assertIn(["open", "-n", "-g", app, "--args", "--setup"], calls)
        self.assertIn("launch requested", output)
        self.assertNotIn("setup completed", output.lower())

    def test_ineligible_or_absent_user_never_launches(self):
        for options in ({"user": ""}, {"user": "root"}, {"user": "loginwindow"}, {"user": "_mbsetupuser"},
                        {"uid": "0"}, {"uid": "500"}, {"uid": "invalid"},
                        {"stat_status": 1}, {"id_status": 1},
                        {"target": "/Volumes/Other"}, {"target": ""},
                        {"app_exists": False}):
            with self.subTest(options=options):
                output, calls, _ = self.run_installer(**options)
                self.assertFalse(any(c[0] in ("launchctl", "sudo", "open") for c in calls))
                self.assertIn("manually", output)

    def test_launch_failures_request_manual_setup(self):
        for options in ({"launch_status": 1}, {"open_status": 1}):
            with self.subTest(options=options):
                output, _, _ = self.run_installer(**options)
                self.assertIn("manually", output)
                self.assertNotIn("launch requested", output)

    def test_packaging_accepts_only_expected_executable_scripts(self):
        source = (CODE / "scripts/package-macos.sh").read_text()
        marker = 'python3 - "$EXPANDED" "$PREINSTALL" "$POSTINSTALL" "$BUNDLE_ID" "$VERSION" "$BUILD_NUMBER" <<\'PY\'\n'
        validator = source.split(marker, 1)[1].split("\nPY\n", 1)[0]
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            scripts = root / "Scripts"
            scripts.mkdir()
            postinstall = scripts / "postinstall"
            expected_postinstall = CODE / "installer/postinstall"
            postinstall.write_bytes(expected_postinstall.read_bytes())
            postinstall.chmod(0o755)
            preinstall = scripts / "preinstall"
            expected_preinstall = CODE / "installer/preinstall"
            preinstall.write_text(expected_preinstall.read_text()
                                  .replace("__ADBLOCKER_BUNDLE_ID__", "org.local.adblocker")
                                  .replace("__ADBLOCKER_MARKETING_VERSION__", "0.0.2")
                                  .replace("__ADBLOCKER_BUNDLE_BUILD__", "5"))
            preinstall.chmod(0o755)

            def validate():
                return subprocess.run(["python3", "-c", validator, str(root), str(expected_preinstall), str(expected_postinstall), "org.local.adblocker", "0.0.2", "5"],
                                      capture_output=True).returncode
            self.assertEqual(validate(), 0)
            postinstall.write_text("#!/bin/bash\nexit 0\n")
            self.assertNotEqual(validate(), 0)
            postinstall.write_bytes(expected_postinstall.read_bytes())
            extra = scripts / "unexpected"
            extra.write_text("unexpected")
            self.assertNotEqual(validate(), 0)
            extra.unlink()
            postinstall.chmod(0o644)
            self.assertNotEqual(validate(), 0)
            postinstall.unlink()
            postinstall.symlink_to(expected_postinstall)
            self.assertNotEqual(validate(), 0)
            postinstall.unlink()
            postinstall.write_bytes(expected_postinstall.read_bytes())
            postinstall.chmod(0o755)
            preinstall.write_bytes(expected_preinstall.read_bytes())
            self.assertNotEqual(validate(), 0)


if __name__ == "__main__":
    unittest.main()
