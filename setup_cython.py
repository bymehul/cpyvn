import shutil

from setuptools import Extension, setup
from Cython.Build import cythonize


CORE_MODULES: tuple[str, ...] = (
    "vn.app.main",
    "vn.cli.main",
    "vn.config.project",
    "vn.ui.impl",
    "vn.runtime.impl",
    "vn.runtime.inspector",
    "vn.runtime.pause_menu",
    "vn.runtime.render",
    "vn.runtime.save",
    "vn.runtime.scene_manifest",
    "vn.runtime.script_editor",
    "vn.runtime.state",
    "vn.runtime.title_menu",
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

MANUAL_PYX_MODULES: set[str] = set(CORE_MODULES)


def _sync_py_to_pyx() -> None:
    for module in CORE_MODULES:
        if module in MANUAL_PYX_MODULES:
            continue
        rel = module.replace(".", "/")
        py_path = f"{rel}.py"
        pyx_path = f"{rel}.pyx"
        with open(py_path, "rb") as src:
            data = src.read()
        try:
            with open(pyx_path, "rb") as existing:
                if existing.read() == data:
                    continue
        except FileNotFoundError:
            pass
        shutil.copy2(py_path, pyx_path)


_sync_py_to_pyx()
core_extensions: list[Extension] = []
parser_extensions: list[Extension] = []
for module in CORE_MODULES:
    ext = Extension(module, [f"{module.replace('.', '/')}.pyx"])
    if module.startswith("vn.parser."):
        parser_extensions.append(ext)
    else:
        core_extensions.append(ext)

ext_modules = []
if core_extensions:
    ext_modules.extend(
        cythonize(
            core_extensions,
            compiler_directives={
                "language_level": "3",
                "binding": True,
                "infer_types": True,
            },
        )
    )
if parser_extensions:
    ext_modules.extend(
        cythonize(
            parser_extensions,
            compiler_directives={
                "language_level": "3",
                "binding": True,
                "infer_types": False,
                "initializedcheck": True,
                "annotation_typing": False,
            },
        )
    )

setup(name="cpyvn-cython", ext_modules=ext_modules)
