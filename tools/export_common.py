from __future__ import annotations

import json
import os
import platform
import shutil
import zipfile
from pathlib import Path

_ENV_REPO_ROOT = os.environ.get("CPYVN_REPO_ROOT", "").strip()
if _ENV_REPO_ROOT:
    REPO_ROOT = Path(_ENV_REPO_ROOT).expanduser().resolve()
else:
    REPO_ROOT = Path(__file__).resolve().parents[1]
SUPPORTED_TARGETS = ("linux", "windows", "macos")
VNEF_LIB_NAMES = {
    "linux": "libvnef_video.so",
    "windows": "vnef_video.dll",
    "macos": "libvnef_video.dylib",
}
RUNNER_EXEC_NAMES = {
    "linux": "cpyvn-runner",
    "windows": "cpyvn-runner.exe",
    "macos": "cpyvn-runner",
}


def detect_target() -> str:
    system = platform.system().lower()
    if "windows" in system:
        return "windows"
    if "darwin" in system or "mac" in system:
        return "macos"
    return "linux"


def normalize_target(value: str) -> str:
    text = value.strip().lower()
    if text in {"win", "windows"}:
        return "windows"
    if text in {"mac", "macos", "darwin", "osx"}:
        return "macos"
    if text in {"linux", "gnu/linux"}:
        return "linux"
    if text == "all":
        return "all"
    raise ValueError(f"Unsupported target: {value!r}")


def resolve_targets(target_value: str) -> list[str]:
    target = normalize_target(target_value)
    if target == "all":
        return list(SUPPORTED_TARGETS)
    return [target]


def vnef_lib_name(target: str) -> str:
    return VNEF_LIB_NAMES[target]


def runner_exec_name(target: str) -> str:
    return RUNNER_EXEC_NAMES[target]


def find_vnef_artifact(target: str, artifacts_root: Path) -> Path | None:
    lib_name = vnef_lib_name(target)
    candidates = [
        artifacts_root / target / lib_name,
        artifacts_root / target / "lib" / lib_name,
        artifacts_root / target / "bin" / lib_name,
        artifacts_root / lib_name,
        # Allow using exported engine folders directly as artifact source.
        artifacts_root / f"cpyvn-engine-{target}" / "runtime" / "vnef" / lib_name,
        artifacts_root / "runtime" / "vnef" / lib_name,
        REPO_ROOT / "vnef-video" / "build" / lib_name,
        REPO_ROOT / "vnef-video" / "build" / "Release" / lib_name,
        REPO_ROOT / "vnef-video" / "build" / "Debug" / lib_name,
    ]
    for path in candidates:
        if path.exists() and path.is_file():
            return path.resolve()
    return None


def ensure_clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def copy_any(src: Path, dst: Path) -> None:
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True)
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def zip_dir(src_dir: Path, zip_path: Path) -> Path:
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in src_dir.rglob("*"):
            if path.is_dir():
                continue
            zf.write(path, path.relative_to(src_dir))
    return zip_path
