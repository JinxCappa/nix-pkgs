import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("package-changed.py").resolve()
ROOT = SCRIPT.parents[2]
PACKAGES = ("sops-install-secrets", "technitium-dns-server")


class PackageChangedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "commit.gpgsign", "false")
        for path in ("_sources/generated.json", "_sources/generated.nix"):
            self.write(path, (ROOT / path).read_text())
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo).decode().strip()

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def check(self, package, expected, event_name="push", event=None, cwd=None):
        event = event if event is not None else {"before": self.base, "after": self.git("rev-parse", "HEAD")}
        self.write("event.json", json.dumps(event))
        output = self.repo / "output"
        output.write_text("")
        args = [sys.executable, str(SCRIPT), package]
        if package == "technitium-dns-server":
            args.append("technitium-dns-server-library")
        subprocess.run(args, cwd=cwd or self.repo, check=True, capture_output=True, env={
            **os.environ, "GITHUB_EVENT_NAME": event_name,
            "GITHUB_EVENT_PATH": str(self.repo / "event.json"), "GITHUB_OUTPUT": str(output),
        })
        self.assertEqual(output.read_text(), f"changed={str(expected).lower()}\n")

    def test_reported_claude_commit_skips_both_packages(self):
        head = "0fc8301407a54e60f35250d7193da43831983ad1"
        base = subprocess.check_output(["git", "rev-parse", f"{head}^"], cwd=ROOT).decode().strip()
        for package in PACKAGES:
            self.check(package, False, event={"before": base, "after": head}, cwd=ROOT)

    def test_own_json_source_changes(self):
        path = "_sources/generated.json"
        data = json.loads((self.repo / path).read_text())
        data["sops-install-secrets"]["version"] = "new-version"
        self.write(path, json.dumps(data))
        self.commit()
        self.check("sops-install-secrets", True)
        self.check("technitium-dns-server", False)

    def test_technitium_library_nix_only_change(self):
        path = "_sources/generated.nix"
        text = (self.repo / path).read_text()
        text = text.replace('pname = "technitium-dns-server-library";', 'pname = "changed-library";')
        self.write(path, text)
        self.commit()
        self.check("technitium-dns-server", True)
        self.check("sops-install-secrets", False)

    def test_direct_and_shared_files(self):
        for path in ("packages/sops-install-secrets/default.nix", "flake.lock", "nvfetcher.toml",
                     ".github/scripts/package-changed.py", ".github/workflows/sops-install-secrets.yaml"):
            with self.subTest(path=path):
                self.base = self.git("rev-parse", "HEAD")
                self.write(path, "changed")
                self.commit()
                self.check("sops-install-secrets", True)

    def test_generated_shared_code_change(self):
        path = "_sources/generated.nix"
        self.write(path, "# shared change\n" + (self.repo / path).read_text())
        self.commit()
        for package in PACKAGES:
            self.check(package, True)

    def test_manual_new_branch_and_missing_history_build(self):
        self.check(PACKAGES[0], True, event_name="workflow_dispatch", event={})
        for base in ("0" * 40, "1" * 40):
            self.check(PACKAGES[0], True, event={"before": base, "after": self.base})

    def test_pull_request_compares_from_merge_base(self):
        self.git("checkout", "-qb", "feature")
        self.write("packages/claude-code/default.nix", "changed")
        head = self.commit()
        self.git("checkout", "--detach", self.base)
        self.write("packages/sops-install-secrets/default.nix", "base-only change")
        base = self.commit()
        self.check(PACKAGES[0], False, event_name="pull_request", event={
            "pull_request": {"base": {"sha": base}, "head": {"sha": head}},
        })

    def test_unrecognized_metadata_builds(self):
        self.write("_sources/generated.nix", "unrecognized layout")
        self.commit()
        self.check(PACKAGES[0], True)


if __name__ == "__main__":
    unittest.main()
