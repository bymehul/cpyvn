# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False
from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

from ..app import run
from ..config import UiConfig, load_project

cpdef bint _env_debug():
    """Return True if the CPYVN_DEBUG env-var is set to a truthy value."""
    cdef str value
    cdef object raw

    raw = os.getenv("CPYVN_DEBUG")
    if not raw:
        return False
    value = raw.strip().lower()
    return value not in {"0", "false", "no", "off"}

class _ColorFormatter(logging.Formatter):
    COLORS = {
        logging.DEBUG:    "\x1b[36m",
        logging.INFO:     "\x1b[32m",
        logging.WARNING:  "\x1b[33m",
        logging.ERROR:    "\x1b[31m",
        logging.CRITICAL: "\x1b[31m",
    }
    RESET = "\x1b[0m"

    def __init__(self, use_color: bool) -> None:
        super().__init__("%(levelname)s:%(name)s:%(message)s")
        self.use_color = use_color

    def format(self, record: logging.LogRecord) -> str:
        cdef str message, color
        message = super().format(record)
        if not self.use_color:
            return message
        color = self.COLORS.get(record.levelno, "")
        if not color:
            return message
        return f"{color}{message}{self.RESET}"

cpdef void _configure_logging(bint debug):
    cdef object handler, root
    cdef bint use_color
    cdef int level

    level = logging.DEBUG if debug else logging.WARNING
    handler = logging.StreamHandler()
    use_color = handler.stream.isatty() if hasattr(handler.stream, "isatty") else False
    handler.setFormatter(_ColorFormatter(use_color))
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)

cpdef void main():
    cdef object parser, args, project, script_path, project_root, ui, project_arg
    cdef bint project_arg_is_file
    cdef int width, height, fps
    cdef bint debug
    cdef dict asset_dirs

    parser = argparse.ArgumentParser(description="cpyvn - minimal VN engine")
    parser.add_argument("--project", help="Path to project directory (contains project.json)")
    parser.add_argument("script", nargs="?", help="Path to script file (optional override)")
    parser.add_argument("--width",  type=int, help="Window width")
    parser.add_argument("--height", type=int, help="Window height")
    parser.add_argument("--fps",    type=int, help="Target FPS")
    parser.add_argument("--debug",  action="store_true", help="Enable debug logging")
    args = parser.parse_args()

    if args.project:
        project_arg = Path(args.project).resolve()
        project_arg_is_file = project_arg.exists() and project_arg.is_file()
        if project_arg_is_file:
            project = load_project(project_arg.parent)
        else:
            project = load_project(project_arg)
        debug = args.debug or _env_debug() or project.debug
        _configure_logging(debug)
        if args.script:
            script_path = Path(args.script).resolve()
        elif project_arg_is_file:
            script_path = project_arg
        else:
            script_path = project.entry
        width  = args.width  or project.window.width
        height = args.height or project.window.height
        fps    = args.fps    or project.window.fps
        run(
            script_path=script_path,
            project_root=project.root,
            title=project.name,
            width=width,
            height=height,
            fps=fps,
            resizable=project.window.resizable,
            asset_dirs=project.assets,
            save_dir=project.saves_dir,
            ui=project.ui,
            prefetch_path=project.prefetch,
            wgpu_blur=project.wgpu_blur,
            wgpu_backend=project.wgpu_backend,
            video_backend=project.video_backend,
            video_audio=project.video_audio,
            video_framedrop=project.video_framedrop,
            features=project.features,
            dev_mode=debug,
        )
        return

    if args.script:
        debug = args.debug or _env_debug()
        _configure_logging(debug)
        script_path  = Path(args.script).resolve()
        project_root = script_path.parent
        width  = args.width  or 1280
        height = args.height or 720
        fps    = args.fps    or 60
        asset_dirs = {
            "bg":      project_root / "assets" / "bg",
            "sprites": project_root / "assets" / "sprites",
            "audio":   project_root / "assets" / "audio",
            "video":   project_root / "assets" / "video",
        }
        ui = UiConfig()
        run(
            script_path=script_path,
            project_root=project_root,
            title=script_path.stem,
            width=width,
            height=height,
            fps=fps,
            resizable=True,
            asset_dirs=asset_dirs,
            save_dir=project_root / "saves",
            ui=ui,
            wgpu_blur=False,
            wgpu_backend=None,
            video_backend="auto",
            video_audio=True,
            video_framedrop="auto",
            features={},
            dev_mode=debug,
        )
        return

    parser.print_help()


if __name__ == "__main__":
    main()
