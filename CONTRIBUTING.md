# Contributing to cpyvn

Thanks for helping. This project is intentionally small and script-first, so changes should stay focused and easy to reason about.

## Setup (Linux)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python setup_cython.py build_ext --inplace
python main.py --project games/demo
```

## Setup (macOS)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python setup_cython.py build_ext --inplace
python main.py --project games/demo
```

## Setup (Windows)

```powershell
py -m venv .venv
.venv\\Scripts\\Activate.ps1
pip install -r requirements.txt
python setup_cython.py build_ext --inplace
python main.py --project games/demo
```

```bat
py -m venv .venv
.venv\\Scripts\\activate.bat
pip install -r requirements.txt
python setup_cython.py build_ext --inplace
python main.py --project games/demo
```

Note: `venv` is a Python virtual environment. It helps keep dependencies isolated. On Windows you can skip it if you prefer, but using it is recommended.
Note: Linux is the recommended dev environment. Building Cython extensions is required and needs a C compiler (gcc/clang on Linux/macOS, Visual Studio Build Tools on Windows).

## Development guidelines

- Keep the VN scripting language simple and consistent.
- Avoid copying other syntax; :
  `label name:`, `scene ...;`, `add ...;`, `off ...;`, `ask "?" ...;`, `go name;`, `set`, `track`, and `check { ... };`.
- Prefer small, focused PRs over large refactors.
- If you add or change a script command, update:
  - `vn/script/ast.pyx`
  - `vn/parser/`
  - `vn/runtime/`
  - `README.md`
  - `docs/memory.md` (if memory/cache/runtime behavior changes)
  - `games/demo/script.vn`
- Keep runtime behavior deterministic and cross-platform.

## Tests / sanity checks

Before submitting:

```bash
python -m py_compile main.py $(rg --files vn -g '*.py')
python setup_cython.py build_ext --inplace
python -m unittest discover -s tests -p "test_*.py" -v
python main.py --project games/demo
```

If you add logic that affects save/load, verify `F5` and `F9` still work.

## Style

- Python 3.11+ only.
- Use clear, explicit error messages for script parsing errors.
- Keep comments minimal and only where they add clarity.
- Core engine modules are authored in `.pyx`.
