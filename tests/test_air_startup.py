#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml>=6"]
# ///
"""Tests for .air/cloud/startup.sh with a temporary HOME and stubbed downloads and engine clone."""
import gzip
import hashlib
import io
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / ".air/cloud/startup.sh"

STUBS = {
    "curl": 'echo curl >> "$LOG"\nwhile [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done\ncat "$STUB_TAR" > "$out"\n',
    "git": 'echo git "$@" >> "$LOG"\ncase "$1" in\n  clone) [ "${GIT_FAIL:-}" != clone ] || exit 1; mkdir -p "$7/factory" ;;\n  check-ref-format) [ "${GIT_INVALID_REF:-}" != "$2" ] ;;\n  *) exit 0 ;;\nesac\n',
    "gh": "",
    "uv": ('echo uv "$@" >> "$LOG"\nprintf "#!/bin/sh\\n" > "$HOME/.local/bin/decide"; chmod +x "$HOME/.local/bin/decide"\n'
           'if [ "$1 $2 $3" = "tool install --force" ]; then\n'
           '  printf "#!/bin/sh\\necho team=\\$FACTORY_TEAM args=\\$*\\n" > "$HOME/.local/bin/factory"; chmod +x "$HOME/.local/bin/factory"\n'
           'fi\n'),
}


class StartupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        self.home, self.repo, self.log = t / "home", t / "repo", t / "log"
        stubs = t / "stubs"
        for directory in (self.home, self.repo, stubs):
            directory.mkdir()
        shutil.copytree(ROOT / "roles", self.repo / "roles")
        shutil.copytree(ROOT / "skills", self.repo / "skills")
        shutil.copytree(ROOT / "workflows", self.repo / "workflows")
        shutil.copy(ROOT / "factory.project.yaml", self.repo / "factory.project.yaml")
        self.log.touch()
        for name, body in STUBS.items():
            path = stubs / name
            path.write_text("#!/bin/sh\n" + body)
            path.chmod(0o755)

        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w") as archive:
            info = tarfile.TarInfo("conftest")
            info.mode, info.size = 0o755, 10
            archive.addfile(info, io.BytesIO(b"#!/bin/sh\n\n"[:10]))
        data = gzip.compress(buf.getvalue(), mtime=0)
        (t / "stub.tgz").write_bytes(data)
        self.script = t / "startup.sh"
        source = SCRIPT.read_text()
        self.script.write_text(re.sub(r"^CONFTEST_SHA=.*$", f"CONFTEST_SHA={hashlib.sha256(data).hexdigest()}", source, flags=re.M))
        self.env = {
            "HOME": str(self.home),
            "LOG": str(self.log),
            "STUB_TAR": str(t / "stub.tgz"),
            "PATH": f"{stubs}:/usr/bin:/bin",
        }

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self):
        return subprocess.run(["sh", str(self.script)], cwd=self.repo, env=self.env, capture_output=True, text=True)

    def test_engine_is_cloned_from_configured_repository_and_team_is_not_cloned(self):
        self.env["FACTORY_ENGINE_REPOSITORY"] = "https://github.com/example/engine.git"
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        self.assertIn(f"git clone --depth 1 --branch main https://github.com/example/engine.git {self.home}/factory-main", log)
        self.assertNotIn("factory-team", log)
        self.assertEqual((self.repo / "factory").exists(), False)
        self.assertEqual(self.env.get("FACTORY_TEAM_REPOSITORY"), None)

    def test_factory_command_carries_the_team(self):
        for launch in (1, 2):  # a relaunch reinstalls the engine and must not wrap the wrapper
            result = self.run_script()
            self.assertEqual(result.returncode, 0, result.stderr)
            factory = self.home / ".local/bin/factory"
            env = {"PATH": "/usr/bin:/bin", "HOME": str(self.home)}
            out = subprocess.run([str(factory), "sweep", "--main"], env=env, capture_output=True, text=True)
            self.assertEqual(out.stdout.strip(), f"team={self.repo.resolve()} args=sweep --main", (launch, out.stderr))
            own = subprocess.run([str(factory)], env={**env, "FACTORY_TEAM": "/elsewhere"}, capture_output=True, text=True)
            self.assertEqual(own.stdout.strip(), "team=/elsewhere args=")

    def test_project_descriptor_tag_selects_engine_ref(self):
        descriptor = self.repo / "factory.project.yaml"
        descriptor.write_text(descriptor.read_text().replace("engine: 1", "engine: v0.2.0", 1))
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("git clone --depth 1 --branch v0.2.0", self.log.read_text())

    def test_ops_exposes_engine_factory_scripts(self):
        self.env["FACTORY_ENV"] = "ops"
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / "factory").resolve(), (self.home / "factory-main/factory").resolve())

    def test_environment_setup_hook_runs_common_then_environment(self):
        hooks = self.repo / "environments"
        (hooks / "write").mkdir(parents=True)
        (hooks / "setup.sh").write_text('echo common >> "$HOOK_LOG"\n')
        (hooks / "write/setup.sh").write_text('echo write >> "$HOOK_LOG"\n')
        self.env.update(FACTORY_ENV="write", HOOK_LOG=str(self.repo / "hooks.log"))
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.repo / "hooks.log").read_text().splitlines(), ["common", "write"])

    def test_role_skills_are_installed_from_team_repository(self):
        self.env["FACTORY_ENV"] = "write"
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        for base in (self.home / ".agents/skills", self.home / ".claude/skills"):
            self.assertTrue((base / "tdd/SKILL.md").is_file())
            self.assertTrue((base / "diagnosing-bugs/SKILL.md").is_file())

    def test_missing_team_skill_fails_without_engine_fallback(self):
        shutil.rmtree(self.repo / "skills/tdd")
        self.env["FACTORY_ENV"] = "write"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing team skill: tdd", result.stderr)

    def test_missing_hook_is_skipped(self):
        self.env["FACTORY_ENV"] = "write"
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.repo / "hooks.log").exists())

    def test_engine_clone_failure_is_reported(self):
        self.env["GIT_FAIL"] = "clone"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("startup: factory install failed", result.stderr)
        self.assertNotIn("uv tool install --force", self.log.read_text())

    def test_factory_install_failure_is_reported(self):
        uv = Path(self.env["PATH"].split(":", 1)[0]) / "uv"
        uv.write_text("#!/bin/sh\nexit 1\n")
        uv.chmod(0o755)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("startup: factory install failed", result.stderr)

    def test_checksum_mismatch_fails_closed(self):
        self.script.write_text(SCRIPT.read_text())
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checksum mismatch", result.stderr)
        self.assertFalse((self.home / ".local/bin/conftest").exists())

    def test_every_download_is_pinned(self):
        text = SCRIPT.read_text()
        self.assertEqual(len(re.findall(r"^\w+_SHA=[0-9a-f]{64}$", text, re.M)), 3)
        self.assertNotRegex(text, r"curl[^\n]*\|\s*(env [^\n]*)?sh")

    def dry_run(self, env):
        result = subprocess.run(
            ["sh", str(SCRIPT)], cwd=self.repo, capture_output=True, text=True,
            env={**self.env, "FACTORY_DRY": "1", "FACTORY_ENV": env},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_dry_run_read_and_write_install_their_team_skills(self):
        read = self.dry_run("read")
        self.assertIn("would install skills: ponytail-review to-tickets", read)
        write = self.dry_run("write")
        self.assertIn("tdd", write)
        self.assertIn("shellcheck-py==0.10.0.1 jactionlint==2.3.0", write)
        self.assertFalse((self.home / ".claude").exists())

    def test_every_node_role_is_installed_by_its_environment(self):
        graph = yaml.safe_load((self.repo / "workflows/delivery.yaml").read_text())["nodes"]
        for env in ("read", "write", "ops"):
            roles_line = self.dry_run(env).splitlines()[0].split("roles=")[1]
            for node in graph.values():
                if node.get("env") == env and node["role"] not in ("script", "human"):
                    self.assertIn(node["role"], roles_line.split(), (env, node["role"]))

    def test_path_like_skill_name_is_rejected_without_deleting_outside_files(self):
        self.env["FACTORY_ENV"] = "write"
        (self.repo / "roles/developer/skills.txt").write_text("../victim\n")
        keep = self.home / ".agents/victim/keep"
        keep.parent.mkdir(parents=True)
        keep.write_text("x")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid skill name", result.stderr)
        self.assertTrue(keep.exists())


if __name__ == "__main__":
    unittest.main()