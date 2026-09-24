#!/usr/bin/env python3
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
C_ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import extensions as ex  # noqa: E402

CAN_BUILD = shutil.which("make") and shutil.which("cc")


def tree(base_functions=None, libnumber="4.0.4"):
    """A throwaway c-root with the shared build rules and a tiny base catalog."""
    d = pathlib.Path(tempfile.mkdtemp())
    (d / "extensions").mkdir()
    shutil.copy(C_ROOT / "extensions" / "extension.mk", d / "extensions")
    (d / "core" / "onefit-3.1").mkdir(parents=True)
    (d / "core" / "onefit-3.1" / "makefile").write_text(f"LIBNUMBER={libnumber}\n")
    (d / "META-C.json").write_text(json.dumps(base_functions or {"BPP": {"function": "BPP(f,a,tau)"}}))
    return d


def add_template(c_root, name="example", **manifest):
    dst = c_root / "extensions" / name
    shutil.copytree(C_ROOT / "extensions" / "template", dst)
    m = json.loads((dst / "extension.json").read_text())
    m["name"] = name
    m.update(manifest)
    (dst / "extension.json").write_text(json.dumps(m))
    return dst


class Validation(unittest.TestCase):
    def setUp(self):
        self.c = tree()
        self.addCleanup(shutil.rmtree, self.c, True)

    def test_template_is_valid(self):
        e = ex.load_extension(C_ROOT / "extensions" / "template", allow_template_name=True)
        self.assertEqual(e.provides, ["ExampleGain"])

    def test_name_must_match_directory(self):
        d = add_template(self.c)
        m = json.loads((d / "extension.json").read_text())
        m["name"] = "other"
        (d / "extension.json").write_text(json.dumps(m))
        with self.assertRaisesRegex(ex.ExtensionError, "must equal its directory name"):
            ex.load_extension(d)

    def test_provides_must_match_metadata(self):
        d = add_template(self.c, provides=["ExampleGain", "Ghost"])
        with self.assertRaisesRegex(ex.ExtensionError, "not in metadata: \\['Ghost'\\]"):
            ex.load_extension(d)

    def test_missing_source_and_licence_and_bad_fields(self):
        d = add_template(self.c, sources=["nope.c"])
        with self.assertRaisesRegex(ex.ExtensionError, "source file not found"):
            ex.load_extension(d)
        d2 = add_template(self.c, name="two", license={"spdx": "MIT", "files": ["MISSING"], "redistributable": True})
        with self.assertRaisesRegex(ex.ExtensionError, "licence file not found"):
            ex.load_extension(d2)
        d3 = add_template(self.c, name="three", license={"spdx": "MIT", "files": ["LICENSE"], "redistributable": "yes"})
        with self.assertRaisesRegex(ex.ExtensionError, "redistributable must be true or false"):
            ex.load_extension(d3)
        d4 = add_template(self.c, name="four", extra_libs=["lapack"])
        with self.assertRaisesRegex(ex.ExtensionError, "-l/-L flags"):
            ex.load_extension(d4)

    def test_requires_base(self):
        e = ex.load_extension(add_template(self.c, requires_base=">=5.0"))
        with self.assertRaisesRegex(ex.ExtensionError, "requires base >=5.0, this base is 4.0.4"):
            ex.check_requires_base(e, self.c)


class SetChecks(unittest.TestCase):
    def setUp(self):
        self.c = tree()
        self.addCleanup(shutil.rmtree, self.c, True)

    def test_declared_conflict_names_both(self):
        a = ex.load_extension(add_template(self.c, "florence", conflicts=["florence-nag"]))
        b = ex.load_extension(add_template(self.c, "florence-nag", conflicts=["florence"]))
        with self.assertRaisesRegex(ex.ExtensionError, "conflicts with"):
            ex.check_set([a, b], {})

    def test_duplicate_function_across_extensions(self):
        a = ex.load_extension(add_template(self.c, "aaa"))
        b = ex.load_extension(add_template(self.c, "bbb"))
        with self.assertRaisesRegex(ex.ExtensionError, "provided by both 'aaa' and 'bbb'"):
            ex.check_set([a, b], {})

    def test_shadowing_base(self):
        a = ex.load_extension(add_template(self.c, "aaa"))
        with self.assertRaisesRegex(ex.ExtensionError, "redefines 'ExampleGain'"):
            ex.check_set([a], {"ExampleGain": {}})


@unittest.skipUnless(CAN_BUILD, "needs make and a C compiler")
class Install(unittest.TestCase):
    def setUp(self):
        self.c = tree()
        self.root = pathlib.Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.c, True)
        self.addCleanup(shutil.rmtree, self.root, True)

    def run_install(self, *extra):
        return ex.main(["install", "--c-root", str(self.c), "--root", str(self.root), *extra])

    def test_no_extensions_writes_empty_hooks_and_base_catalog(self):
        self.assertEqual(self.run_install(), 0)
        mk = (self.root / "etc" / "extensions.mk").read_text()
        self.assertIn("EXTERNAL_MODEL_LIBS := \n", mk)
        self.assertEqual(json.loads((self.c / "META-CATALOG.json").read_text()), json.loads((self.c / "META-C.json").read_text()))

    def test_build_install_test_and_catalog(self):
        add_template(self.c, extra_libs=["-lm"])
        base_before = (self.c / "META-C.json").read_text()
        self.assertEqual(self.run_install("--test"), 0)
        self.assertTrue((self.root / "lib" / "libonefit-ext-example.a").is_file())
        self.assertTrue((self.root / "include" / "ext" / "example" / "example.h").is_file())
        self.assertTrue((self.root / "share" / "extensions" / "example" / "LICENSE").is_file())
        mk = (self.root / "etc" / "extensions.mk").read_text()
        self.assertIn("-lonefit-ext-example -lm", mk)
        self.assertIn(f"-I{self.root.resolve()}/include/ext/example", mk)
        cat = json.loads((self.c / "META-CATALOG.json").read_text())
        self.assertIn("ExampleGain", cat)
        self.assertIn("BPP", cat)
        self.assertEqual((self.c / "META-C.json").read_text(), base_before, "base catalog must never be edited")
        self.assertEqual(self.run_install(), 0, "re-running must be a clean no-op")

    def test_removing_an_extension_removes_it_from_the_catalog(self):
        d = add_template(self.c)
        self.assertEqual(self.run_install(), 0)
        shutil.rmtree(d)
        self.assertEqual(self.run_install(), 0)
        self.assertNotIn("ExampleGain", json.loads((self.c / "META-CATALOG.json").read_text()))
        self.assertNotIn("example", (self.root / "etc" / "extensions.mk").read_text())

    def test_conflict_fails_before_building_anything(self):
        add_template(self.c, "florence", conflicts=["florence-nag"])
        add_template(self.c, "florence-nag", conflicts=["florence"])
        self.assertEqual(self.run_install(), 1)
        self.assertFalse((self.root / "lib").exists(), "nothing may be built when the set is invalid")

    def test_legacy_bundle_is_skipped_not_broken(self):
        legacy = self.c / "extensions" / "old"
        legacy.mkdir()
        (legacy / "Makefile").write_text("install:\n\tfalse\n")
        self.assertEqual(self.run_install(), 0)


if __name__ == "__main__":
    unittest.main()
