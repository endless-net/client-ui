#!/usr/bin/env python3
"""Автономные проверки общего Flutter package; design запускается только явно."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

from ci import run, verify_flutter


def load_units(package: Path) -> list[str]:
    profile = json.loads((package / ".ci/profile.json").read_text(encoding="utf-8"))
    if profile.get("schema") != 1 or profile.get("component") != "endlessnet-ui":
        raise ValueError("Неизвестный профиль общей UI библиотеки")
    modules = profile.get("modules", [])
    if len(modules) != 1 or modules[0].get("path") != "." or modules[0].get("kind") != "flutter":
        raise ValueError("Требуется один собственный Flutter package")
    entries = modules[0].get("unit", [])
    if (not isinstance(entries, list) or not entries
            or any(not isinstance(item, str) or not re.fullmatch(r"test/[a-z0-9_]+_test\.dart", item) for item in entries)
            or len(entries) != len(set(entries))):
        raise ValueError("Нужны уникальные ordinary unit files; design не входит в unit")
    expected = {path.relative_to(package).as_posix() for path in (package / "test").rglob("*_test.dart")}
    if set(entries) != expected:
        raise ValueError("Unit inventory не совпадает с ordinary tests")
    return entries


def check(root: Path, *, design: bool = False) -> None:
    package = root / "packages/endlessnet_ui"
    units = load_units(package)
    verify_flutter(root)
    run(["flutter", "pub", "get", "--enforce-lockfile"], package)
    run(["dart", "format", "--output=none", "--set-exit-if-changed", "lib", "bin", "test", "tool", "test_design"], package)
    run(["flutter", "analyze", "--no-pub"], package)
    if design:
        if not list((package / "test_design/components").glob("*_test.dart")):
            raise ValueError("Component design suite отсутствует")
        run(["flutter", "test", "--no-pub", "test_design/components"], package)
    else:
        run(["dart", "run", "tool/check_test_boundaries.dart"], package)
        run(["flutter", "test", "--no-pub", *units], package)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--design", action="store_true", help="Только отдельная component design suite")
    args = parser.parse_args()
    check(Path(__file__).resolve().parents[1], design=args.design)
