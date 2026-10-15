"""Exercise the native CLI against real GNU make, in isolated directories."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "_build/native/debug/build/cmd/main/main.exe"
MAKE = shutil.which("gmake") or shutil.which("make")


class MakeFilesystemTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gmkfs-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("source.txt", b"hello\n")
        self.write("included.mk", b"PHONY_NAMES = clean force\n.PHONY: $(PHONY_NAMES)\n")
        self.write("Makefile", b"""include included.mk
.PHONY: all
all: output.txt
output.txt: source.txt
\t@echo recipe-log
\t@echo built >> builds
\t@tr '[:lower:]' '[:upper:]' < source.txt > output.txt
clean:
\t@touch should-not-run
force:
\t@echo forced >> forced
forced.txt: force
\t@printf forced > forced.txt
broken.txt:
\t@printf stale > broken.txt
\t@exit 7
missing.txt:
\t@echo no-output
binary.dat:
\t@printf '\\000\\377\\012' > binary.dat
""")

    def write(self, name, content):
        (self.root / name).write_bytes(content)

    def cli(self, *args, env=None):
        return subprocess.run(
            [str(BINARY), "-C", str(self.root), "--make", MAKE, *args],
            capture_output=True, env=env, timeout=20,
        )

    def test_listing_does_not_build_and_hides_expanded_phony(self):
        result = self.cli("ls")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(),
                         [b"binary.dat", b"broken.txt", b"forced.txt", b"missing.txt", b"output.txt"])
        self.assertFalse((self.root / "builds").exists())

    def test_build_read_and_make_incremental_rebuild(self):
        first = self.cli("cat", "output.txt")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, b"HELLO\n")
        self.assertIn(b"recipe-log", first.stderr)
        self.assertEqual(self.cli("cat", "output.txt").stdout, b"HELLO\n")
        self.assertEqual((self.root / "builds").read_bytes(), b"built\n")
        self.write("source.txt", b"changed\n")
        # Deterministic dependency ordering without sleeping or future timestamps.
        os.utime(self.root / "output.txt", (1, 1))
        self.assertEqual(self.cli("cat", "output.txt").stdout, b"CHANGED\n")
        self.assertEqual((self.root / "builds").read_bytes(), b"built\nbuilt\n")

    def test_phony_is_rejected_before_execution_even_if_file_exists(self):
        self.write("clean", b"not a visible file")
        result = self.cli("cat", "clean")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertFalse((self.root / "should-not-run").exists())

    def test_phony_prerequisite_runs_normally(self):
        for _ in range(2):
            result = self.cli("cat", "forced.txt")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, b"forced")
        self.assertEqual((self.root / "forced").read_bytes(), b"forced\nforced\n")

    def test_binary_content_is_not_decoded(self):
        result = self.cli("cat", "binary.dat")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"\x00\xff\n")

    def test_failed_build_and_missing_output_never_return_recipe_output(self):
        for target in ["broken.txt", "missing.txt", "unknown.txt"]:
            with self.subTest(target=target):
                result = self.cli("cat", target)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")

    def test_make_flags_do_not_suppress_build(self):
        result = self.cli("cat", "output.txt", env={**os.environ, "MAKEFLAGS": "n"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"HELLO\n")

    def test_recursive_default_recipe_is_not_executed_by_listing(self):
        self.write("Makefile", b"all:\n\t+touch should-not-run\n")
        result = self.cli("ls")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "should-not-run").exists())

    def test_alternate_makefile_and_nested_target(self):
        self.write("Custom.mk", b"dir/out:\n\t@mkdir -p dir\n\t@printf nested > dir/out\n")
        result = self.cli("-f", "Custom.mk", "cat", "dir/out")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b"nested")


if __name__ == "__main__":
    unittest.main()
