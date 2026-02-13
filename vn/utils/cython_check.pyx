from __future__ import annotations

from importlib import import_module
from typing import Iterable

_EXTENSIONS: tuple[str, ...] = (".so", ".pyd", ".dll")

_MODULES: tuple[str, ...] = (
    "vn.app.main",
    "vn.cli.main",
    "vn.config.project",
    "vn.ui.impl",
    "vn.runtime.impl",
    "vn.runtime.inspector",
    "vn.runtime.render",
    "vn.runtime.save",
    "vn.runtime.scene_manifest",
    "vn.runtime.script_editor",
    "vn.runtime.state",
    "vn.runtime.video",
    "vn.runtime.video_factory",
    "vn.runtime.video_vnef",
    "vn.parser.impl",
    "vn.parser.blocks",
    "vn.parser.commands",
    "vn.parser.helpers",
    "vn.parser.include",
    "vn.parser.logic",
    "vn.parser.model",
    "vn.assets.manager",
    "vn.gpu.blur_wgpu",
    "vn.script.ast",
    "vn.text.richtext",
    "vn.utils.cython_check",
)


def _is_compiled(module) -> bool:
    path = getattr(module, "__file__", "") or ""
    return path.endswith(_EXTENSIONS)


def _missing_modules(names: Iterable[str]) -> list[tuple[str, str]]:
    missing: list[tuple[str, str]] = []
    for name in names:
        module = import_module(name)
        if not _is_compiled(module):
            missing.append((name, getattr(module, "__file__", "")))
    return missing


def require_cython() -> None:
    missing = _missing_modules(_MODULES)
    if not missing:
        return
    details = ", ".join(f"{name} ({path})" for name, path in missing)
    raise RuntimeError(
        "Cython build required. Run: python setup_cython.py build_ext --inplace. "
        f"Missing compiled modules: {details}"
    )
