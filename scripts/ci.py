#!/usr/bin/env python3
"""Автономные проверки и выпуск desktop-каркаса Client UI."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile


FLUTTER_VERSION = "3.47.7"
FLUTTER_REVISION = "abaf9c523780a608bd46686fd5e53740a07077f8"
DART_VERSION = "3.13.5"
REPOSITORY = "endless-net/client-ui"
TARGETS = {"windows-amd64", "linux-amd64", "darwin-amd64", "darwin-arm64"}
TAG = re.compile(r"v0\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")


def run(args: list[str], cwd: Path, *, capture: bool = False,
        env: dict[str, str] | None = None) -> str:
    command = list(args)
    if os.name == "nt" and command[0] in {"flutter", "dart"}:
        command = ["cmd.exe", "/d", "/c", *command]
    print("+ " + " ".join(args), file=sys.stderr, flush=True)
    result = subprocess.run(command, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None, env=env)
    return result.stdout.strip() if capture else ""


def inside(root: Path, value: str) -> Path:
    if not value or Path(value).is_absolute() or ".." in Path(value).parts:
        raise ValueError("Путь должен быть относительным и оставаться в checkout")
    result = root.joinpath(value).resolve(strict=True)
    if not result.is_relative_to(root.resolve()):
        raise ValueError("Путь выходит из checkout")
    return result


def load_profile(root: Path) -> dict:
    profile = json.loads((root / ".ci/profile.json").read_text(encoding="utf-8"))
    if profile.get("schema") != 1 or profile.get("component") != "client-ui":
        raise ValueError("Неизвестный профиль Client UI")
    modules = profile.get("modules", [])
    if len(modules) != 1 or modules[0].get("kind") != "flutter":
        raise ValueError("Профиль должен явно объявлять собственный Flutter package")
    module = inside(root, modules[0]["path"])
    if not (module / "pubspec.yaml").is_file() or not (module / "pubspec.lock").is_file():
        raise ValueError("Отсутствует объявленный package или lockfile")
    units = modules[0].get("unit")
    if not isinstance(units, list) or not all(isinstance(item, str) for item in units):
        raise ValueError("Unit entrypoints должны быть явным списком файлов")
    for entry in units:
        if not inside(module, entry).is_file():
            raise ValueError("Отсутствует unit entrypoint")
    actual_targets: set[str] = set()
    names: set[str] = set()
    for artifact in profile.get("artifacts", []):
        target = artifact.get("target", {})
        key = f"{target.get('os')}-{target.get('arch')}"
        if (key not in TARGETS or key in actual_targets
                or artifact.get("release") != "runtime"
                or artifact.get("kind") != "flutter-desktop"
                or artifact.get("module") != modules[0]["path"]):
            raise ValueError("Неверный или повторный desktop target")
        name = artifact.get("name", "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name) or name in names:
            raise ValueError("Неверное или повторное имя архива")
        actual_targets.add(key)
        names.add(name)
    if actual_targets != TARGETS:
        raise ValueError("Профиль должен содержать все четыре desktop target")
    return profile


def verify_flutter(root: Path) -> None:
    if (root / ".flutter-version").read_text(encoding="utf-8").strip() != FLUTTER_VERSION:
        raise ValueError("Pin Flutter не совпадает с CI")
    version = json.loads(run(["flutter", "--version", "--machine"], root, capture=True))
    if (version.get("frameworkVersion") != FLUTTER_VERSION
            or version.get("frameworkRevision") != FLUTTER_REVISION
            or version.get("dartSdkVersion") != DART_VERSION):
        raise ValueError("Требуется закреплённый Flutter/Dart SDK")


def check(root: Path) -> None:
    profile = load_profile(root)
    verify_flutter(root)
    module = inside(root, profile["modules"][0]["path"])
    run(["flutter", "pub", "get", "--enforce-lockfile"], module)
    run(["dart", "format", "--output=none", "--set-exit-if-changed", "lib"], module)
    run(["flutter", "analyze", "--no-pub"], module)
    units = profile["modules"][0]["unit"]
    if units:
        run(["flutter", "test", "--no-pub", *units], module)
    else:
        print("UNIT_ABSENT: пустой UI не имеет unit-сценариев; покрытие не заявляется.")
    run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "scripts/tests"], root)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def archive(source: Path, output: Path, *, windows: bool) -> None:
    """Нормализует metadata архива; symlink может указывать только внутрь bundle."""
    paths = sorted(source.rglob("*"), key=lambda item: item.relative_to(source).as_posix())
    output.parent.mkdir(parents=True, exist_ok=True)
    for path in paths:
        if path.is_symlink() and not path.resolve().is_relative_to(source.resolve()):
            raise ValueError("Symlink выходит из bundle")
    if windows:
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
            for path in paths:
                if path.is_dir():
                    continue
                if path.is_symlink():
                    raise ValueError("Windows bundle не должен содержать symlink")
                info = zipfile.ZipInfo(path.relative_to(source).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                bundle.writestr(info, path.read_bytes())
    else:
        with output.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as bundle:
                for path in paths:
                    info = bundle.gettarinfo(str(path), arcname=path.relative_to(source).as_posix())
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = 0
                    info.pax_headers = {}
                    if info.isfile():
                        info.mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
                        with path.open("rb") as stream:
                            bundle.addfile(info, stream)
                    elif info.isdir():
                        info.mode = 0o755
                        bundle.addfile(info)
                    elif info.issym():
                        bundle.addfile(info)
                    else:
                        raise ValueError("Bundle содержит неподдерживаемый тип файла")


def verify_binary(path: Path, target: str, root: Path) -> None:
    header = path.read_bytes()[:4096]
    if target == "windows-amd64":
        offset = struct.unpack_from("<I", header, 0x3C)[0]
        if header[:2] != b"MZ" or header[offset:offset + 6] != b"PE\0\0\x64\x86":
            raise ValueError("Ожидался Windows amd64 PE")
    elif target == "linux-amd64":
        if header[:5] != b"\x7fELF\x02" or struct.unpack_from("<H", header, 18)[0] != 62:
            raise ValueError("Ожидался Linux amd64 ELF")
    else:
        expected = "x86_64" if target == "darwin-amd64" else "arm64"
        if run(["lipo", "-archs", str(path)], root, capture=True).split() != [expected]:
            raise ValueError("Неверная архитектура macOS executable")


def build(root: Path, target: str, out: Path) -> None:
    profile = load_profile(root)
    artifact = next(item for item in profile["artifacts"]
                    if f"{item['target']['os']}-{item['target']['arch']}" == target)
    expected_os = artifact["target"]["os"]
    actual_os = {"Windows": "windows", "Linux": "linux", "Darwin": "darwin"}.get(platform.system())
    if actual_os != expected_os:
        raise ValueError("Native Flutter target должен собираться на соответствующей ОС")
    verify_flutter(root)
    module = inside(root, artifact["module"])
    run(["flutter", "pub", "get", "--enforce-lockfile"], module)
    environment = os.environ.copy()
    if expected_os == "darwin":
        environment["FLUTTER_XCODE_ARCHS"] = "x86_64" if target.endswith("amd64") else "arm64"
        environment["FLUTTER_XCODE_CODE_SIGNING_ALLOWED"] = "NO"
        platform_name = "macos"
    else:
        platform_name = expected_os
    run(["flutter", "build", platform_name, "--release", "--no-pub"], module, env=environment)
    if expected_os == "windows":
        source = module / "build/windows/x64/runner/Release"
        executable = source / "endlessnet_client_ui.exe"
    elif expected_os == "linux":
        source = module / "build/linux/x64/release/bundle"
        executable = source / "endlessnet_client_ui"
    else:
        source = module / "build/macos/Build/Products/Release"
        applications = list(source.glob("*.app"))
        if len(applications) != 1:
            raise ValueError("Ожидался ровно один macOS app bundle")
        executable = applications[0] / "Contents/MacOS/endlessnet_client_ui"
        # Release directory содержит также промежуточные frameworks вне .app.
        source = applications[0].parent / ".ci-bundle"
        source.mkdir(exist_ok=True)
        destination = source / applications[0].name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(applications[0], destination, symlinks=True)
    verify_binary(executable, target, root)
    suffix = ".zip" if expected_os == "windows" else ".tar.gz"
    path = out / (artifact["name"] + suffix)
    archive(source, path, windows=expected_os == "windows")
    digest = sha256(path)
    identity = {"repository": REPOSITORY, "commit": run(["git", "rev-parse", "HEAD"], root, capture=True),
                "dirty": bool(run(["git", "status", "--porcelain"], root, capture=True)),
                "target": target, "archive": path.name, "sha256": digest,
                "flutter": FLUTTER_VERSION, "dart": DART_VERSION}
    (out / (path.name + ".json")).write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    (out / (path.name + ".sha256")).write_text(f"{digest}  {path.name}\n", encoding="utf-8")
    print(json.dumps(identity))


def validate_event(environment: dict[str, str], head: str) -> str:
    ref = environment.get("GITHUB_REF", "")
    tag = ref.removeprefix("refs/tags/")
    if (environment.get("GITHUB_EVENT_NAME") != "push" or not ref.startswith("refs/tags/")
            or not TAG.fullmatch(tag) or environment.get("GITHUB_REPOSITORY") != REPOSITORY
            or environment.get("GITHUB_SHA") != head):
        raise ValueError("Publish требует push обычного v0-тега на exact source commit")
    return tag


def gh_json(root: Path, endpoint: str) -> dict:
    return json.loads(run(["gh", "api", endpoint], root, capture=True))


def release_view(root: Path, tag: str) -> dict:
    # REST releases/tags разрешает опубликованные теги, а gh также находит draft.
    value = json.loads(run(["gh", "release", "view", tag, "--repo", REPOSITORY, "--json",
                            "tagName,targetCommitish,isDraft,isPrerelease,assets"], root, capture=True))
    if value["tagName"] != tag:
        raise ValueError("Release tag не совпадает")
    return {"tag_name": value["tagName"], "target_commitish": value["targetCommitish"],
            "draft": value["isDraft"], "prerelease": value["isPrerelease"], "assets": value["assets"]}


def verify_remote_tag(root: Path, tag: str, head: str) -> None:
    ref = gh_json(root, f"repos/{REPOSITORY}/git/ref/tags/{tag}")["object"]
    seen: set[str] = set()
    while ref["type"] == "tag":
        if ref["sha"] in seen or len(seen) >= 8:
            raise ValueError("Некорректная цепочка annotated tag")
        seen.add(ref["sha"])
        ref = gh_json(root, f"repos/{REPOSITORY}/git/tags/{ref['sha']}")["object"]
    if ref.get("type") != "commit" or ref.get("sha") != head:
        raise ValueError("Remote tag не указывает на проверенный commit")


def reconcile_assets(existing: dict[str, str], expected: dict[str, str], *, draft: bool) -> list[str]:
    if set(existing) - set(expected):
        raise ValueError("Существующий release содержит неожиданные assets")
    if any(expected[name] != digest for name, digest in existing.items()):
        raise ValueError("Опубликованные bytes конфликтуют; overwrite запрещён")
    missing = sorted(set(expected) - set(existing))
    if missing and not draft:
        raise ValueError("Опубликованный release неполон; нельзя дописывать его молча")
    return missing


def publish(root: Path, out: Path) -> None:
    profile = load_profile(root)
    head = run(["git", "rev-parse", "HEAD"], root, capture=True)
    tag = validate_event(dict(os.environ), head)
    verify_remote_tag(root, tag, head)
    assets: dict[str, str] = {}
    for artifact in profile["artifacts"]:
        suffix = ".zip" if artifact["target"]["os"] == "windows" else ".tar.gz"
        path = out / (artifact["name"] + suffix)
        identity = json.loads((out / (path.name + ".json")).read_text(encoding="utf-8"))
        digest = sha256(path)
        target = f"{artifact['target']['os']}-{artifact['target']['arch']}"
        if (identity.get("commit") != head or identity.get("repository") != REPOSITORY
                or identity.get("archive") != path.name or identity.get("sha256") != digest
                or identity.get("target") != target
                or identity.get("dirty", True)):
            raise ValueError("Архив не принадлежит exact source или повреждён")
        assets[path.name] = digest
    checksums = out / "checksums.txt"
    checksums.write_text("".join(f"{assets[name]}  {name}\n" for name in sorted(assets)), encoding="utf-8")
    identity_path = out / "source.json"
    identity_path.write_text(json.dumps({"repository": REPOSITORY, "commit": head, "tag": tag,
                                         "flutter": FLUTTER_VERSION, "dart": DART_VERSION},
                                        sort_keys=True, indent=2) + "\n", encoding="utf-8")
    assets[checksums.name] = sha256(checksums)
    assets[identity_path.name] = sha256(identity_path)
    # Список endpoint даёт отсутствие release без маскировки 403/5xx как 404.
    releases = json.loads(run(["gh", "api", "--paginate", "--slurp", f"repos/{REPOSITORY}/releases"],
                             root, capture=True))
    matches = [item for page in releases for item in page if item["tag_name"] == tag]
    if len(matches) > 1:
        raise ValueError("Несколько release с одним тегом")
    if not matches:
        run(["gh", "release", "create", tag, "--repo", REPOSITORY, "--draft", "--verify-tag",
             "--target", head, "--title", tag, "--generate-notes", "--notes", f"Source commit: {head}"], root)
        release = release_view(root, tag)
    else:
        release = matches[0]
    if release.get("prerelease") or release.get("target_commitish") != head:
        raise ValueError("Существующий release имеет другую identity")
    with tempfile.TemporaryDirectory(prefix="client-ui-release-") as directory:
        downloaded = Path(directory)
        if release["assets"]:
            run(["gh", "release", "download", tag, "--repo", REPOSITORY, "--dir", str(downloaded)], root)
        existing = {path.name: sha256(path) for path in downloaded.iterdir() if path.is_file()}
        missing = reconcile_assets(existing, assets, draft=release["draft"])
    for name in missing:
        run(["gh", "release", "upload", tag, str(out / name), "--repo", REPOSITORY], root)
    verify_remote_tag(root, tag, head)
    if release["draft"]:
        with tempfile.TemporaryDirectory(prefix="client-ui-verify-") as directory:
            downloaded = Path(directory)
            run(["gh", "release", "download", tag, "--repo", REPOSITORY, "--dir", str(downloaded)], root)
            verified = {path.name: sha256(path) for path in downloaded.iterdir() if path.is_file()}
            if reconcile_assets(verified, assets, draft=True):
                raise ValueError("Draft upload не завершён")
        run(["gh", "release", "edit", tag, "--repo", REPOSITORY, "--draft=false"], root)
    final = release_view(root, tag)
    if final["draft"] or final["prerelease"] or final.get("target_commitish") != head:
        raise ValueError("Published state не подтверждён")
    print(f"PUBLISHED {REPOSITORY} {tag} {head}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "build", "publish"])
    parser.add_argument("--target", choices=sorted(TARGETS))
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--out", type=Path, default=Path(".artifacts"))
    options = parser.parse_args()
    root = options.root.resolve(strict=True)
    out = options.out if options.out.is_absolute() else root / options.out
    if options.command == "check":
        check(root)
    elif options.command == "build":
        if options.target is None:
            parser.error("build требует --target")
        build(root, options.target, out)
    else:
        publish(root, out)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"CI_FAILED: {error}", file=sys.stderr)
        sys.exit(1)
