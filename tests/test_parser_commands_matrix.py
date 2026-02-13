from __future__ import annotations

from pathlib import Path
import tempfile
import textwrap
import unittest

from vn.parser import ScriptParseError, parse_script
from vn.script import (
    AddVar,
    Animate,
    Blend,
    CacheClear,
    CachePin,
    CacheUnpin,
    CameraSet,
    Call,
    CharacterDef,
    Choice,
    Echo,
    GarbageCollect,
    Hide,
    HotspotAdd,
    HotspotDebug,
    HotspotPoly,
    HotspotRemove,
    HudAdd,
    HudRemove,
    IfJump,
    Input,
    Item,
    Jump,
    Label,
    Load,
    Loading,
    Map,
    Music,
    Mute,
    Notify,
    Phone,
    Meter,
    Preload,
    Save,
    Say,
    Scene,
    SetVar,
    Show,
    ShowChar,
    Sound,
    Video,
    Voice,
    Wait,
    WaitVideo,
    WaitVoice,
)


def _write(path: Path, body: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(body).strip() + "\n", encoding="utf-8")
    return path


class ParserCommandMatrixTests(unittest.TestCase):
    def _parse(self, body: str, extra_files: dict[str, str] | None = None) -> object:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            if extra_files:
                for rel, content in extra_files.items():
                    _write(root / rel, content)
            main = _write(root / "main.vn", body)
            return parse_script(main)

    def test_label_command(self) -> None:
        parsed = self._parse(
            """
            label start:
            """,
        )
        self.assertIsInstance(parsed.commands[0], Label)
        self.assertEqual(parsed.labels["start"], 0)

    def test_dialogue_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                narrator "hello";
            """,
        )
        say = next(cmd for cmd in parsed.commands if isinstance(cmd, Say))
        self.assertEqual(say.speaker, "narrator")
        self.assertEqual(say.text, "hello")

    def test_ask_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                ask "Pick one?"
                    "A" -> a_path;
                    "B" -> b_path;
            """,
        )
        ask = next(cmd for cmd in parsed.commands if isinstance(cmd, Choice))
        self.assertEqual(ask.prompt, "Pick one?")
        self.assertEqual(ask.options, [("A", "a_path"), ("B", "b_path")])

    def test_go_and_goto_commands(self) -> None:
        parsed = self._parse(
            """
            label start:
                go one;
                goto two;
            """,
        )
        jumps = [cmd for cmd in parsed.commands if isinstance(cmd, Jump)]
        self.assertEqual([jump.target for jump in jumps], ["one", "two"])

    def test_scene_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                scene image "bg.png" fade 0.3 float 2 1.5;
            """,
        )
        scene = next(cmd for cmd in parsed.commands if isinstance(cmd, Scene))
        self.assertEqual(scene.kind, "image")
        self.assertEqual(scene.value, "bg.png")
        self.assertEqual(scene.fade, 0.3)
        self.assertEqual(scene.float_amp, 2.0)
        self.assertEqual(scene.float_speed, 1.5)
        self.assertEqual(scene.transition_style, "fade")
        self.assertEqual(scene.transition_seconds, 0.3)

    def test_scene_transition_style_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                scene image "bg.png" dissolve 0.5;
            """,
        )
        scene = next(cmd for cmd in parsed.commands if isinstance(cmd, Scene))
        self.assertEqual(scene.transition_style, "dissolve")
        self.assertEqual(scene.transition_seconds, 0.5)
        self.assertIsNone(scene.fade)

    def test_add_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                add image card "card.png" center middle z 4 fade 0.2 float 3 1.1;
            """,
        )
        show = next(cmd for cmd in parsed.commands if isinstance(cmd, Show))
        self.assertEqual(show.kind, "image")
        self.assertEqual(show.name, "card")
        self.assertEqual(show.value, "card.png")
        self.assertEqual(show.anchor, "center middle")
        self.assertEqual(show.z, 4)
        self.assertEqual(show.fade, 0.2)
        self.assertEqual(show.float_amp, 3.0)
        self.assertEqual(show.float_speed, 1.1)

    def test_add_image_size_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                add image poster "poster.png" size 320 480 100 200 z 2;
            """,
        )
        show = next(cmd for cmd in parsed.commands if isinstance(cmd, Show))
        self.assertEqual(show.kind, "image")
        self.assertEqual(show.name, "poster")
        self.assertEqual(show.value, "poster.png")
        self.assertEqual(show.size, (320, 480))
        self.assertEqual(show.pos, (100, 200))
        self.assertEqual(show.z, 2)

    def test_show_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                show alice happy left bottom z 3 fade 0.25 float 5 0.8;
            """,
        )
        show = next(cmd for cmd in parsed.commands if isinstance(cmd, ShowChar))
        self.assertEqual(show.ident, "alice")
        self.assertEqual(show.expression, "happy")
        self.assertEqual(show.anchor, "left bottom")
        self.assertEqual(show.z, 3)
        self.assertEqual(show.fade, 0.25)
        self.assertEqual(show.transition_style, "fade")
        self.assertEqual(show.transition_seconds, 0.25)
        self.assertEqual(show.float_amp, 5.0)
        self.assertEqual(show.float_speed, 0.8)

    def test_show_transition_style_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                show alice happy right wipe 0.4;
            """,
        )
        show = next(cmd for cmd in parsed.commands if isinstance(cmd, ShowChar))
        self.assertEqual(show.transition_style, "wipe")
        self.assertEqual(show.transition_seconds, 0.4)
        self.assertIsNone(show.fade)

    def test_show_rect_alias_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                show rect box #ff0000 200 100 center middle blur 0.5;
            """,
        )
        show = next(cmd for cmd in parsed.commands if isinstance(cmd, Show))
        self.assertEqual(show.kind, "rect")
        self.assertEqual(show.name, "box")
        self.assertEqual(show.value, "#ff0000")
        self.assertEqual(show.size, (200, 100))
        self.assertEqual(show.anchor, "center middle")
        self.assertEqual(show.transition_style, "blur")
        self.assertEqual(show.transition_seconds, 0.5)

    def test_off_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                off alice fade 0.4;
            """,
        )
        hide = next(cmd for cmd in parsed.commands if isinstance(cmd, Hide))
        self.assertEqual(hide.name, "alice")
        self.assertEqual(hide.fade, 0.4)
        self.assertEqual(hide.transition_style, "fade")
        self.assertEqual(hide.transition_seconds, 0.4)

    def test_off_transition_style_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                off alice slide 0.4;
            """,
        )
        hide = next(cmd for cmd in parsed.commands if isinstance(cmd, Hide))
        self.assertEqual(hide.transition_style, "slide")
        self.assertEqual(hide.transition_seconds, 0.4)
        self.assertIsNone(hide.fade)

    def test_hotspot_commands(self) -> None:
        parsed = self._parse(
            """
            label start:
                hotspot add kitchen 100 200 320 180 -> kitchen_scene;
                hotspot poly gate 50 50 120 40 180 90 110 160 40 120 -> gate_scene;
                hotspot debug on;
                hotspot remove kitchen;
                hotspot clear;
            """,
        )
        add = next(cmd for cmd in parsed.commands if isinstance(cmd, HotspotAdd))
        poly = next(cmd for cmd in parsed.commands if isinstance(cmd, HotspotPoly))
        debug = next(cmd for cmd in parsed.commands if isinstance(cmd, HotspotDebug))
        removes = [cmd for cmd in parsed.commands if isinstance(cmd, HotspotRemove)]
        self.assertEqual(add.name, "kitchen")
        self.assertEqual((add.x, add.y, add.w, add.h), (100, 200, 320, 180))
        self.assertEqual(add.target, "kitchen_scene")
        self.assertEqual(poly.name, "gate")
        self.assertEqual(len(poly.points), 5)
        self.assertEqual(poly.target, "gate_scene")
        self.assertTrue(debug.enabled)
        self.assertEqual(removes[0].name, "kitchen")
        self.assertIsNone(removes[1].name)

    def test_hud_commands(self) -> None:
        parsed = self._parse(
            """
            label start:
                hud add settings_btn text "Settings" 1100 20 200 40 -> settings_screen;
                hud add map_btn icon "icons/map.png" 50 20 48 48 -> map_screen;
                hud add inv_btn both "icons/bag.png" "Inventory" 50 80 160 48 -> inv_screen;
                hud remove settings_btn;
                hud clear;
            """,
        )
        adds = [cmd for cmd in parsed.commands if isinstance(cmd, HudAdd)]
        removes = [cmd for cmd in parsed.commands if isinstance(cmd, HudRemove)]
        self.assertEqual(len(adds), 3)
        # text style
        self.assertEqual(adds[0].name, "settings_btn")
        self.assertEqual(adds[0].style, "text")
        self.assertEqual(adds[0].text, "Settings")
        self.assertIsNone(adds[0].icon)
        self.assertEqual((adds[0].x, adds[0].y, adds[0].w, adds[0].h), (1100, 20, 200, 40))
        self.assertEqual(adds[0].target, "settings_screen")
        # icon style
        self.assertEqual(adds[1].name, "map_btn")
        self.assertEqual(adds[1].style, "icon")
        self.assertIsNone(adds[1].text)
        self.assertEqual(adds[1].icon, "icons/map.png")
        self.assertEqual((adds[1].x, adds[1].y, adds[1].w, adds[1].h), (50, 20, 48, 48))
        self.assertEqual(adds[1].target, "map_screen")
        # both style
        self.assertEqual(adds[2].name, "inv_btn")
        self.assertEqual(adds[2].style, "both")
        self.assertEqual(adds[2].text, "Inventory")
        self.assertEqual(adds[2].icon, "icons/bag.png")
        self.assertEqual((adds[2].x, adds[2].y, adds[2].w, adds[2].h), (50, 80, 160, 48))
        self.assertEqual(adds[2].target, "inv_screen")
        # remove / clear
        self.assertEqual(len(removes), 2)
        self.assertEqual(removes[0].name, "settings_btn")
        self.assertIsNone(removes[1].name)

    def test_camera_commands(self) -> None:
        parsed = self._parse(
            """
            label start:
                camera 120 -40 1.35;
                camera reset;
            """,
        )
        cams = [cmd for cmd in parsed.commands if isinstance(cmd, CameraSet)]
        self.assertEqual((cams[0].pan_x, cams[0].pan_y, cams[0].zoom), (120.0, -40.0, 1.35))
        self.assertEqual((cams[1].pan_x, cams[1].pan_y, cams[1].zoom), (0.0, 0.0, 1.0))

    def test_play_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                play tune "bgm.ogg" false;
            """,
        )
        play = next(cmd for cmd in parsed.commands if isinstance(cmd, Music))
        self.assertEqual(play.path, "bgm.ogg")
        self.assertFalse(play.loop)

    def test_video_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                video play "cutscene.mp4" loop true fit cover;
                video stop;
            """,
        )
        video = [cmd for cmd in parsed.commands if isinstance(cmd, Video)]
        self.assertEqual(video[0].action, "play")
        self.assertEqual(video[0].path, "cutscene.mp4")
        self.assertTrue(video[0].loop)
        self.assertEqual(video[0].fit, "cover")
        self.assertEqual(video[1].action, "stop")

    def test_video_defaults(self) -> None:
        parsed = self._parse(
            """
            label start:
                video play "intro.mp4";
            """,
        )
        video = next(cmd for cmd in parsed.commands if isinstance(cmd, Video))
        self.assertEqual(video.action, "play")
        self.assertEqual(video.path, "intro.mp4")
        self.assertFalse(video.loop)
        self.assertEqual(video.fit, "contain")

    def test_video_rejects_invalid_fit(self) -> None:
        with self.assertRaisesRegex(ScriptParseError, "video fit must be one of"):
            self._parse(
                """
                label start:
                    video play "intro.mp4" fit fill;
                """,
            )

    def test_animate_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                animate chars.alice move 900 520 0.6 inout;
                animate chars.alice size 420 680 0.5 out;
                animate chars.alice alpha 140 0.4 in;
                animate stop chars.alice;
            """,
        )
        anim = [cmd for cmd in parsed.commands if isinstance(cmd, Animate)]
        self.assertEqual(anim[0].name, "chars.alice")
        self.assertEqual(anim[0].action, "move")
        self.assertEqual((anim[0].v1, anim[0].v2), (900.0, 520.0))
        self.assertEqual(anim[0].seconds, 0.6)
        self.assertEqual(anim[0].ease, "inout")

        self.assertEqual(anim[1].action, "size")
        self.assertEqual((anim[1].v1, anim[1].v2), (420.0, 680.0))
        self.assertEqual(anim[1].ease, "out")

        self.assertEqual(anim[2].action, "alpha")
        self.assertEqual(anim[2].v1, 140.0)
        self.assertEqual(anim[2].seconds, 0.4)
        self.assertEqual(anim[2].ease, "in")

        self.assertEqual(anim[3].action, "stop")
        self.assertEqual(anim[3].name, "chars.alice")

    def test_animate_rejects_invalid_ease(self) -> None:
        with self.assertRaisesRegex(ScriptParseError, "animate ease must be one of"):
            self._parse(
                """
                label start:
                    animate card move 100 200 0.6 bounce;
                """,
            )

    def test_sound_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                sound effect "click.wav";
            """,
        )
        sfx = next(cmd for cmd in parsed.commands if isinstance(cmd, Sound))
        self.assertEqual(sfx.path, "click.wav")

    def test_echo_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                echo "rain.ogg" start;
                echo stop;
            """,
        )
        echos = [cmd for cmd in parsed.commands if isinstance(cmd, Echo)]
        self.assertEqual(echos[0].path, "rain.ogg")
        self.assertEqual(echos[0].action, "start")
        self.assertIsNone(echos[1].path)
        self.assertEqual(echos[1].action, "stop")

    def test_voice_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                voice alice "line01.wav";
                voice "line02.wav";
            """,
        )
        voices = [cmd for cmd in parsed.commands if isinstance(cmd, Voice)]
        self.assertEqual(voices[0].character, "alice")
        self.assertEqual(voices[0].path, "line01.wav")
        self.assertIsNone(voices[1].character)
        self.assertEqual(voices[1].path, "line02.wav")

    def test_mute_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                mute music;
            """,
        )
        mute = next(cmd for cmd in parsed.commands if isinstance(cmd, Mute))
        self.assertEqual(mute.target, "music")

    def test_preload_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                preload bg "park.png";
            """,
        )
        preload = next(cmd for cmd in parsed.commands if isinstance(cmd, Preload))
        self.assertEqual(preload.kind, "bg")
        self.assertEqual(preload.path, "park.png")

    def test_cache_commands(self) -> None:
        parsed = self._parse(
            """
            label start:
                cache clear images;
                cache clear scripts;
                cache clear runtime;
                cache clear scene;
                cache clear script "chapters/intro.vn";
                cache pin sprites "hero.png";
                cache unpin sprites "hero.png";
            """,
        )
        clears = [cmd for cmd in parsed.commands if isinstance(cmd, CacheClear)]
        pin = next(cmd for cmd in parsed.commands if isinstance(cmd, CachePin))
        unpin = next(cmd for cmd in parsed.commands if isinstance(cmd, CacheUnpin))
        self.assertEqual([cmd.kind for cmd in clears], ["images", "scripts", "runtime", "runtime", "script"])
        self.assertEqual(clears[-1].path, "chapters/intro.vn")
        self.assertEqual(pin.kind, "sprites")
        self.assertEqual(pin.path, "hero.png")
        self.assertEqual(unpin.kind, "sprites")
        self.assertEqual(unpin.path, "hero.png")

    def test_gc_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                gc;
            """,
        )
        self.assertTrue(any(isinstance(cmd, GarbageCollect) for cmd in parsed.commands))

    def test_wait_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                wait 0.75;
            """,
        )
        wait = next(cmd for cmd in parsed.commands if isinstance(cmd, Wait))
        self.assertEqual(wait.seconds, 0.75)

    def test_wait_voice_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                wait voice;
            """,
        )
        self.assertTrue(any(isinstance(cmd, WaitVoice) for cmd in parsed.commands))

    def test_wait_video_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                wait video;
            """,
        )
        self.assertTrue(any(isinstance(cmd, WaitVideo) for cmd in parsed.commands))

    def test_notify_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                notify "Tip text" 2.5;
            """,
        )
        notify = next(cmd for cmd in parsed.commands if isinstance(cmd, Notify))
        self.assertEqual(notify.text, "Tip text")
        self.assertEqual(notify.seconds, 2.5)

    def test_blend_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                blend fade 0.8;
            """,
        )
        blend = next(cmd for cmd in parsed.commands if isinstance(cmd, Blend))
        self.assertEqual(blend.style, "fade")
        self.assertEqual(blend.seconds, 0.8)

    def test_blend_accepts_all_supported_styles(self) -> None:
        styles = ["fade", "wipe", "slide", "dissolve", "zoom", "blur", "flash", "shake", "none"]
        body_lines = ["label start:"] + [f"    blend {style} 0.5;" for style in styles]
        parsed = self._parse("\n".join(body_lines))
        found = [cmd.style for cmd in parsed.commands if isinstance(cmd, Blend)]
        self.assertEqual(found, styles)

    def test_blend_rejects_unknown_style(self) -> None:
        with self.assertRaisesRegex(ScriptParseError, "blend style must be one of"):
            self._parse(
                """
                label start:
                    blend warp 0.5;
                """,
            )

    def test_save_and_load_commands(self) -> None:
        parsed = self._parse(
            """
            label start:
                save slot_a;
                load slot_b;
            """,
        )
        save = next(cmd for cmd in parsed.commands if isinstance(cmd, Save))
        load = next(cmd for cmd in parsed.commands if isinstance(cmd, Load))
        self.assertEqual(save.slot, "slot_a")
        self.assertEqual(load.slot, "slot_b")

    def test_set_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                set visits 3;
            """,
        )
        set_var = next(cmd for cmd in parsed.commands if isinstance(cmd, SetVar))
        self.assertEqual(set_var.name, "visits")
        self.assertEqual(set_var.value, 3)

    def test_track_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                track rel gf +5;
            """,
        )
        track = next(cmd for cmd in parsed.commands if isinstance(cmd, AddVar))
        self.assertEqual(track.name, "rel_gf")
        self.assertEqual(track.amount, 5)

    def test_check_goto_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                check coins >= 10 go rich;
            """,
        )
        cond = next(cmd for cmd in parsed.commands if isinstance(cmd, IfJump))
        self.assertEqual(cond.name, "coins")
        self.assertEqual(cond.op, ">=")
        self.assertEqual(cond.value, 10)
        self.assertEqual(cond.target, "rich")

    def test_check_block_command(self) -> None:
        parsed = self._parse(
            """
            label start:
                check visits > 1 {
                    narrator "inside";
                };
            """,
        )
        gate = next(cmd for cmd in parsed.commands if isinstance(cmd, IfJump))
        self.assertEqual(gate.op, "<=")
        self.assertTrue(gate.target.startswith("__check_skip_"))
        self.assertIn(gate.target, parsed.labels)

    def test_loading_and_call_commands(self) -> None:
        parsed = self._parse(
            """
            label start:
                loading "Prep" {
                    preload audio "bell.wav";
                    call "chapters/boot.vn" intro;
                };
            """,
            extra_files={
                "chapters/boot.vn": """
                label intro:
                    narrator "boot";
                """,
            },
        )
        loading = [cmd for cmd in parsed.commands if isinstance(cmd, Loading)]
        call = next(cmd for cmd in parsed.commands if isinstance(cmd, Call))
        self.assertEqual([item.action for item in loading], ["start", "end"])
        self.assertEqual(call.path, "chapters/boot.vn")
        self.assertEqual(call.label, "intro")

    def test_call_without_loading_block(self) -> None:
        parsed = self._parse(
            """
            label start:
                call "chapters/boot.vn" intro;
            """,
            extra_files={
                "chapters/boot.vn": """
                label intro:
                    narrator "boot";
                """,
            },
        )
        call = next(cmd for cmd in parsed.commands if isinstance(cmd, Call))
        self.assertEqual(call.path, "chapters/boot.vn")
        self.assertEqual(call.label, "intro")

    def test_include_command(self) -> None:
        parsed = self._parse(
            """
            include "chapters/intro.vn" as intro;

            label start:
                go intro.opening;
            """,
            extra_files={
                "chapters/intro.vn": """
                label opening:
                    narrator "hello";
                """,
            },
        )
        self.assertIn("intro.opening", parsed.labels)
        self.assertTrue(any(isinstance(cmd, Jump) and cmd.target == "intro.opening" for cmd in parsed.commands))

    def test_include_must_appear_before_other_commands(self) -> None:
        with self.assertRaisesRegex(ScriptParseError, "include must appear before any other commands"):
            self._parse(
                """
                label start:
                    narrator "x";

                include "chapters/intro.vn" as intro;
                """,
                extra_files={
                    "chapters/intro.vn": """
                    label opening:
                        narrator "hello";
                    """,
                },
            )

    def test_character_block_command(self) -> None:
        parsed = self._parse(
            """
            character alice {
                name "Alice";
                color "#ff3366";
                voice "alice";
                pos 900 620;
                z 7;
                float 3 1.4;
                sprite default "alice/default.png";
                sprite happy "alice/happy.png";
            };

            label start:
                show alice happy;
            """,
        )
        char_def = next(cmd for cmd in parsed.commands if isinstance(cmd, CharacterDef))
        self.assertEqual(char_def.ident, "alice")
        self.assertEqual(char_def.display_name, "Alice")
        self.assertEqual(char_def.color, "#ff3366")
        self.assertEqual(char_def.voice_tag, "alice")
        self.assertEqual(char_def.pos, (900, 620))
        self.assertEqual(char_def.z, 7)
        self.assertEqual(char_def.float_amp, 3.0)
        self.assertEqual(char_def.float_speed, 1.4)
        self.assertEqual(char_def.sprites, {"default": "alice/default.png", "happy": "alice/happy.png"})

    # ── Input tests ──────────────────────────────────────────────
    def test_input_basic(self):
        parsed = self._parse('input player_name "What is your name?";')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Input)
        self.assertEqual(cmd.variable, "player_name")
        self.assertEqual(cmd.prompt, "What is your name?")
        self.assertIsNone(cmd.default_value)

    def test_input_with_default(self):
        parsed = self._parse('input player_name "Your name?" default "Player";')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Input)
        self.assertEqual(cmd.variable, "player_name")
        self.assertEqual(cmd.prompt, "Your name?")
        self.assertEqual(cmd.default_value, "Player")

    # ── Timed Choice tests ───────────────────────────────────────
    def test_timed_choice(self):
        script = textwrap.dedent("""\
            ask "Run or hide?" timeout 5.0 default 2
                "Run" -> run_label
                "Hide" -> hide_label;
        """)
        parsed = self._parse(script)
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Choice)
        self.assertEqual(cmd.prompt, "Run or hide?")
        self.assertEqual(cmd.timeout, 5.0)
        self.assertEqual(cmd.timeout_default, 2)
        self.assertEqual(len(cmd.options), 2)

    def test_choice_no_timeout(self):
        script = textwrap.dedent("""\
            ask "Pick one"
                "A" -> a_label
                "B" -> b_label;
        """)
        parsed = self._parse(script)
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Choice)
        self.assertIsNone(cmd.timeout)
        self.assertIsNone(cmd.timeout_default)

    # ── Phone tests ──────────────────────────────────────────────
    def test_phone_open(self):
        parsed = self._parse('phone open "Alice";')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Phone)
        self.assertEqual(cmd.action, "open")
        self.assertEqual(cmd.contact, "Alice")

    def test_phone_msg(self):
        parsed = self._parse('phone msg left "Hello!";')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Phone)
        self.assertEqual(cmd.action, "msg")
        self.assertEqual(cmd.side, "left")
        self.assertEqual(cmd.text, "Hello!")

    def test_phone_close(self):
        parsed = self._parse('phone close;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Phone)
        self.assertEqual(cmd.action, "close")

    # ── Meter tests ──────────────────────────────────────────────
    def test_meter_show(self):
        parsed = self._parse('meter show trust "Trust" 0 100 color #4ecdc4;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Meter)
        self.assertEqual(cmd.action, "show")
        self.assertEqual(cmd.variable, "trust")
        self.assertEqual(cmd.label, "Trust")
        self.assertEqual(cmd.min_val, 0)
        self.assertEqual(cmd.max_val, 100)
        self.assertEqual(cmd.color, "#4ecdc4")

    def test_meter_hide(self):
        parsed = self._parse('meter hide trust;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Meter)
        self.assertEqual(cmd.action, "hide")
        self.assertEqual(cmd.variable, "trust")

    def test_meter_update(self):
        parsed = self._parse('meter update trust;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Meter)
        self.assertEqual(cmd.action, "update")
        self.assertEqual(cmd.variable, "trust")

    def test_meter_clear(self):
        parsed = self._parse('meter clear;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Meter)
        self.assertEqual(cmd.action, "clear")

    # ── Item tests ──────────────────────────────────────────────
    def test_item_add(self):
        parsed = self._parse('item add potion "HP Potion" "Heals 50" icon "items/potion.png" amount 2;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Item)
        self.assertEqual(cmd.action, "add")
        self.assertEqual(cmd.item_id, "potion")
        self.assertEqual(cmd.name, "HP Potion")
        self.assertEqual(cmd.description, "Heals 50")
        self.assertEqual(cmd.icon, "items/potion.png")
        self.assertEqual(cmd.amount, 2)

    def test_item_remove(self):
        parsed = self._parse('item remove potion amount 1;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Item)
        self.assertEqual(cmd.action, "remove")
        self.assertEqual(cmd.item_id, "potion")
        self.assertEqual(cmd.amount, 1)

    def test_item_clear(self):
        parsed = self._parse('item clear;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Item)
        self.assertEqual(cmd.action, "clear")

    # ── Map tests ──────────────────────────────────────────────
    def test_map_show(self):
        parsed = self._parse('map show "world_map.png";')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Map)
        self.assertEqual(cmd.action, "show")
        self.assertEqual(cmd.value, "world_map.png")

    def test_map_poi(self):
        parsed = self._parse('map poi "Town" 400 300 -> town_label;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Map)
        self.assertEqual(cmd.action, "poi")
        self.assertEqual(cmd.label, "Town")
        self.assertEqual(cmd.pos, (400, 300))
        self.assertEqual(cmd.target, "town_label")

    def test_map_hide(self):
        parsed = self._parse('map hide;')
        cmd = parsed.commands[0]
        self.assertIsInstance(cmd, Map)
        self.assertEqual(cmd.action, "hide")


if __name__ == "__main__":
    unittest.main()
