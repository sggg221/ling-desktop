import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class LauncherChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="ling-launcher-check-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "project with spaces"
        self.root.mkdir()
        source = Path(__file__).resolve().parents[1] / "run.command"
        (self.root / "run.command").write_bytes(source.read_bytes())
        (self.root / "build.sh").write_text(
            '#!/bin/bash\n'
            'printf "build\\n" >> "$LAUNCH_LOG"\n'
            'exit "${BUILD_STATUS:-0}"\n'
        )
        binaries = self.root / "bin"
        binaries.mkdir()
        opener = binaries / "open"
        opener.write_text(
            '#!/bin/bash\n'
            'printf "open %s\\n" "$1" >> "$LAUNCH_LOG"\n'
        )
        opener.chmod(0o755)
        self.log = self.root / "launch.log"
        self.environment = {
            **os.environ,
            "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
            "LAUNCH_LOG": str(self.log),
            "BUILD_STATUS": "0",
        }

    def existing_binary(self):
        binary = self.root / "dist/LingDesktop.app/Contents/MacOS/LingDesktop"
        binary.parent.mkdir(parents=True)
        binary.write_text("#!/bin/bash\nexit 0\n")
        binary.chmod(0o755)
        return binary

    def run_launcher(self):
        return subprocess.run(
            ["bash", str(self.root / "run.command")],
            cwd=self.directory.name,
            env=self.environment,
            text=True,
            capture_output=True,
        )

    def assert_build_then_open(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.log.read_text().splitlines(),
            ["build", "open " + str(self.root / "dist/LingDesktop.app")],
        )

    def test_first_launch_builds_before_opening(self):
        self.assert_build_then_open()

    def test_existing_binary_still_runs_incremental_build(self):
        self.existing_binary()
        self.assert_build_then_open()

    def test_newer_source_is_not_ignored(self):
        binary = self.existing_binary()
        os.utime(binary, (1, 1))
        sources = self.root / "Sources"
        sources.mkdir()
        (sources / "Changed.swift").write_text("// Newer source\n")
        self.assert_build_then_open()

    def test_build_failure_does_not_open_old_binary(self):
        self.existing_binary()
        self.environment["BUILD_STATUS"] = "42"
        result = self.run_launcher()
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), ["build"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
