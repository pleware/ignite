"""Hermetic tests for the ignite Python engine.

No live network, no real ``mise install``, no real ``pecl``. Every network /
process edge is stubbed by injecting ``run`` / ``fetch`` callbacks. The tests
run against ``src/`` on any local Python 3.10+ (see ``test-engine-python.sh``).

Run directly::

    PYTHONPATH=src python tests/test_engine.py
"""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "src"))

from ignite import _toml, _yaml  # noqa: E402
from ignite.config import Config, ConfigError  # noqa: E402
from ignite.manifest import clone_targets  # noqa: E402
from ignite.paths import (  # noqa: E402
    resolve_toolchain_root,
    resolve_workspace_root,
    to_native,
    to_posix,
)
from ignite.pins import Pins  # noqa: E402
from ignite.runtime_extensions import Step, plan  # noqa: E402
from ignite.shim import env_exports  # noqa: E402
from ignite.toolchain import plant_mise, run_mise_install  # noqa: E402
from ignite.tools import install_tools  # noqa: E402
from ignite.workspace_tree import (  # noqa: E402
    LayoutError,
    contains_kind,
    init,
    analyze,
    parse_layout_file,
    parse_layout,
)

KIT = pathlib.Path(__file__).resolve().parent.parent


def write(path: pathlib.Path, text: str) -> pathlib.Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


class TomlTest(unittest.TestCase):
    def test_sections_and_comments(self):
        data = _toml.loads(
            "# c\n[kit]\npin = \"abc\" # trailing\n\n[other]\nx = 1\n"
        )
        self.assertEqual(data["kit"]["pin"], "abc")
        self.assertEqual(data["other"]["x"], "1")

    def test_quoted_key(self):
        data = _toml.loads('[tools]\n"php@8.4" = "8.4.1"\n')
        self.assertEqual(data["tools"]["php@8.4"], "8.4.1")

    def test_inline_array(self):
        data = _toml.loads('[runtime-extensions]\nphp = ["imagick", "pcntl"]\n')
        self.assertEqual(data["runtime-extensions"]["php"], ["imagick", "pcntl"])

    def test_bad_line_raises(self):
        with self.assertRaises(_toml.TomlError):
            _toml.loads("[x]\nnot-a-kv-line\n")

    def test_key_outside_section_raises(self):
        with self.assertRaises(_toml.TomlError):
            _toml.loads("pin = 1\n")


class YamlTest(unittest.TestCase):
    def test_nested_and_flow(self):
        data = _yaml.loads(
            "schema: ignite.workspace-tree/1\n"
            "kinds:\n"
            "  notes:\n"
            "    gitignore: deny-by-default\n"
            "    contains:\n"
            "      - leaf\n"
            "    tags: [a, b]\n"
        )
        self.assertEqual(data["schema"], "ignite.workspace-tree/1")
        self.assertEqual(data["kinds"]["notes"]["gitignore"], "deny-by-default")
        self.assertEqual(data["kinds"]["notes"]["contains"], ["leaf"])
        self.assertEqual(data["kinds"]["notes"]["tags"], ["a", "b"])

    def test_bool_and_null(self):
        data = _yaml.loads("a: true\nb: false\nc: null\n")
        self.assertIs(data["a"], True)
        self.assertIs(data["b"], False)
        self.assertIsNone(data["c"])


class PinsTest(unittest.TestCase):
    def setUp(self):
        self.pins = Pins(KIT)

    def test_pins_read(self):
        self.assertTrue(self.pins.pin_mise)
        self.assertTrue(self.pins.pin_uv)
        self.assertTrue(self.pins.pin_python)
        self.assertIn("GRAPHIFYY", self.pins.extra_tool_keys)

    def test_tool_spec_expands(self):
        tool = self.pins.tool("GRAPHIFYY")
        self.assertIn(self.pins.get("PIN_GRAPHIFYY"), tool["spec"])


class PathsTest(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Windows-only drive mapping")
    def test_to_native_posix_drive(self):
        self.assertEqual(to_native("/f/work/repo"), "F:\\work\\repo")

    def test_to_native_leaves_windows_alone(self):
        self.assertEqual(to_native("D:/work/repo"), "D:/work/repo")
        self.assertEqual(to_native("C:\\work\\repo"), "C:\\work\\repo")
        self.assertEqual(to_native("relative"), "relative")

    @unittest.skipUnless(os.name == "nt", "Windows-only drive mapping")
    def test_to_posix_drive(self):
        self.assertEqual(to_posix("F:\\work\\repo"), "/f/work/repo")

    def test_resolve_workspace_explicit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = resolve_workspace_root(tmp)
            self.assertTrue(os.path.isdir(root))

    def test_resolve_toolchain(self):
        self.assertEqual(
            resolve_toolchain_root("/w"), os.path.join("/w", ".ignite")
        )


class ConfigTest(unittest.TestCase):
    def _cfg(self, text: str) -> Config:
        d = tempfile.mkdtemp()
        write(pathlib.Path(d) / "ignite.toml", text)
        return Config(d).load()

    def test_runtime_extensions_present(self):
        cfg = self._cfg('[runtime-extensions]\nphp@8.4 = ["imagick", "pcntl"]\n')
        self.assertEqual(
            cfg.runtime_extensions(), {"php@8.4": ["imagick", "pcntl"]}
        )

    def test_runtime_extensions_absent(self):
        cfg = self._cfg("# nothing\n")
        self.assertEqual(cfg.runtime_extensions(), {})

    def test_runtime_extensions_empty_table(self):
        cfg = self._cfg("[runtime-extensions]\n")
        self.assertEqual(cfg.runtime_extensions(), {})

    def test_missing_ignite_toml_raises(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ConfigError):
                Config(d).load()

    def test_kit_policy(self):
        cfg = self._cfg('[kit]\npin = "abc"\n')
        pin, url = cfg.kit_policy()
        self.assertEqual(pin, "abc")
        self.assertTrue(url.endswith("pleware/ignite.git"))

    def test_kit_url_without_pin_raises(self):
        cfg = self._cfg('[kit]\nurl = "https://example.com/x.git"\n')
        with self.assertRaises(ConfigError):
            cfg.kit_policy()

    def test_layout_policy(self):
        cfg = self._cfg(
            '[workspace-tree]\nfile = "layout.yaml"\nkind = "notes"\n'
        )
        file_, kind, kind_from = cfg.layout_policy()
        self.assertEqual((file_, kind, kind_from), ("layout.yaml", "notes", "notes"))

    def test_layout_alias(self):
        cfg = self._cfg('[layout]\nfile = "old.yaml"\nkind = "leaf"\n')
        file_, kind, _ = cfg.layout_policy()
        self.assertEqual((file_, kind), ("old.yaml", "leaf"))


class ManifestTest(unittest.TestCase):
    def test_clone_targets(self):
        targets = clone_targets(str(KIT / "examples" / "workspace"))
        by_key = {t.key: t for t in targets}
        self.assertIn("product", by_key)
        self.assertEqual(by_key["product"].dir, "example-product")
        self.assertTrue(by_key["product"].required)
        self.assertIn("optional_ops", by_key)
        self.assertFalse(by_key["optional_ops"].required)
        # path "." (umbrella) is skipped
        self.assertNotIn("workspace", by_key)

    def test_missing_mani_yaml_returns_empty(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(clone_targets(d), [])


class WorkspaceTreeTest(unittest.TestCase):
    def test_parse_example(self):
        layout = parse_layout_file(
            str(KIT / "examples" / "workspace" / "workspace-layout.yaml")
        )
        self.assertEqual(layout.schema, "ignite.workspace-tree/1")
        self.assertIn("notes", layout.kinds)
        self.assertIn("leaf", layout.kinds)
        self.assertEqual(layout.kinds["notes"].gitignore, "deny-by-default")

    def test_alias_schema(self):
        layout = parse_layout_file(
            str(KIT / "examples" / "layouts" / "minimal.yaml")
        )
        self.assertEqual(layout.schema, "ignite.layout/1")

    def test_bad_schema_raises(self):
        with self.assertRaises(LayoutError):
            parse_layout("schema: nope\nkinds:\n  x:\n")

    def test_contains(self):
        layout = parse_layout_file(
            str(KIT / "examples" / "workspace" / "workspace-layout.yaml")
        )
        self.assertTrue(contains_kind(layout, "notes", "leaf"))
        self.assertFalse(contains_kind(layout, "leaf", "notes"))

    def test_init_then_analyze(self):
        layout = parse_layout_file(
            str(KIT / "examples" / "layouts" / "minimal.yaml")
        )
        with tempfile.TemporaryDirectory() as tmp:
            dest = os.path.join(tmp, "ws")
            self.assertEqual(init(dest, "notes", str(KIT / "examples" / "layouts"), layout), [])
            self.assertTrue(os.path.isfile(os.path.join(dest, "README.md")))
            self.assertTrue(os.path.isdir(os.path.join(dest, "notes")))
            self.assertFalse(os.path.exists(os.path.join(dest, "drafts")))
            self.assertEqual(analyze(dest, "notes", layout), [])

            # forbidden path exists -> analyze fails
            os.makedirs(os.path.join(dest, "drafts"))
            self.assertTrue(analyze(dest, "notes", layout))


class RuntimeExtensionsTest(unittest.TestCase):
    def test_plan_pecl(self):
        p = plan({"php@8.4": ["imagick", "pcntl"]}, "linux")
        self.assertEqual(p.os, "linux")
        self.assertEqual(
            p.steps,
            [
                Step("php@8.4", "imagick", "linux", "pecl"),
                Step("php@8.4", "pcntl", "linux", "pecl"),
            ],
        )
        self.assertEqual(p.fallbacks, [])

    def test_plan_windows_dll(self):
        p = plan({"php@8.4": ["imagick", "redis"]}, "windows")
        self.assertEqual(p.steps[0].recipe, "dll")
        self.assertEqual(p.steps[1].recipe, "dll")

    def test_plan_absent(self):
        self.assertEqual(plan({}, "linux").steps, [])

    def test_plan_empty_list(self):
        self.assertEqual(plan({"php": []}, "linux").steps, [])

    def test_plan_unknown_recipe_falls_back(self):
        # gd is compiled in -> builtin -> fallback (no recipe on any OS)
        p = plan({"php@8.4": ["gd", "totally-unknown"]}, "linux")
        self.assertEqual(p.steps, [])
        self.assertEqual(
            p.fallbacks,
            [("php@8.4", "gd"), ("php@8.4", "totally-unknown")],
        )

    def test_never_merged_into_tool_pins(self):
        # runtime-extensions are a separate object from the TOOL_* fleet pins.
        pins = Pins(KIT)
        keys = set(pins.extra_tool_keys)
        p = plan({"php@8.4": ["imagick"]}, "linux")
        for step in p.steps:
            self.assertNotIn(step.extension, keys)
            self.assertNotIn(step.runtime, keys)
        # The TOOL_* plant is untouched by a runtime-extensions declaration.
        self.assertIn("GRAPHIFYY", keys)


class ShimTest(unittest.TestCase):
    def test_env_exports_shape(self):
        pins = Pins(KIT)
        out = env_exports(str(KIT / "examples" / "workspace"), pins)
        for needle in (
            "export IGNITE_TOOLCHAIN_ROOT=",
            "export MISE_DATA_DIR=",
            "export UV_TOOL_DIR=",
            "export UV_TOOL_BIN_DIR=",
            "unset GOROOT",
            "export GOCACHE=",
            "export GOMODCACHE=",
            "export PATH=",
            "/mise/shims:",
            f"/stack/mise/{pins.pin_mise}/bin:",
            f"/stack/uv/{pins.pin_uv}/bin:",
            "/uv-tools/bin:",
        ):
            self.assertIn(needle, out, needle)
        # PATH is a POSIX shim even on Windows (eval'd by Git Bash).
        self.assertNotIn("\\", out)


class ToolchainTest(unittest.TestCase):
    def test_plant_mise_uses_injected_fetch(self):
        pins = Pins(KIT)
        with tempfile.TemporaryDirectory() as tmp:
            toolchain = os.path.join(tmp, "tc")
            os.makedirs(toolchain)
            fetched = []

            def fake_fetch(url, dest):
                fetched.append(url)
                # fabricate a tar.gz holding a single `mise` binary
                import tarfile
                import io

                buf = io.BytesIO()
                with tarfile.open(fileobj=buf, mode="w:gz") as tf:
                    payload = b"#!/bin/sh\nexit 0\n"
                    info = tarfile.TarInfo("mise")
                    info.size = len(payload)
                    info.mode = 0o755
                    tf.addfile(info, io.BytesIO(payload))
                with open(dest, "wb") as fh:
                    fh.write(buf.getvalue())

            logs = []
            bin_path = plant_mise(
                toolchain, pins, "linux", "amd64", fake_fetch, logs.append
            )
            self.assertTrue(fetched)
            self.assertTrue(os.path.isfile(bin_path))
            self.assertTrue(os.access(bin_path, os.X_OK))

    def test_run_mise_install_invokes_mise(self):
        pins = Pins(KIT)
        with tempfile.TemporaryDirectory() as tmp:
            workspace = os.path.join(tmp, "ws")
            os.makedirs(workspace)
            write(pathlib.Path(workspace) / "mise.toml", "[tools]\n")
            calls = []

            def fake_run(cmd, cwd=None, env=None):
                calls.append(cmd)

            run_mise_install(
                workspace, os.path.join(tmp, "tc"), "/bin/mise", ["php@7.4"],
                fake_run, lambda m: None,
            )
            self.assertEqual([c[1] for c in calls], ["trust", "install", "install"])
            self.assertTrue(calls[0][2].endswith("mise.toml"))
            self.assertEqual(calls[2], ["/bin/mise", "install", "php@7.4"])


class ToolsTest(unittest.TestCase):
    def test_install_tools_markers_and_receipt_skip(self):
        pins = Pins(KIT)
        with tempfile.TemporaryDirectory() as tmp:
            toolchain = os.path.join(tmp, "tc")
            workspace = os.path.join(tmp, "ws")
            os.makedirs(workspace)
            os.makedirs(os.path.join(toolchain, "uv-tools", "bin"))
            calls = []

            def fake_run(cmd, cwd=None, env=None):
                calls.append(cmd)
                # simulate uv writing the tool env + receipt + interpreter
                tool_dir = env["UV_TOOL_DIR"]
                env_root = os.path.join(tool_dir, "graphifyy")
                os.makedirs(os.path.join(env_root, "bin"))
                write(pathlib.Path(env_root) / "bin" / "python", "#!/bin/sh\n")
                write(
                    pathlib.Path(env_root) / "uv-receipt.toml",
                    f'requirements = ["graphifyy=={pins.get("PIN_GRAPHIFYY")}"]\n',
                )

            logs = []
            install_tools(toolchain, workspace, pins, "/bin/uv", fake_run, logs.append)

            # exactly one tool install, correct spec
            installs = [c for c in calls if c[:2] == ["/bin/uv", "tool"]]
            self.assertEqual(len(installs), 1)
            self.assertIn("graphifyy[ollama,sql]==", " ".join(installs[0]))
            self.assertEqual(installs[0][1:3], ["tool", "install"])

            # markers written to the workspace
            self.assertTrue(
                os.path.isfile(os.path.join(workspace, "graphify-out", ".graphify_python"))
            )
            self.assertEqual(
                pathlib.Path(
                    workspace, "graphify-out", ".graphify_root"
                ).read_text(encoding="utf-8").strip(),
                ".",
            )

            # second run: receipt already names the pin -> no new install
            calls.clear()
            install_tools(toolchain, workspace, pins, "/bin/uv", fake_run, logs.append)
            self.assertEqual([c for c in calls if c[:2] == ["/bin/uv", "tool"]], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
