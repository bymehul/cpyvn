#!/usr/bin/env python3
from __future__ import annotations

import os
import queue
import shlex
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

if __package__:
    from .templates import create_project_tree, slugify
else:
    from templates import create_project_tree, slugify


class StudioApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("cpyvn Studio")
        self.geometry("980x700")
        self.minsize(860, 600)

        self.repo_root = Path(__file__).resolve().parents[2]
        self._running = False
        self._run_queue: queue.Queue[object] = queue.Queue()
        self._run_buttons: list[ttk.Button] = []

        self._configure_style()
        self._init_vars()
        self._build_ui()

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

    def _init_vars(self) -> None:
        games_dir = self.repo_root / "games"

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
        self.export_zip_var = tk.BooleanVar(value=True)
        self.export_strict_var = tk.BooleanVar(value=False)
        self.export_artifacts_var = tk.StringVar(value="vnef-video/artifacts")
        self.export_engine_out_var = tk.StringVar(value="dist/exports/engine")
        self.export_game_out_var = tk.StringVar(value="dist/exports/game")

    def _build_ui(self) -> None:
        root = ttk.Frame(self, style="Root.TFrame", padding=14)
        root.pack(fill="both", expand=True)

        heading = ttk.Label(
            root,
            text="cpyvn Studio",
            font=("TkDefaultFont", 16, "bold"),
            foreground="#f5f8ff",
            background="#131722",
        )
        heading.pack(anchor="w")
        sub = ttk.Label(
            root,
            text="Create game skeletons and run engine/game exports.",
            foreground="#95a5c3",
            background="#131722",
        )
        sub.pack(anchor="w", pady=(2, 10))

        notebook = ttk.Notebook(root)
        notebook.pack(fill="both", expand=True)

        create_tab = ttk.Frame(notebook, padding=12, style="Root.TFrame")
        export_tab = ttk.Frame(notebook, padding=12, style="Root.TFrame")
        notebook.add(create_tab, text="New Game")
        notebook.add(export_tab, text="Export")

        self._build_create_tab(create_tab)
        self._build_export_tab(export_tab)

    def _build_create_tab(self, parent: ttk.Frame) -> None:
        card = ttk.Frame(parent, style="Card.TFrame", padding=14)
        card.pack(fill="x")
        card.columnconfigure(1, weight=1)

        ttk.Label(card, text="Create Project", style="CardTitle.TLabel").grid(row=0, column=0, columnspan=3, sticky="w")

        ttk.Label(card, text="Parent Folder", style="Body.TLabel").grid(row=1, column=0, sticky="w", pady=(12, 4))
        ttk.Entry(card, textvariable=self.new_parent_var).grid(row=1, column=1, sticky="ew", pady=(12, 4), padx=(8, 8))
        ttk.Button(card, text="Browse", command=lambda: self._browse_dir(self.new_parent_var)).grid(row=1, column=2, sticky="ew", pady=(12, 4))

        ttk.Label(card, text="Game Name", style="Body.TLabel").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Entry(card, textvariable=self.new_name_var).grid(row=2, column=1, sticky="ew", pady=4, padx=(8, 8))
        ttk.Label(card, text="Used for folder + title", style="Hint.TLabel").grid(row=2, column=2, sticky="w", pady=4)

        ttk.Label(card, text="Window Size", style="Body.TLabel").grid(row=3, column=0, sticky="w", pady=4)
        size_wrap = ttk.Frame(card, style="Card.TFrame")
        size_wrap.grid(row=3, column=1, sticky="w", pady=4, padx=(8, 8))
        ttk.Entry(size_wrap, width=7, textvariable=self.new_width_var).pack(side="left")
        ttk.Label(size_wrap, text="x", style="Body.TLabel").pack(side="left", padx=6)
        ttk.Entry(size_wrap, width=7, textvariable=self.new_height_var).pack(side="left")

        ttk.Label(card, text="FPS", style="Body.TLabel").grid(row=4, column=0, sticky="w", pady=4)
        ttk.Entry(card, width=8, textvariable=self.new_fps_var).grid(row=4, column=1, sticky="w", pady=4, padx=(8, 8))

        toggles = ttk.Frame(card, style="Card.TFrame")
        toggles.grid(row=5, column=0, columnspan=3, sticky="w", pady=(8, 2))
        ttk.Checkbutton(toggles, text="Resizable window", variable=self.new_resizable_var).pack(side="left", padx=(0, 14))
        ttk.Checkbutton(toggles, text="Enable title menu", variable=self.new_title_menu_var).pack(side="left", padx=(0, 14))
        ttk.Checkbutton(toggles, text="Enable pause menu", variable=self.new_pause_menu_var).pack(side="left")

        actions = ttk.Frame(card, style="Card.TFrame")
        actions.grid(row=6, column=0, columnspan=3, sticky="w", pady=(12, 2))
        create_btn = ttk.Button(actions, text="Create Project", command=self._create_project)
        create_btn.pack(side="left")
        self._run_buttons.append(create_btn)

        ttk.Label(card, textvariable=self.new_status_var, style="Hint.TLabel").grid(row=7, column=0, columnspan=3, sticky="w", pady=(8, 0))

    def _build_export_tab(self, parent: ttk.Frame) -> None:
        form = ttk.Frame(parent, style="Card.TFrame", padding=14)
        form.pack(fill="x")
        form.columnconfigure(1, weight=1)

        ttk.Label(form, text="Export Tasks", style="CardTitle.TLabel").grid(row=0, column=0, columnspan=3, sticky="w")

        ttk.Label(form, text="Project Folder", style="Body.TLabel").grid(row=1, column=0, sticky="w", pady=(12, 4))
        ttk.Entry(form, textvariable=self.export_project_var).grid(row=1, column=1, sticky="ew", pady=(12, 4), padx=(8, 8))
        ttk.Button(form, text="Browse", command=lambda: self._browse_dir(self.export_project_var)).grid(row=1, column=2, sticky="ew", pady=(12, 4))

        ttk.Label(form, text="Target", style="Body.TLabel").grid(row=2, column=0, sticky="w", pady=4)
        ttk.Combobox(
            form,
            textvariable=self.export_target_var,
            values=["host", "linux", "windows", "macos", "all"],
            state="readonly",
            width=14,
        ).grid(row=2, column=1, sticky="w", pady=4, padx=(8, 8))

        ttk.Label(form, text="Artifacts Root", style="Body.TLabel").grid(row=3, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.export_artifacts_var).grid(row=3, column=1, sticky="ew", pady=4, padx=(8, 8))

        ttk.Label(form, text="Engine Output", style="Body.TLabel").grid(row=4, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.export_engine_out_var).grid(row=4, column=1, sticky="ew", pady=4, padx=(8, 8))

        ttk.Label(form, text="Game Output", style="Body.TLabel").grid(row=5, column=0, sticky="w", pady=4)
        ttk.Entry(form, textvariable=self.export_game_out_var).grid(row=5, column=1, sticky="ew", pady=4, padx=(8, 8))

        toggles = ttk.Frame(form, style="Card.TFrame")
        toggles.grid(row=6, column=0, columnspan=3, sticky="w", pady=(8, 4))
        ttk.Checkbutton(toggles, text="Create zip", variable=self.export_zip_var).pack(side="left", padx=(0, 14))
        ttk.Checkbutton(toggles, text="Strict artifact check (engine)", variable=self.export_strict_var).pack(side="left")

        actions = ttk.Frame(form, style="Card.TFrame")
        actions.grid(row=7, column=0, columnspan=3, sticky="w", pady=(10, 0))
        export_engine_btn = ttk.Button(actions, text="Export Engine", command=self._export_engine)
        export_engine_btn.pack(side="left", padx=(0, 8))
        export_game_btn = ttk.Button(actions, text="Export Game", command=self._export_game)
        export_game_btn.pack(side="left")
        self._run_buttons.extend([export_engine_btn, export_game_btn])

        log_card = ttk.Frame(parent, style="Card.TFrame", padding=10)
        log_card.pack(fill="both", expand=True, pady=(10, 0))
        ttk.Label(log_card, text="Run Log", style="CardTitle.TLabel").pack(anchor="w", pady=(0, 6))

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

    def _set_running(self, value: bool) -> None:
        self._running = value
        state = "disabled" if value else "normal"
        for button in self._run_buttons:
            button.configure(state=state)

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
        cmd = [
            sys.executable,
            str(self.repo_root / "tools" / "export_engine.py"),
            "--target",
            self.export_target_var.get().strip() or "host",
            "--output",
            self.export_engine_out_var.get().strip() or "dist/exports/engine",
            "--artifacts",
            self.export_artifacts_var.get().strip() or "vnef-video/artifacts",
        ]
        if self.export_zip_var.get():
            cmd.append("--zip")
        if self.export_strict_var.get():
            cmd.append("--strict")
        self._run_command(cmd)

    def _export_game(self) -> None:
        project_path = self.export_project_var.get().strip()
        if not project_path:
            messagebox.showerror("Missing project", "Project folder is required.")
            return
        target = self.export_target_var.get().strip() or "host"
        if target == "all":
            messagebox.showerror("Invalid target", "Export Game does not support target=all.")
            return
        cmd = [
            sys.executable,
            str(self.repo_root / "tools" / "export_game.py"),
            "--project",
            project_path,
            "--target",
            target,
            "--output",
            self.export_game_out_var.get().strip() or "dist/exports/game",
        ]
        if self.export_zip_var.get():
            cmd.append("--zip")
        self._run_command(cmd)

    def _run_command(self, command: list[str]) -> None:
        if self._running:
            return
        self._set_running(True)
        self._append_log("$ " + " ".join(shlex.quote(part) for part in command))

        thread = threading.Thread(target=self._run_worker, args=(command,), daemon=True)
        thread.start()
        self.after(100, self._drain_queue)

    def _run_worker(self, command: list[str]) -> None:
        env = dict(os.environ)
        env.setdefault("PYTHONUNBUFFERED", "1")
        try:
            process = subprocess.Popen(
                command,
                cwd=str(self.repo_root),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                env=env,
            )
        except Exception as exc:  # pragma: no cover - UI path
            self._run_queue.put(f"[error] failed to start command: {exc}")
            self._run_queue.put(("__exit__", 1))
            return

        assert process.stdout is not None
        for line in process.stdout:
            self._run_queue.put(line.rstrip("\n"))
        code = process.wait()
        if code == 0:
            self._run_queue.put("[done] success")
        else:
            self._run_queue.put(f"[done] failed with exit code {code}")
        self._run_queue.put(("__exit__", code))

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


def main() -> None:
    app = StudioApp()
    app.mainloop()


if __name__ == "__main__":
    main()
