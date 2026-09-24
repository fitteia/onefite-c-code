#!/usr/bin/env python3
"""Build and register onefite extensions (see extensions/README.md).

  extensions.py list      [--c-root DIR]
  extensions.py validate  PATH [--c-root DIR]
  extensions.py install   --root DIR [--c-root DIR] [--test] [--include-template]

`install` validates every extensions/<name>/extension.json, refuses conflicting
or duplicate function sets, builds each with extensions/extension.mk (or the
extension's own Makefile), and writes the only two things a runtime reads:

  <root>/etc/extensions.mk   EXTERNAL_MODEL_LIBS / EXTERNAL_MODEL_INCLUDES
  <c-root>/META-CATALOG.json META-C.json + every extension's functions

META-C.json itself is never modified.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

NAME_RE = re.compile(r"^[a-z][a-z0-9_-]*$")
SOURCE_SUFFIXES = {".c", ".f"}
SKIP_DIRS = {"template"}


class ExtensionError(Exception):
    pass


class Extension:
    def __init__(self, path, data):
        self.path = path
        self.data = data
        self.name = data["name"]
        self.provides = list(data["provides"])
        self.conflicts = list(data.get("conflicts", []))
        self.sources = list(data["sources"])
        self.headers = list(data.get("headers", []))
        self.extra_libs = list(data.get("extra_libs", []))
        self.metadata = data["metadata"]
        self.tests = data.get("tests")
        self.license = data["license"]
        self.requires_base = data.get("requires_base")

    def metadata_functions(self):
        return json.loads((self.path / self.metadata).read_text())["functions"]


def _need(cond, where, msg):
    if not cond:
        raise ExtensionError(f"{where}: {msg}")


def _files_exist(base, names, where, what):
    for n in names:
        _need((base / n).is_file(), where, f"{what} file not found: {n}")


def load_extension(path, allow_template_name=False):
    path = pathlib.Path(path)
    where = str(path / "extension.json")
    _need((path / "extension.json").is_file(), str(path), "no extension.json")
    try:
        data = json.loads((path / "extension.json").read_text())
    except json.JSONDecodeError as e:
        raise ExtensionError(f"{where}: invalid JSON: {e}")
    _need(isinstance(data, dict), where, "root must be an object")
    _need(data.get("schema") == 1, where, "schema must be 1")
    for key in ("name", "version", "provides", "sources", "metadata", "license"):
        _need(key in data, where, f"missing required field '{key}'")
    name = data["name"]
    _need(isinstance(name, str) and NAME_RE.match(name), where,
          "name must match [a-z][a-z0-9_-]*")
    if not (allow_template_name and path.name in SKIP_DIRS):
        _need(name == path.name, where,
              f"name '{name}' must equal its directory name '{path.name}'")
    _need(isinstance(data["version"], str), where, "version must be a string")
    for key in ("provides", "sources", "headers", "conflicts", "extra_libs"):
        if key in data:
            _need(isinstance(data[key], list) and all(isinstance(x, str) for x in data[key]),
                  where, f"{key} must be a list of strings")
    _need(data["provides"], where, "provides must not be empty")
    _need(data["sources"], where, "sources must not be empty")
    for s in data["sources"]:
        _need(pathlib.Path(s).suffix in SOURCE_SUFFIXES, where,
              f"unsupported source type: {s} (use .c or .f)")
    _files_exist(path, data["sources"], where, "source")
    _files_exist(path, data.get("headers", []), where, "header")
    for lib in data.get("extra_libs", []):
        _need(lib.startswith(("-l", "-L")), where, f"extra_libs entries must be -l/-L flags: {lib}")
    lic = data["license"]
    _need(isinstance(lic, dict) and isinstance(lic.get("spdx"), str) and lic["spdx"], where,
          "license.spdx is required")
    _need(isinstance(lic.get("redistributable"), bool), where,
          "license.redistributable must be true or false")
    _need(isinstance(lic.get("files"), list) and lic["files"], where,
          "license.files must list at least one licence/notice file")
    _files_exist(path, lic["files"], where, "licence")
    _need((path / data["metadata"]).is_file(), where, f"metadata file not found: {data['metadata']}")
    if data.get("tests"):
        _need((path / data["tests"]).is_file(), where, f"tests script not found: {data['tests']}")
    ext = Extension(path, data)
    try:
        functions = ext.metadata_functions()
    except (json.JSONDecodeError, KeyError, TypeError):
        raise ExtensionError(f"{path / data['metadata']}: must be an object with a 'functions' object")
    _need(isinstance(functions, dict), where, "metadata 'functions' must be an object")
    if set(functions) != set(ext.provides):
        missing = sorted(set(ext.provides) - set(functions))
        extra = sorted(set(functions) - set(ext.provides))
        raise ExtensionError(
            f"{where}: 'provides' and {data['metadata']} disagree"
            + (f"; not in metadata: {missing}" if missing else "")
            + (f"; not in provides: {extra}" if extra else ""))
    return ext


def base_version(c_root):
    for rel in ("core/onefit-3.1/makefile", "local/makefile"):
        p = pathlib.Path(c_root) / rel
        if p.is_file():
            m = re.search(r"^LIBNUMBER\s*=\s*([0-9][0-9.]*)", p.read_text(), re.M)
            if m:
                return m.group(1)
    return None


def _ver(s):
    return tuple(int(x) for x in s.split("."))


def check_requires_base(ext, c_root):
    if not ext.requires_base:
        return
    m = re.match(r"^(>=|<=|==|>|<)\s*([0-9][0-9.]*)$", ext.requires_base.strip())
    if not m:
        raise ExtensionError(f"{ext.name}: requires_base must look like '>=4.0.4'")
    have = base_version(c_root)
    if have is None:
        return
    op, want = m.groups()
    a, b = _ver(have), _ver(want)
    ok = {">=": a >= b, "<=": a <= b, "==": a == b, ">": a > b, "<": a < b}[op]
    if not ok:
        raise ExtensionError(f"{ext.name} requires base {ext.requires_base}, this base is {have}")


def discover(ext_dir, include_template=False):
    """Returns (extensions, legacy_dirs)."""
    exts, legacy = [], []
    ext_dir = pathlib.Path(ext_dir)
    if not ext_dir.is_dir():
        return exts, legacy
    for d in sorted(ext_dir.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        if d.name in SKIP_DIRS and not include_template:
            continue
        if (d / "extension.json").is_file():
            exts.append(load_extension(d, allow_template_name=include_template))
        elif (d / "Makefile").is_file():
            legacy.append(d)
    return exts, legacy


def base_functions(c_root):
    p = pathlib.Path(c_root) / "META-C.json"
    if not p.is_file():
        return {}
    data = json.loads(p.read_text())
    if not isinstance(data, dict):
        raise ExtensionError(f"{p}: metadata root must be an object")
    return data


def check_set(exts, base):
    names = {e.name: e for e in exts}
    for e in exts:
        for c in e.conflicts:
            if c in names:
                raise ExtensionError(
                    f"extension '{e.name}' conflicts with '{c}' - install only one of them "
                    f"(remove extensions/{c} or extensions/{e.name})")
    owner = {}
    for e in exts:
        for fn in e.provides:
            if fn in owner:
                raise ExtensionError(
                    f"function '{fn}' is provided by both '{owner[fn]}' and '{e.name}'")
            if fn in base:
                raise ExtensionError(
                    f"extension '{e.name}' redefines '{fn}', which the base catalog already has")
            owner[fn] = e.name


def build(ext, c_root, root):
    env = dict(os.environ)
    if (ext.path / "Makefile").is_file():
        cmd = ["make", "-C", str(ext.path), "install",
               f"C_ROOT={c_root}", f"ROOT={root}"]
    else:
        cmd = ["make", "-f", str(pathlib.Path(c_root) / "extensions" / "extension.mk"),
               "-C", str(ext.path),
               f"EXT_NAME={ext.name}",
               f"EXT_SOURCES={' '.join(ext.sources)}",
               f"EXT_HEADERS={' '.join(ext.headers)}",
               f"EXT_LICENSE_FILES={' '.join(ext.license['files'])}",
               f"EXT_METADATA={ext.metadata}",
               f"C_ROOT={c_root}", f"ROOT={root}", "install"]
    print(f"===> building extension {ext.name} {ext.data['version']}", file=sys.stderr)
    subprocess.run(cmd, check=True, env=env)


def run_tests(ext, c_root, root):
    if not ext.tests:
        return
    print(f"===> testing extension {ext.name}", file=sys.stderr)
    env = dict(os.environ, C_ROOT=str(c_root), ROOT=str(root), EXT_NAME=ext.name)
    subprocess.run(["sh", ext.tests], cwd=ext.path, check=True, env=env)


def write_extensions_mk(root, exts):
    libs, incs = [], []
    for e in exts:
        libs.append(f"-lonefit-ext-{e.name}")
        incs.append(f"-I{root}/include/ext/{e.name}")
    for e in exts:
        for l in e.extra_libs:
            if l not in libs:
                libs.append(l)
    p = pathlib.Path(root) / "etc" / "extensions.mk"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        "# Generated by onefite-c-code tools/extensions.py - do not edit.\n"
        f"EXTERNAL_MODEL_LIBS := {' '.join(libs)}\n"
        f"EXTERNAL_MODEL_INCLUDES := {' '.join(incs)}\n")
    return p


def write_catalog(c_root, exts, base):
    merged = dict(base)
    for e in exts:
        merged.update(e.metadata_functions())
    p = pathlib.Path(c_root) / "META-CATALOG.json"
    p.write_text(json.dumps(merged, indent=4, ensure_ascii=False) + "\n")
    return p


def cmd_list(args):
    exts, legacy = discover(pathlib.Path(args.c_root) / "extensions", args.include_template)
    for e in exts:
        tag = "redistributable" if e.license["redistributable"] else "NOT redistributable"
        print(f"{e.name} {e.data['version']}  [{e.license['spdx']}, {tag}]  provides: {', '.join(e.provides)}")
    for d in legacy:
        print(f"{d.name}  (legacy bundle: no extension.json, installed by doctor's older path)")
    if not exts and not legacy:
        print("(no extensions installed)")


def cmd_validate(args):
    ext = load_extension(args.path, allow_template_name=True)
    check_requires_base(ext, args.c_root)
    check_set([ext], base_functions(args.c_root))
    print(f"ok: {ext.name} {ext.data['version']} provides {', '.join(ext.provides)}")


def cmd_install(args):
    c_root = pathlib.Path(args.c_root).resolve()
    root = pathlib.Path(args.root).resolve()
    exts, legacy = discover(c_root / "extensions", args.include_template)
    base = base_functions(c_root)
    for e in exts:
        check_requires_base(e, c_root)
    check_set(exts, base)
    for d in legacy:
        print(f"===> skipping legacy bundle {d.name} (no extension.json)", file=sys.stderr)
    for e in exts:
        if not e.license["redistributable"]:
            print(f"===> NOTE: '{e.name}' is not redistributable ({e.license['spdx']}); "
                  f"see {e.path / e.license['files'][0]}", file=sys.stderr)
        build(e, c_root, root)
        if args.test:
            run_tests(e, c_root, root)
    write_extensions_mk(root, exts)
    write_catalog(c_root, exts, base)
    print(f"===> {len(exts)} extension(s) installed into {root}", file=sys.stderr)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("list", "validate", "install"):
        sp = sub.add_parser(name)
        sp.add_argument("--c-root", default=str(pathlib.Path(__file__).resolve().parent.parent))
        sp.add_argument("--include-template", action="store_true")
        if name == "validate":
            sp.add_argument("path")
        if name == "install":
            sp.add_argument("--root", required=True)
            sp.add_argument("--test", action="store_true")
    args = ap.parse_args(argv)
    try:
        {"list": cmd_list, "validate": cmd_validate, "install": cmd_install}[args.cmd](args)
    except ExtensionError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(f"error: build step failed: {' '.join(map(str, e.cmd))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
