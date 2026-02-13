from __future__ import annotations

from pathlib import Path
import tempfile
import textwrap
import unittest

from vn.parser import ScriptParseError, parse_script
from vn.script import Call, IfJump, Jump, Label, Map, Notify, ShowChar


def _write(path: Path, body: str) -> Path:
    path.write_text(textwrap.dedent(body).strip() + "\n", encoding="utf-8")
    return path


class ParserRegressionTests(unittest.TestCase):
    def test_parse_notify_and_show_regression(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            script = _write(
                Path(td) / "main.vn",
                """
                label start:
                    notify "tip text" 3.5;
                    show alice happy right fade 0.3 float 4 1.2;
                """,
            )

            parsed = parse_script(script)
            notify = next(cmd for cmd in parsed.commands if isinstance(cmd, Notify))
            show = next(cmd for cmd in parsed.commands if isinstance(cmd, ShowChar))

            self.assertEqual(notify.text, "tip text")
            self.assertEqual(notify.seconds, 3.5)
            self.assertEqual(show.ident, "alice")
            self.assertEqual(show.expression, "happy")
            self.assertEqual(show.anchor, "right")
            self.assertEqual(show.fade, 0.3)
            self.assertEqual(show.float_amp, 4)
            self.assertEqual(show.float_speed, 1.2)

    def test_include_alias_and_global_label_resolution(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            _write(
                root / "intro.vn",
                """
                label intro:
                    narrator "inside include";
                    go ::end;
                """,
            )
            main = _write(
                root / "main.vn",
                """
                include "intro.vn" as intro;

                label start:
                    go intro.intro;

                label end:
                    narrator "done";
                """,
            )

            parsed = parse_script(main)
            jumps = [cmd for cmd in parsed.commands if isinstance(cmd, Jump)]

            self.assertIn("intro.intro", parsed.labels)
            self.assertIn("start", parsed.labels)
            self.assertIn("end", parsed.labels)
            self.assertTrue(any(j.target == "intro.intro" for j in jumps))
            self.assertTrue(any(j.target == "end" for j in jumps))

    def test_check_block_injects_skip_label_and_inverted_condition(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            script = _write(
                Path(td) / "main.vn",
                """
                label start:
                    check visits > 1 {
                        narrator "inside";
                    };
                    narrator "after";
                """,
            )

            parsed = parse_script(script)
            gate = next(cmd for cmd in parsed.commands if isinstance(cmd, IfJump))

            self.assertEqual(gate.name, "visits")
            self.assertEqual(gate.op, "<=")
            self.assertEqual(gate.value, 1)
            self.assertTrue(gate.target.startswith("__check_skip_"))
            self.assertTrue(any(isinstance(cmd, Label) and cmd.name == gate.target for cmd in parsed.commands))
            self.assertIn(gate.target, parsed.labels)

    def test_call_parses_with_or_without_loading_block(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            _write(
                root / "chap.vn",
                """
                label intro:
                    narrator "x";
                """,
            )
            plain = _write(
                root / "plain.vn",
                """
                label start:
                    call "chap.vn" intro;
                """,
            )
            valid = _write(
                root / "valid.vn",
                """
                label start:
                    loading "Prep" {
                        call "chap.vn" intro;
                    };
                """,
            )

            parsed_plain = parse_script(plain)
            parsed = parse_script(valid)
            self.assertTrue(any(isinstance(cmd, Call) for cmd in parsed_plain.commands))
            self.assertTrue(any(isinstance(cmd, Call) for cmd in parsed.commands))

    def test_include_alias_namespaces_map_poi_targets(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            _write(
                root / "map.vn",
                """
                label map_demo:
                    map show "world.png";
                    map poi "Local" 100 100 -> local_end;
                    map poi "Global" 120 120 -> ::end;

                label local_end:
                    narrator "done";
                """,
            )
            main = _write(
                root / "main.vn",
                """
                include "map.vn" as m;

                label start:
                    go m.map_demo;

                label end:
                    narrator "global";
                """,
            )

            parsed = parse_script(main)
            maps = [cmd for cmd in parsed.commands if isinstance(cmd, Map) and cmd.action == "poi"]

            self.assertIn("m.map_demo", parsed.labels)
            self.assertIn("m.local_end", parsed.labels)
            self.assertTrue(any(cmd.target == "m.local_end" for cmd in maps))
            self.assertTrue(any(cmd.target == "end" for cmd in maps))


if __name__ == "__main__":
    unittest.main()
