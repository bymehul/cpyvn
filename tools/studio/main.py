#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import queue
import shlex
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

if getattr(sys, "frozen", False):
    _bundle_root = Path(getattr(sys, "_MEIPASS", Path(sys.executable).resolve().parent)).resolve()
    os.environ.setdefault("CPYVN_REPO_ROOT", str(_bundle_root))

try:
    from tools.studio.templates import create_project_tree, slugify
    from tools.export_common import copy_any, ensure_clean_dir, normalize_target, zip_dir
    from tools.export_engine import export_engine as run_export_engine
    from tools.export_game import export_game as run_export_game
except ImportError:
    if __package__:
        from .templates import create_project_tree, slugify
        from ..export_common import copy_any, ensure_clean_dir, normalize_target, zip_dir
        from ..export_engine import export_engine as run_export_engine
        from ..export_game import export_game as run_export_game
    else:
        tools_root = Path(__file__).resolve().parents[1]
        if str(tools_root) not in sys.path:
            sys.path.insert(0, str(tools_root))
        from templates import create_project_tree, slugify
        from export_common import copy_any, ensure_clean_dir, normalize_target, zip_dir
        from export_engine import export_engine as run_export_engine
        from export_game import export_game as run_export_game


class StudioApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("cpyvn Studio")
        self.geometry("980x700")
        self.minsize(860, 600)

        self.repo_root = self._resolve_repo_root()
        self._running = False
        self._run_queue: queue.Queue[object] = queue.Queue()
        self._run_buttons: list[ttk.Button] = []
        self._active_process: subprocess.Popen[str] | None = None
        self.stop_button: ttk.Button | None = None

        self._configure_style()
        self._init_vars()
        self._build_ui()

    def _resolve_repo_root(self) -> Path:
        env_root = os.environ.get("CPYVN_REPO_ROOT", "").strip()
        if env_root:
            return Path(env_root).expanduser().resolve()
        if getattr(sys, "frozen", False):
            base = getattr(sys, "_MEIPASS", "")
            if base:
                return Path(str(base)).resolve()
            return Path(sys.executable).resolve().parent
        return Path(__file__).resolve().parents[2]

    def _is_frozen_runtime(self) -> bool:
        return bool(getattr(sys, "frozen", False))

    def _detect_workspace_root(self) -> Path:
        base = Path.cwd().resolve() if self._is_frozen_runtime() else self.repo_root
        probe_roots = [base]
        if self._is_frozen_runtime():
            probe_roots.append(Path(sys.executable).resolve().parent)
        for root in probe_roots:
            for node in [root, *root.parents]:
                if (node / "games").exists():
                    return node.resolve()
        return base

    def _studio_task_command(self, task: str, *parts: str) -> list[str]:
        return [str(sys.executable), "--studio-task", task, *parts]

    def _configure_style(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("Root.TFrame", background="#131722")
        style.configure("Card.TFrame", background="#1d2333")
        style.configure("CardTitle.TLabel", background="#1d2333", foreground="#f2f6ff", font=("TkDefaultFont", 11, "bold"))
        style.configure("Body.TLabel", background="#1d2333", foreground="#d9e2f2")
        style.configure("Hint.TLabel", background="#1d2333", foreground="#9fb0cc")
        style.configure("Mode.TLabel", background="#131722", foreground="#c7d3eb")

    def _init_vars(self) -> None:
        workspace_root = self._detect_workspace_root()
        games_dir = workspace_root / "games"

        self.new_parent_var = tk.StringVar(value=str(games_dir))
        self.new_name_var = tk.StringVar(value="new_game")
        self.new_width_var = tk.StringVar(value="1280")
        self.new_height_var = tk.StringVar(value="720")
        self.new_fps_var = tk.StringVar(value="60")
        self.new_resizable_var = tk.BooleanVar(value=True)
        self.new_title_menu_var = tk.BooleanVar(value=True)
        self.new_pause_menu_var = tk.BooleanVar(value=True)
        self.new_status_var = tk.StringVar(value="Ready.")

        self.export_project_var = tk.StringVar(value=str(self.repo_root / "games" / "demo"))
        self.export_target_var = tk.StringVar(value="host")
        self.export_artifacts_var = tk.StringVar(value="vnef-video/artifacts")
        self.export_engine_out_var = tk.StringVar(value="dist/exports/engine")
        self.export_game_out_var = tk.StringVar(value="dist/exports/game")

        if self._is_frozen_runtime():
            demo_path = games_dir / "demo"
            self.export_project_var.set(str(demo_path if demo_path.exists() else workspace_root))

    def _resolve_user_path(self, value: str, default: str, base_dir: Path | None = None) -> str:
        text = value.strip() if value else ""
        raw = text or default
        path = Path(raw).expanduser()
        if not path.is_absolute():
            root = (base_dir or Path.cwd().resolve()).resolve()
            path = (root / path).resolve()
        return str(path)

    def _project_workspace_root(self) -> Path:
        project_text = self.export_project_var.get().strip()
        if not project_text:
            return self._detect_workspace_root()
        project_path = Path(project_text).expanduser()
        if not project_path.is_absolute():
            project_path = (Path.cwd().resolve() / project_path).resolve()
        parts = list(project_path.parts)
        if "games" in parts:
            idx = parts.index("games")
            if idx > 0:
                return Path(*parts[:idx]).resolve()
        if project_path.exists():
            return project_path.parent.resolve()
        return self._detect_workspace_root()

    def _auto_artifacts_root(self, base_dir: Path | None = None) -> str:
        candidates: list[Path] = []
        explicit = self.export_artifacts_var.get().strip()
        if explicit:
            candidates.append(Path(explicit).expanduser())
        if base_dir is not None:
            candidates.append((base_dir / "dist" / "exports" / "engine").resolve())
            candidates.append((base_dir / "vnef-video" / "artifacts").resolve())
        candidates.append((self.repo_root / "dist" / "exports" / "engine").resolve())
        candidates.append((self.repo_root / "vnef-video" / "artifacts").resolve())

        seen: set[Path] = set()
        normalized: list[Path] = []
        for item in candidates:
            path = item if item.is_absolute() else (Path.cwd().resolve() / item).resolve()
            if path in seen:
                continue
            seen.add(path)
            normalized.append(path)

        for path in normalized:
            if path.exists():
                self.export_artifacts_var.set(str(path))
                return str(path)

        fallback = str(normalized[0] if normalized else (self.repo_root / "dist" / "exports" / "engine").resolve())
        self.export_artifacts_var.set(fallback)
        return fallback

    def _build_ui(self) -> None:
        root = ttk.Frame(self, style="Root.TFrame", padding=14)
        root.pack(fill="both", expand=True)

        top = ttk.Frame(root, style="Root.TFrame")
        top.pack(fill="x")
        ttk.Label(
            top,
            text="cpyvn Studio",
            font=("TkDefaultFont", 16, "bold"),
            foreground="#f5f8ff",
            background="#131722",
        ).pack(side="left")
        mode_text = "Mode: Standalone (No Python)" if self._is_frozen_runtime() else "Mode: Source (Python)"
        ttk.Label(top, text=mode_text, style="Mode.TLabel").pack(side="right")

        workspace_text = f"Workspace: {self._detect_workspace_root()}"
        ttk.Label(
            root,
            text=workspace_text,
            foreground="#95a5c3",
            background="#131722",
        ).pack(anchor="w", pady=(2, 0))
        ttk.Label(
            root,
            text="Step 1 create/open a project. Step 2 run or export from the Export tab.",
            foreground="#95a5c3",
            background="#131722",
        ).pack(anchor="w", pady=(2, 10))

        notebook = ttk.Notebook(root)
        notebook.pack(fill="both", expand=True)

        create_tab = ttk.Frame(notebook, padding=12, style="Root.TFrame")
        export_tab = ttk.Frame(notebook, padding=12, style="Root.TFrame")
        notebook.add(create_tab, text="Project Setup")
        notebook.add(export_tab, text="Run & Export")

        self._build_create_tab(create_tab)
        self._build_export_tab(export_tab)

    def _build_create_tab(self, parent: ttk.Frame) -> None:
        card = ttk.Frame(parent, style="Card.TFrame", padding=14)
        card.pack(fill="x")
        card.columnconfigure(1, weight=1)

        ttk.Label(card, text="New Project", style="CardTitle.TLabel").grid(row=0, column=0, columnspan=3, sticky="w")
        ttk.Label(
            card,
            text="Create a clean game folder with starter files.",
            style="Hint.TLabel",
        ).grid(row=1, column=0, columnspan=3, sticky="w", pady=(2, 10))

        ttk.Label(card, text="Parent Folder", style="Body.TLabel").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(card, textvariable=self.new_parent_var).grid(row=2, column=1, sticky="ew", pady=4, padx=(8, 8))
        ttk.Button(card, text="Browse", command=lambda: self._browse_dir(self.new_parent_var)).grid(row=2, column=2, sticky="ew", pady=4)

        ttk.Label(card, text="Game Name", style="Body.TLabel").grid(row=3, column=0, sticky="w", pady=4)
        ttk.Entry(card, textvariable=self.new_name_var).grid(row=3, column=1, sticky="ew", pady=4, padx=(8, 8))
        ttk.Label(card, text="Used for folder + project title", style="Hint.TLabel").grid(row=3, column=2, sticky="w", pady=4)

        ttk.Label(card, text="Window Size", style="Body.TLabel").grid(row=4, column=0, sticky="w", pady=4)
        size_wrap = ttk.Frame(card, style="Card.TFrame")
        size_wrap.grid(row=4, column=1, sticky="w", pady=4, padx=(8, 8))
        ttk.Entry(size_wrap, width=7, textvariable=self.new_width_var).pack(side="left")
        ttk.Label(size_wrap, text="x", style="Body.TLabel").pack(side="left", padx=6)
        ttk.Entry(size_wrap, width=7, textvariable=self.new_height_var).pack(side="left")

        ttk.Label(card, text="FPS", style="Body.TLabel").grid(row=5, column=0, sticky="w", pady=4)
        ttk.Entry(card, width=8, textvariable=self.new_fps_var).grid(row=5, column=1, sticky="w", pady=4, padx=(8, 8))

        toggles = ttk.Frame(card, style="Card.TFrame")
        toggles.grid(row=6, column=0, columnspan=3, sticky="w", pady=(8, 2))
        ttk.Checkbutton(toggles, text="Resizable window", variable=self.new_resizable_var).pack(side="left", padx=(0, 14))
        ttk.Checkbutton(toggles, text="Enable title menu", variable=self.new_title_menu_var).pack(side="left", padx=(0, 14))
        ttk.Checkbutton(toggles, text="Enable pause menu", variable=self.new_pause_menu_var).pack(side="left")

        actions = ttk.Frame(card, style="Card.TFrame")
        actions.grid(row=7, column=0, columnspan=3, sticky="w", pady=(12, 2))
        create_btn = ttk.Button(actions, text="Create Project", command=self._create_project)
        create_btn.pack(side="left")
        self._run_buttons.append(create_btn)

        ttk.Label(card, textvariable=self.new_status_var, style="Hint.TLabel").grid(row=8, column=0, columnspan=3, sticky="w", pady=(8, 0))

    def _build_export_tab(self, parent: ttk.Frame) -> None:
        form = ttk.Frame(parent, style="Card.TFrame", padding=14)
        form.pack(fill="x")
        form.columnconfigure(1, weight=1)

        ttk.Label(form, text="Run / Export", style="CardTitle.TLabel").grid(row=0, column=0, columnspan=3, sticky="w")
        ttk.Label(
            form,
            text="1) Choose project. 2) Click One-Click Export. 3) Run exported build.",
            style="Hint.TLabel",
        ).grid(row=1, column=0, columnspan=3, sticky="w", pady=(2, 10))

        ttk.Label(form, text="Project Folder", style="Body.TLabel").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.export_project_var).grid(row=2, column=1, sticky="ew", pady=4, padx=(8, 8))
        ttk.Button(form, text="Browse", command=lambda: self._browse_dir(self.export_project_var)).grid(row=2, column=2, sticky="ew", pady=4)

        ttk.Label(form, text="Target", style="Body.TLabel").grid(row=3, column=0, sticky="w", pady=4)
        ttk.Combobox(
            form,
            textvariable=self.export_target_var,
            values=["host", "linux", "windows", "macos"],
            state="readonly",
            width=14,
        ).grid(row=3, column=1, sticky="w", pady=4, padx=(8, 8))
        ttk.Label(form, text="Use host for current OS", style="Hint.TLabel").grid(row=3, column=2, sticky="w", pady=4)

        ttk.Label(form, text="Video Artifacts", style="Body.TLabel").grid(row=4, column=0, sticky="w", pady=4)
        ttk.Label(form, text="Auto", style="Body.TLabel").grid(row=4, column=1, sticky="w", pady=4, padx=(8, 8))
        ttk.Label(form, text="Auto-detected from exports/engine or vnef-video/artifacts", style="Hint.TLabel").grid(
            row=4,
            column=2,
            sticky="w",
            pady=4,
        )

        ttk.Label(form, text="Engine Output", style="Body.TLabel").grid(row=5, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.export_engine_out_var).grid(row=5, column=1, sticky="ew", pady=4, padx=(8, 8))
        ttk.Label(form, text="Engine export root", style="Hint.TLabel").grid(row=5, column=2, sticky="w", pady=4)

        ttk.Label(form, text="Game Output", style="Body.TLabel").grid(row=6, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.export_game_out_var).grid(row=6, column=1, sticky="ew", pady=4, padx=(8, 8))
        ttk.Label(form, text="Game export root", style="Hint.TLabel").grid(row=6, column=2, sticky="w", pady=4)

        ttk.Label(
            form,
            text="One-Click Export always builds frozen runtime and zip output.",
            style="Hint.TLabel",
        ).grid(row=7, column=0, columnspan=3, sticky="w", pady=(10, 2))
        if self._is_frozen_runtime():
            ttk.Label(
                form,
                text="Standalone Studio uses bundled frozen engine templates from dist/exports/engine.",
                style="Hint.TLabel",
            ).grid(row=8, column=0, columnspan=3, sticky="w", pady=(2, 0))

        actions = ttk.Frame(form, style="Card.TFrame")
        actions.grid(row=9, column=0, columnspan=3, sticky="w", pady=(12, 0))
        quick_export_btn = ttk.Button(actions, text="One-Click Export", command=self._quick_export)
        quick_export_btn.pack(side="left", padx=(0, 12))
        run_dev_btn = ttk.Button(actions, text="Run (Dev)", command=self._run_dev)
        run_dev_btn.pack(side="left", padx=(8, 8))
        run_export_btn = ttk.Button(actions, text="Run (Exported)", command=self._run_exported)
        run_export_btn.pack(side="left")
        self.stop_button = ttk.Button(actions, text="Stop", command=self._stop_run, state="disabled")
        self.stop_button.pack(side="left", padx=(12, 0))
        self._run_buttons.extend([quick_export_btn, run_dev_btn, run_export_btn])

        log_card = ttk.Frame(parent, style="Card.TFrame", padding=10)
        log_card.pack(fill="both", expand=True, pady=(10, 0))
        ttk.Label(log_card, text="Task Log", style="CardTitle.TLabel").pack(anchor="w", pady=(0, 6))

        self.log_text = tk.Text(
            log_card,
            height=16,
            bg="#101520",
            fg="#e7edf9",
            insertbackground="#e7edf9",
            relief="flat",
            wrap="word",
        )
        self.log_text.pack(fill="both", expand=True)
        self.log_text.configure(state="disabled")

    def _browse_dir(self, variable: tk.StringVar) -> None:
        initial = variable.get().strip() or str(self.repo_root)
        selected = filedialog.askdirectory(initialdir=initial, title="Select folder")
        if selected:
            variable.set(selected)

    def _append_log(self, text: str) -> None:
        self.log_text.configure(state="normal")
        self.log_text.insert("end", text.rstrip() + "\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def _use_zip(self) -> bool:
        return True

    def _use_strict_artifacts(self) -> bool:
        return False

    def _use_frozen_runner(self) -> bool:
        return True

    def _set_running(self, value: bool) -> None:
        self._running = value
        state = "disabled" if value else "normal"
        for button in self._run_buttons:
            button.configure(state=state)
        if self.stop_button is not None:
            self.stop_button.configure(state="normal" if value else "disabled")

    def _detect_host_target(self) -> str:
        text = sys.platform.lower()
        if text.startswith("win"):
            return "windows"
        if text == "darwin":
            return "macos"
        return "linux"

    def _create_project(self) -> None:
        if self._running:
            return
        parent_raw = self.new_parent_var.get().strip()
        name_raw = self.new_name_var.get().strip()
        if not parent_raw or not name_raw:
            self.new_status_var.set("Parent folder and game name are required.")
            return
        try:
            width = max(320, int(self.new_width_var.get().strip()))
            height = max(240, int(self.new_height_var.get().strip()))
            fps = max(30, int(self.new_fps_var.get().strip()))
        except ValueError:
            self.new_status_var.set("Width, height, and FPS must be valid numbers.")
            return

        destination = Path(parent_raw).expanduser().resolve() / slugify(name_raw)
        if destination.exists() and any(destination.iterdir()):
            ok = messagebox.askyesno(
                title="Folder exists",
                message=f"{destination} is not empty.\nOverwrite project files?",
                icon=messagebox.WARNING,
            )
            if not ok:
                return

        create_project_tree(
            destination=destination,
            game_name=name_raw,
            width=width,
            height=height,
            fps=fps,
            resizable=bool(self.new_resizable_var.get()),
            title_menu_enabled=bool(self.new_title_menu_var.get()),
            pause_menu_enabled=bool(self.new_pause_menu_var.get()),
        )
        self.export_project_var.set(str(destination))
        self.new_status_var.set(f"Project created: {destination}")
        self._append_log(f"[ok] created project: {destination}")

    def _export_engine(self) -> None:
        target = self.export_target_var.get().strip() or "host"
        output = self.export_engine_out_var.get().strip() or "dist/exports/engine"
        base_dir = self._project_workspace_root() if self._is_frozen_runtime() else None
        if self._is_frozen_runtime():
            output = self._resolve_user_path(output, "dist/exports/engine", base_dir=base_dir)
        artifacts = self._auto_artifacts_root(base_dir=base_dir)
        if self._is_frozen_runtime():
            cmd = self._studio_task_command(
                "export-engine",
                "--target",
                target,
                "--output",
                output,
                "--artifacts",
                artifacts,
            )
        else:
            cmd = [
                sys.executable,
                str(self.repo_root / "tools" / "export_engine.py"),
                "--target",
                target,
                "--output",
                output,
                "--artifacts",
                artifacts,
            ]
        if self._use_zip():
            cmd.append("--zip")
        if self._use_strict_artifacts():
            cmd.append("--strict")
        if self._use_frozen_runner():
            cmd.append("--freeze")
        self._run_command(cmd)

    def _quick_export(self) -> None:
        project_path = self.export_project_var.get().strip()
        if not project_path:
            messagebox.showerror("Missing project", "Project folder is required.")
            return
        project_path = self._resolve_user_path(project_path, "games/demo")

        target = self.export_target_var.get().strip() or "host"
        if target == "all":
            target = "host"
            self.export_target_var.set("host")
        engine_target = self._detect_host_target() if target == "host" else target

        base_dir = self._project_workspace_root() if self._is_frozen_runtime() else None
        engine_out = self._resolve_user_path(
            self.export_engine_out_var.get().strip() or "dist/exports/engine",
            "dist/exports/engine",
            base_dir=base_dir,
        )
        game_out = self._resolve_user_path(
            self.export_game_out_var.get().strip() or "dist/exports/game",
            "dist/exports/game",
            base_dir=base_dir,
        )
        artifacts = self._auto_artifacts_root(base_dir=base_dir)
        self.export_engine_out_var.set(engine_out)
        self.export_game_out_var.set(game_out)
        self.export_artifacts_var.set(artifacts)

        engine_dir = Path(engine_out) / f"cpyvn-engine-{engine_target}"
        commands: list[list[str]] = []
        needs_engine_export = not engine_dir.exists()
        if engine_dir.exists() and self._use_frozen_runner():
            needs_engine_export = self._engine_runtime_mode(engine_dir) != "frozen"
        if needs_engine_export:
            if self._is_frozen_runtime():
                cmd_engine = self._studio_task_command(
                    "export-engine",
                    "--target",
                    target,
                    "--output",
                    engine_out,
                    "--artifacts",
                    artifacts,
                )
            else:
                cmd_engine = [
                    sys.executable,
                    str(self.repo_root / "tools" / "export_engine.py"),
                    "--target",
                    target,
                    "--output",
                    engine_out,
                    "--artifacts",
                    artifacts,
                ]
            if self._use_zip():
                cmd_engine.append("--zip")
            if self._use_strict_artifacts():
                cmd_engine.append("--strict")
            if self._use_frozen_runner():
                cmd_engine.append("--freeze")
            commands.append(cmd_engine)

        if self._is_frozen_runtime():
            cmd_game = self._studio_task_command(
                "export-game",
                "--project",
                project_path,
                "--target",
                target,
                "--output",
                game_out,
                "--engine",
                str(engine_dir),
            )
        else:
            cmd_game = [
                sys.executable,
                str(self.repo_root / "tools" / "export_game.py"),
                "--project",
                project_path,
                "--target",
                target,
                "--output",
                game_out,
                "--engine",
                str(engine_dir),
            ]
        if self._use_zip():
            cmd_game.append("--zip")
        commands.append(cmd_game)

        self._run_commands(commands)

    def _export_game(self) -> None:
        project_path = self.export_project_var.get().strip()
        if not project_path:
            messagebox.showerror("Missing project", "Project folder is required.")
            return
        project_path = self._resolve_user_path(project_path, "games/demo")
        target = self.export_target_var.get().strip() or "host"
        if target == "all":
            messagebox.showerror("Invalid target", "Export Game does not support target=all.")
            return
        output = self.export_game_out_var.get().strip() or "dist/exports/game"
        base_dir = self._project_workspace_root() if self._is_frozen_runtime() else None
        if self._is_frozen_runtime():
            output = self._resolve_user_path(output, "dist/exports/game", base_dir=base_dir)
        if self._is_frozen_runtime():
            engine_out = self.export_engine_out_var.get().strip() or "dist/exports/engine"
            engine_out = self._resolve_user_path(engine_out, "dist/exports/engine", base_dir=base_dir)
            engine_target = target
            if engine_target == "host":
                engine_target = self._detect_host_target()
            engine_dir_path = Path(engine_out) / f"cpyvn-engine-{engine_target}"
            if self._use_frozen_runner() and self._engine_runtime_mode(engine_dir_path) != "frozen":
                messagebox.showerror(
                    "Frozen engine required",
                    "Freeze runner is enabled but selected engine export is not frozen.\n"
                    "Run Export Engine with Freeze enabled first.",
                )
                return
            engine_dir = str(engine_dir_path)
            cmd = self._studio_task_command(
                "export-game",
                "--project",
                project_path,
                "--target",
                target,
                "--output",
                output,
                "--engine",
                engine_dir,
            )
        else:
            cmd = [
                sys.executable,
                str(self.repo_root / "tools" / "export_game.py"),
                "--project",
                project_path,
                "--target",
                target,
                "--output",
                output,
            ]
        if self._use_zip():
            cmd.append("--zip")
        self._run_command(cmd)

    def _run_dev(self) -> None:
        project_path = self.export_project_var.get().strip()
        if not project_path:
            messagebox.showerror("Missing project", "Project folder is required.")
            return
        project_path = self._resolve_user_path(project_path, "games/demo")
        if self._is_frozen_runtime():
            cmd = self._studio_task_command(
                "run-dev",
                "--project",
                project_path,
            )
        else:
            cmd = [
                sys.executable,
                str(self.repo_root / "main.py"),
                "--project",
                project_path,
            ]
        self._run_command(cmd)

    def _project_name(self, project_dir: Path) -> str:
        project_json = project_dir / "project.json"
        if not project_json.exists():
            return project_dir.name
        try:
            raw = json.loads(project_json.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return project_dir.name
        if isinstance(raw, dict):
            value = str(raw.get("name", "")).strip()
            if value:
                return value
        return project_dir.name

    def _engine_runtime_mode(self, engine_dir: Path) -> str:
        manifest = engine_dir / "engine_manifest.json"
        if not manifest.exists():
            return ""
        try:
            raw = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return ""
        if not isinstance(raw, dict):
            return ""
        return str(raw.get("runtime_mode", "")).strip().lower()

    def _run_exported(self) -> None:
        project_path = self.export_project_var.get().strip()
        if not project_path:
            messagebox.showerror("Missing project", "Project folder is required.")
            return
        project_dir = Path(self._resolve_user_path(project_path, "games/demo"))
        target = self.export_target_var.get().strip() or "host"
        if target == "all":
            messagebox.showerror("Invalid target", "Run Exported does not support target=all.")
            return
        if target == "host":
            target = self._detect_host_target()

        game_name = self._project_name(project_dir)
        export_out = self.export_game_out_var.get().strip() or "dist/exports/game"
        if self._is_frozen_runtime():
            export_out = self._resolve_user_path(export_out, "dist/exports/game", base_dir=self._project_workspace_root())
            bundle_dir = (Path(export_out) / f"{game_name}-{target}").resolve()
        else:
            bundle_dir = (self.repo_root / export_out / f"{game_name}-{target}").resolve()
        if not bundle_dir.exists():
            messagebox.showerror("Missing export", f"Game export not found:\n{bundle_dir}")
            return

        if target == "windows":
            launcher = bundle_dir / "play.bat"
            cmd = ["cmd", "/c", str(launcher)]
        else:
            launcher = bundle_dir / "play.sh"
            cmd = [str(launcher)]
        if not launcher.exists():
            messagebox.showerror("Missing launcher", f"Launcher not found:\n{launcher}")
            return
        self._run_command(cmd, cwd=bundle_dir)

    def _run_command(self, command: list[str], cwd: Path | None = None) -> None:
        self._run_commands([command], cwd=cwd)

    def _run_commands(self, commands: list[list[str]], cwd: Path | None = None) -> None:
        if self._running:
            return
        self._set_running(True)
        for command in commands:
            self._append_log("$ " + " ".join(shlex.quote(part) for part in command))

        thread = threading.Thread(target=self._run_worker, args=(commands, cwd), daemon=True)
        thread.start()
        self.after(100, self._drain_queue)

    def _run_worker(self, commands: list[list[str]], cwd: Path | None) -> None:
        env = dict(os.environ)
        env.setdefault("PYTHONUNBUFFERED", "1")
        code = 0
        for command in commands:
            try:
                process = subprocess.Popen(
                    command,
                    cwd=str(cwd or self.repo_root),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    env=env,
                )
                self._active_process = process
            except Exception as exc:  # pragma: no cover - UI path
                self._run_queue.put(f"[error] failed to start command: {exc}")
                self._run_queue.put(("__exit__", 1))
                return

            assert process.stdout is not None
            for line in process.stdout:
                self._run_queue.put(line.rstrip("\n"))
            code = process.wait()
            self._active_process = None
            if code != 0:
                break

        if code == 0:
            self._run_queue.put("[done] success")
        else:
            self._run_queue.put(f"[done] failed with exit code {code}")
        self._run_queue.put(("__exit__", code))

    def _stop_run(self) -> None:
        proc = self._active_process
        if proc is None:
            return
        if proc.poll() is not None:
            return
        self._append_log("[info] stopping running process...")
        try:
            proc.terminate()
        except Exception as exc:
            self._append_log(f"[warn] terminate failed: {exc}")

    def _drain_queue(self) -> None:
        keep_polling = True
        while True:
            try:
                item = self._run_queue.get_nowait()
            except queue.Empty:
                break
            if isinstance(item, tuple) and len(item) == 2 and item[0] == "__exit__":
                self._set_running(False)
                keep_polling = False
            else:
                self._append_log(str(item))
        if keep_polling and self._running:
            self.after(100, self._drain_queue)


def _run_dev_task(project: str) -> None:
    from vn.cli.main import main as runtime_main

    argv_backup = list(sys.argv)
    try:
        sys.argv = [argv_backup[0], "--project", project]
        runtime_main()
    finally:
        sys.argv = argv_backup


def _read_runtime_mode(engine_dir: Path) -> str:
    manifest = engine_dir / "engine_manifest.json"
    if not manifest.exists():
        return ""
    try:
        raw = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    if not isinstance(raw, dict):
        return ""
    return str(raw.get("runtime_mode", "")).strip().lower()


def _find_bundled_frozen_engine(target: str) -> Path | None:
    rel = Path("dist") / "exports" / "engine" / f"cpyvn-engine-{target}"
    roots: list[Path] = []

    env_root = os.environ.get("CPYVN_REPO_ROOT", "").strip()
    if env_root:
        roots.append(Path(env_root).expanduser().resolve())
    meipass = getattr(sys, "_MEIPASS", "")
    if meipass:
        roots.append(Path(str(meipass)).resolve())
    roots.append(Path(sys.executable).resolve().parent)
    roots.append(Path.cwd().resolve())

    seen: set[Path] = set()
    for root in roots:
        if root in seen:
            continue
        seen.add(root)
        probe_nodes = [root]
        probe_nodes.extend(list(root.parents)[:3])
        for node in probe_nodes:
            candidate = (node / rel).resolve()
            if not candidate.exists():
                continue
            if _read_runtime_mode(candidate) == "frozen":
                return candidate
    return None


def _copy_bundled_frozen_engines(target: str, output: str, zip_output: bool) -> None:
    raw_target = str(target or "host").strip().lower()
    if raw_target == "host":
        if sys.platform.startswith("win"):
            raw_target = "windows"
        elif sys.platform == "darwin":
            raw_target = "macos"
        else:
            raw_target = "linux"
    targets = ["linux", "windows", "macos"] if raw_target == "all" else [normalize_target(raw_target)]

    output_root = Path(output).expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    copied: list[Path] = []
    missing: list[str] = []
    for t in targets:
        bundled = _find_bundled_frozen_engine(t)
        if bundled is None:
            missing.append(t)
            continue
        dst = output_root / bundled.name
        if bundled.resolve() != dst.resolve():
            ensure_clean_dir(dst)
            copy_any(bundled, dst)
        copied.append(dst)
        print(f"[ok] bundled frozen engine: {dst}")
        if zip_output:
            zip_path = output_root / f"{bundled.name}.zip"
            zip_dir(dst, zip_path)
            print(f"[ok] zip: {zip_path}")

    if missing:
        raise RuntimeError(
            "Missing bundled frozen engine template(s): "
            + ", ".join(missing)
            + ". Use source Studio/CLI to build them, or use a with-engines Studio package."
        )
    if copied:
        print(f"[done] exported {len(copied)} bundled frozen engine template(s) to {output_root}")


def _run_studio_task(argv: list[str]) -> int:
    def _workspace_root() -> Path:
        base = Path.cwd().resolve()
        probe_roots = [base]
        if getattr(sys, "frozen", False):
            probe_roots.append(Path(sys.executable).resolve().parent)
        for root in probe_roots:
            for node in [root, *root.parents]:
                if (node / "games").exists():
                    return node.resolve()
        return base

    def _cwd_abs(raw: str) -> str:
        text = (raw or "").strip()
        if not text:
            return ""
        path = Path(text).expanduser()
        if not path.is_absolute():
            path = (_workspace_root() / path).resolve()
        return str(path)

    def _remap_project_path(raw: str) -> str:
        path = Path((raw or "").strip()).expanduser()
        if not path:
            return raw
        if path.exists():
            return str(path.resolve())
        parts = list(path.parts)
        if "games" not in parts:
            return str(path)
        rel = Path(*parts[parts.index("games") :])
        candidate = (_workspace_root() / rel).resolve()
        if candidate.exists():
            return str(candidate)
        return str(path)

    parser = argparse.ArgumentParser(description="cpyvn Studio task runner")
    parser.add_argument("--studio-task", required=True, choices=["export-engine", "export-game", "run-dev"])
    parser.add_argument("--project", default="")
    parser.add_argument("--target", default="host")
    parser.add_argument("--output", default="")
    parser.add_argument("--artifacts", default="")
    parser.add_argument("--zip", action="store_true")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--freeze", action="store_true")
    parser.add_argument("--freeze-skip-cython", action="store_true")
    parser.add_argument("--engine", default="")
    args = parser.parse_args(argv)

    if args.studio_task == "export-engine":
        output = str(args.output or "dist/exports/engine")
        artifacts = str(args.artifacts or "vnef-video/artifacts")
        freeze_skip_cython = bool(args.freeze_skip_cython)
        if getattr(sys, "frozen", False):
            output = _cwd_abs(output)
            artifacts = _cwd_abs(artifacts)
            if args.freeze:
                _copy_bundled_frozen_engines(
                    target=str(args.target or "host"),
                    output=output,
                    zip_output=bool(args.zip),
                )
                return 0
        run_export_engine(
            target=str(args.target or "host"),
            output=output,
            artifacts=artifacts,
            zip_output=bool(args.zip),
            strict=bool(args.strict),
            freeze=bool(args.freeze),
            freeze_skip_cython=freeze_skip_cython,
        )
        return 0

    if args.studio_task == "export-game":
        if not args.project:
            raise ValueError("--project is required for --studio-task export-game")
        project = str(args.project)
        output = str(args.output or "dist/exports/game")
        engine = str(args.engine or "")
        if getattr(sys, "frozen", False):
            project = _remap_project_path(_cwd_abs(project))
            output = _cwd_abs(output)
            if engine:
                engine = _cwd_abs(engine)
        run_export_game(
            project=project,
            target=str(args.target or "host"),
            engine=engine,
            output=output,
            zip_output=bool(args.zip),
        )
        return 0

    if args.studio_task == "run-dev":
        if not args.project:
            raise ValueError("--project is required for --studio-task run-dev")
        project = str(args.project)
        if getattr(sys, "frozen", False):
            project = _remap_project_path(_cwd_abs(project))
        _run_dev_task(project)
        return 0

    raise ValueError(f"Unsupported studio task: {args.studio_task}")


def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])
    if "--studio-task" in args:
        return _run_studio_task(args)

    app = StudioApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
