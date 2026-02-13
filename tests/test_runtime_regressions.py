from __future__ import annotations

import json
from pathlib import Path
import os
import tempfile
import unittest
from unittest.mock import patch

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")

import pygame

from vn.config import UiConfig
from vn.runtime.impl import VNRuntime, _compare_numbers
from vn.runtime.scene_manifest import SceneManifest
from vn.script import (
    AddVar,
    Animate,
    CameraSet,
    CacheClear,
    CharacterDef,
    Choice,
    HotspotAdd,
    HotspotPoly,
    HotspotRemove,
    IfJump,
    Label,
    Map,
    Notify,
    Say,
    SetVar,
    Show,
    ShowChar,
    Video,
    Voice,
    WaitVideo,
)


class _DummyAssets:
    def __init__(self, root: Path):
        self.project_root = root
        self.last_prune_images: set[Path] = set()
        self.last_prune_sounds: set[Path] = set()

    def load_image(self, path: str, kind: str) -> pygame.Surface:
        surface = pygame.Surface((64, 64), pygame.SRCALPHA)
        surface.fill((255, 255, 255, 255))
        return surface

    def resolve_path(self, path: str, kind: str) -> Path:
        p = Path(path)
        if p.is_absolute():
            return p
        return (self.project_root / p).resolve()

    def make_color_surface(self, color: str, size: tuple[int, int] | None = None) -> pygame.Surface:
        if size is None:
            size = (1280, 720)
        return pygame.Surface(size, pygame.SRCALPHA)

    def make_rect_surface(self, color: str, size: tuple[int, int]) -> pygame.Surface:
        return pygame.Surface(size, pygame.SRCALPHA)

    def play_sound(self, path: str) -> None:
        return

    def play_music(self, path: str, loop: bool = True) -> None:
        return

    def play_echo(self, path: str) -> None:
        return

    def stop_echo(self) -> None:
        return

    def play_voice(self, path: str) -> None:
        return

    def is_voice_playing(self) -> bool:
        return False

    def mute(self, target: str = "all") -> None:
        return

    def clear_images(self) -> None:
        return

    def clear_sounds(self) -> None:
        return

    def clear_all(self) -> None:
        return

    def prune_images(self, keep: set[Path]) -> None:
        self.last_prune_images = set(keep)

    def prune_sounds(self, keep: set[Path]) -> None:
        self.last_prune_sounds = set(keep)

    def pin_sound(self, path: str) -> None:
        return

    def unpin_sound(self, path: str) -> None:
        return

    def pin_image(self, path: str, kind: str) -> None:
        return

    def unpin_image(self, path: str, kind: str) -> None:
        return

    def preload_sound(self, path: str) -> None:
        return

    def preload_image(self, path: str, kind: str) -> None:
        return


class RuntimeRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        pygame.init()
        pygame.font.init()

    @classmethod
    def tearDownClass(cls) -> None:
        pygame.quit()

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        tmp_path = Path(self._tmp.name)
        screen = pygame.Surface((1280, 720))
        assets = _DummyAssets(tmp_path)
        self.runtime = VNRuntime(
            commands=[],
            labels={},
            screen=screen,
            assets=assets,  # type: ignore[arg-type]
            save_path=tmp_path / "save.json",
            script_path=tmp_path / "script.vn",
            ui=UiConfig(),
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_compare_numbers_operators(self) -> None:
        self.assertTrue(_compare_numbers(2, 2, "=="))
        self.assertTrue(_compare_numbers(2, 3, "!="))
        self.assertTrue(_compare_numbers(4, 3, ">"))
        self.assertTrue(_compare_numbers(4, 4, ">="))
        self.assertTrue(_compare_numbers(3, 4, "<"))
        self.assertTrue(_compare_numbers(4, 4, "<="))
        self.assertFalse(_compare_numbers(1, 2, ">"))

    def test_eval_condition_numeric_and_string(self) -> None:
        self.runtime.variables["coins"] = 10
        self.runtime.variables["name"] = "alice"

        self.assertTrue(self.runtime._eval_condition(IfJump(name="coins", op=">=", value=10, target="x")))
        self.assertFalse(self.runtime._eval_condition(IfJump(name="coins", op="<", value=5, target="x")))
        self.assertTrue(self.runtime._eval_condition(IfJump(name="name", op="==", value="alice", target="x")))
        self.assertTrue(self.runtime._eval_condition(IfJump(name="name", op="!=", value="bob", target="x")))

    def test_eval_condition_right_side_can_reference_variable(self) -> None:
        self.runtime.variables["coins"] = 8
        self.runtime.variables["target"] = 10
        self.runtime.variables["state"] = "ok"
        self.runtime.variables["expected"] = "ok"

        self.assertTrue(self.runtime._eval_condition(IfJump(name="coins", op="<", value="$target", target="x")))
        self.assertTrue(self.runtime._eval_condition(IfJump(name="state", op="==", value="$expected", target="x")))
        self.assertFalse(self.runtime._eval_condition(IfJump(name="coins", op=">", value="$target", target="x")))

    def test_resolve_voice_path_with_voice_tag(self) -> None:
        self.runtime.characters["chars.alice"] = CharacterDef(
            ident="chars.alice",
            display_name="Alice",
            voice_tag="alice",
        )

        self.assertEqual(
            self.runtime._resolve_voice_path(Voice(character="chars.alice", path="line01.wav")),
            "alice/line01.wav",
        )
        self.assertEqual(
            self.runtime._resolve_voice_path(Voice(character="chars.alice", path="../raw.wav")),
            "../raw.wav",
        )
        self.assertEqual(self.runtime._resolve_voice_path(Voice(character=None, path="raw.wav")), "raw.wav")

    def test_apply_show_char_uses_defaults_and_fallback(self) -> None:
        self.runtime._apply_character_def(
            CharacterDef(
                ident="chars.alice",
                display_name="Alice",
                sprites={"default": "alice/default.png", "happy": "alice/happy.png"},
                anchor="right bottom",
                z=3,
                float_amp=4.0,
                float_speed=1.0,
            )
        )

        self.runtime._apply_show_char(ShowChar(ident="chars.alice", expression="happy"))
        sprite = self.runtime.sprites["chars.alice"]
        self.assertEqual(sprite.state.value, "alice/happy.png")
        self.assertEqual(sprite.state.anchor, "right bottom")
        self.assertEqual(sprite.state.z, 3)
        self.assertEqual(sprite.state.float_amp, 4.0)
        self.assertEqual(sprite.state.float_speed, 1.0)

        self.runtime._apply_show_char(ShowChar(ident="chars.alice", expression="missing"))
        sprite = self.runtime.sprites["chars.alice"]
        self.assertEqual(sprite.state.value, "alice/default.png")

        self.runtime._apply_show_char(ShowChar(ident="chars.alice", expression="happy", float_amp=9.0, float_speed=2.0))
        sprite = self.runtime.sprites["chars.alice"]
        self.assertEqual(sprite.state.float_amp, 9.0)
        self.assertEqual(sprite.state.float_speed, 2.0)

    def test_apply_show_image_with_size_scales_surface(self) -> None:
        self.runtime._apply_show(
            Show(
                kind="image",
                name="poster",
                value="poster.png",
                size=(200, 120),
                pos=(40, 60),
                anchor=None,
                z=0,
            )
        )
        sprite = self.runtime.sprites["poster"]
        self.assertEqual(sprite.rect.size, (200, 120))
        self.assertEqual(sprite.state.size, (200, 120))
        self.assertEqual(sprite.state.pos, (40, 60))

    def test_apply_add_resets_non_numeric(self) -> None:
        self.runtime.variables["visits"] = "bad"
        self.runtime._apply_add(AddVar(name="visits", amount=3))
        self.assertEqual(self.runtime.variables["visits"], 3)

    def test_apply_notify_sets_message_and_timeout(self) -> None:
        self.runtime._apply_notify(Notify(text="Tip!", seconds=1.2))
        self.assertEqual(self.runtime.notify_message, "Tip!")
        self.assertIsNotNone(self.runtime.notify_until_ms)

    def test_set_say_choice_notify_support_variable_interpolation(self) -> None:
        self.runtime.commands = [
            SetVar(name="coins", value=7),
            SetVar(name="copy", value="$coins"),
            SetVar(name="name", value="mia"),
            Notify(text="Hi ${name}", seconds=1.0),
            Say(speaker="narrator", text="coins=${copy}"),
            Choice(options=[("Talk to ${name}", "x")], prompt="coins=${coins}"),
        ]
        self.runtime.index = 0

        self.runtime._step()
        self.assertEqual(self.runtime.variables["copy"], 7)
        self.assertEqual(self.runtime.notify_message, "Hi mia")
        self.assertEqual(self.runtime.current_say, ("narrator", "coins=7"))

        self.runtime.current_say = None
        self.runtime._step()
        self.assertIsNotNone(self.runtime.current_choice)
        self.assertEqual(self.runtime.current_choice.options[0][0], "Talk to mia")
        self.assertEqual(self.runtime.current_choice.prompt, "coins=7")

    def test_hotspot_add_remove(self) -> None:
        self.runtime._apply_hotspot_add(HotspotAdd(name="kitchen", x=10, y=20, w=100, h=80, target="room"))
        self.assertIn("kitchen", self.runtime.hotspots)
        self.runtime._apply_hotspot_remove(HotspotRemove(name="kitchen"))
        self.assertNotIn("kitchen", self.runtime.hotspots)

    def test_hotspot_click_jumps_to_target(self) -> None:
        self.runtime.commands = [Label("room"), Notify(text="Entered", seconds=0.5)]
        self.runtime.labels = {"room": 0}
        self.runtime.index = len(self.runtime.commands)
        self.runtime._apply_hotspot_add(HotspotAdd(name="room_hs", x=0, y=0, w=200, h=200, target="room"))
        self.assertTrue(self.runtime._handle_hotspot_click((100, 100)))
        self.assertEqual(self.runtime.notify_message, "Entered")

    def test_jump_accepts_global_prefix(self) -> None:
        self.runtime.labels = {"end": 7}
        self.runtime._jump("::end")
        self.assertEqual(self.runtime.index, 7)

    def test_inventory_toggle_respects_feature_flag(self) -> None:
        self.runtime.feature_flags["items"] = False
        self.runtime.inventory_active = False
        self.runtime._jump("inventory_toggle")
        self.assertFalse(self.runtime.inventory_active)

        pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=pygame.K_i))
        self.runtime._handle_events()
        self.assertFalse(self.runtime.inventory_active)

    def test_inventory_page_scroll_clamps(self) -> None:
        for idx in range(27):
            item_id = f"item_{idx}"
            self.runtime.inventory[item_id] = {
                "name": item_id,
                "desc": "d",
                "icon": None,
                "count": 1,
            }
        self.runtime.inventory_items_per_page = 10
        self.runtime.inventory_page = 0

        self.runtime._scroll_inventory_page(1)
        self.assertEqual(self.runtime.inventory_page, 1)
        self.runtime._scroll_inventory_page(10)
        self.assertEqual(self.runtime.inventory_page, 2)
        self.runtime._scroll_inventory_page(-10)
        self.assertEqual(self.runtime.inventory_page, 0)

    def test_polygon_hotspot_respects_camera_transform(self) -> None:
        self.runtime.commands = [Label("poly"), Notify(text="Poly hit", seconds=0.5)]
        self.runtime.labels = {"poly": 0}
        self.runtime.index = len(self.runtime.commands)
        self.runtime._apply_hotspot_poly(
            HotspotPoly(
                name="poly_hs",
                points=[(500, 280), (760, 280), (740, 520), (480, 510)],
                target="poly",
            )
        )
        self.runtime._apply_camera(CameraSet(pan_x=120, pan_y=-40, zoom=1.5))
        sx, sy = self.runtime._bg_world_to_screen((620, 390))
        self.assertTrue(self.runtime._handle_hotspot_click((int(sx), int(sy))))
        self.assertEqual(self.runtime.notify_message, "Poly hit")

    def test_map_show_consumes_following_poi_and_click_executes_target(self) -> None:
        self.runtime.commands = [
            Map(action="show", value="world.png"),
            Map(action="poi", label="Start", pos=(100, 100), points=[], target="next"),
            Label("next"),
            Notify(text="Entered map target", seconds=0.5),
        ]
        self.runtime.labels = {"next": 2}
        self.runtime.index = 0

        self.runtime._step()
        self.assertTrue(self.runtime.map_active)
        self.assertEqual(len(self.runtime.map_points), 1)
        self.assertEqual(self.runtime.index, 2)

        evt = pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=(100, 100), button=1)
        self.runtime._handle_map_mousedown(evt)

        self.assertFalse(self.runtime.map_active)
        self.assertEqual(self.runtime.notify_message, "Entered map target")

    def test_sprite_animate_move_size_alpha(self) -> None:
        self.runtime._apply_show(
            Show(
                kind="rect",
                name="box",
                value="#ffffff",
                size=(64, 64),
                pos=(10, 20),
                anchor=None,
                z=0,
            )
        )

        self.runtime._apply_animate(Animate(name="box", action="move", v1=120, v2=150, seconds=0.5, ease="linear"))
        move_track = self.runtime.sprite_animations["box"]["move"]
        move_track.start_ms -= move_track.duration_ms
        self.runtime._update_sprite_animations()
        self.assertEqual(self.runtime.sprites["box"].rect.topleft, (120, 150))

        self.runtime._apply_animate(Animate(name="box", action="size", v1=200, v2=100, seconds=0.5, ease="out"))
        size_track = self.runtime.sprite_animations["box"]["size"]
        size_track.start_ms -= size_track.duration_ms
        self.runtime._update_sprite_animations()
        self.assertEqual(self.runtime.sprites["box"].rect.size, (200, 100))

        self.runtime._apply_animate(Animate(name="box", action="alpha", v1=96, seconds=0.5, ease="in"))
        alpha_track = self.runtime.sprite_animations["box"]["alpha"]
        alpha_track.start_ms -= alpha_track.duration_ms
        self.runtime._update_sprite_animations()
        self.assertEqual(self.runtime.sprites["box"].state.alpha, 96)
        self.assertNotIn("box", self.runtime.sprite_animations)

    def test_sprite_animate_stop_clears_tracks(self) -> None:
        self.runtime._apply_show(
            Show(
                kind="rect",
                name="box",
                value="#ffffff",
                size=(64, 64),
                pos=(0, 0),
                anchor=None,
                z=0,
            )
        )
        self.runtime._apply_animate(Animate(name="box", action="move", v1=50, v2=60, seconds=1.0, ease="linear"))
        self.assertIn("box", self.runtime.sprite_animations)
        self.runtime._apply_animate(Animate(name="box", action="stop"))
        self.assertNotIn("box", self.runtime.sprite_animations)

    def test_video_play_and_stop(self) -> None:
        clip = Path(self._tmp.name) / "clip.mp4"
        clip.write_bytes(b"fake")

        class _FakePlayback:
            def __init__(self, path: Path, loop: bool = False) -> None:
                self.path = path
                self.loop = loop
                self.closed = False

            def update(self, now_ms: int):
                surface = pygame.Surface((16, 16), pygame.SRCALPHA)
                return surface, False

            def close(self) -> None:
                self.closed = True

        with patch("vn.runtime.impl.create_video_playback", return_value=_FakePlayback(clip, loop=True)):
            self.runtime._apply_video(Video(action="play", path="clip.mp4", loop=True, fit="cover"))
            self.assertIsNotNone(self.runtime.video_player)
            self.assertEqual(self.runtime.video_path, "clip.mp4")
            self.assertEqual(self.runtime.video_fit, "cover")
            self.assertTrue(self.runtime.video_loop)
            self.assertIsNotNone(self.runtime.video_surface)
            self.assertEqual(self.runtime.video_backend_active, "auto")

            player = self.runtime.video_player
            self.runtime._apply_video(Video(action="stop"))
            self.assertIsNone(self.runtime.video_player)
            self.assertIsNone(self.runtime.video_surface)
            self.assertIsNone(self.runtime.video_path)
            self.assertEqual(self.runtime.video_backend_active, "none")
            self.assertTrue(player.closed)

    def test_wait_video_tracks_video_activity(self) -> None:
        self.runtime.video_player = object()
        self.assertTrue(self.runtime._apply_wait_video())
        self.assertTrue(self.runtime._is_waiting())
        self.runtime.video_player = None
        self.runtime.video_audio_pending.clear()
        self.runtime.video_audio_pcm_buffer.clear()
        self.assertFalse(self.runtime._is_video_active())
        self.runtime.wait_for_video = True
        self.runtime._update_timers()
        self.assertFalse(self.runtime.wait_for_video)

    def test_save_quick_writes_schema_and_relative_script_path(self) -> None:
        self.runtime.current_script_path = (Path(self._tmp.name) / "chapters" / "intro.vn").resolve()
        self.runtime.current_script_path.parent.mkdir(parents=True, exist_ok=True)
        self.runtime.current_script_path.write_text("label start:\n", encoding="utf-8")
        self.runtime.inventory["coin"] = {"name": "Coin", "desc": "currency", "icon": None, "count": 2}
        self.runtime.map_active = True
        self.runtime.map_image = "world.png"
        self.runtime.map_points = [{"label": "Town", "target": "town", "pos": (100, 120), "points": []}]

        self.runtime.save_quick()

        payload = json.loads(self.runtime.save_path.read_text(encoding="utf-8"))
        self.assertEqual(payload.get("save_version"), 2)
        self.assertEqual(payload.get("script_path"), "chapters/intro.vn")
        self.assertIn("inventory", payload)
        self.assertIn("map", payload)
        self.assertFalse(self.runtime.save_path.with_suffix(".json.tmp").exists())

    def test_load_quick_ignores_malformed_json(self) -> None:
        self.runtime.save_path.write_text("{", encoding="utf-8")
        self.runtime.index = 5
        self.runtime.load_quick()
        self.assertEqual(self.runtime.index, 5)

    def test_apply_save_data_restores_script_ui_and_choice_timeout(self) -> None:
        tmp = Path(self._tmp.name)
        scene_path = (tmp / "chapters" / "scene.vn").resolve()
        scene_path.parent.mkdir(parents=True, exist_ok=True)
        scene_path.write_text("label start:\n", encoding="utf-8")
        loaded_commands = [Label("start"), Notify(text="ok", seconds=0.5)]
        loaded_labels = {"start": 0}
        loaded_manifest = SceneManifest()

        payload = {
            "save_version": 2,
            "script_path": "chapters/scene.vn",
            "index": 1,
            "background": {"kind": "color", "value": "#112233", "float_amp": 2.0, "float_speed": 0.4},
            "vars": {"coins": 7},
            "sprites": {},
            "inventory": {"key": {"name": "Key", "desc": "Door key", "icon": None, "count": 1}},
            "inventory_page": 0,
            "inventory_open": True,
            "meters": {"trust": {"label": "Trust", "min": 0, "max": 100, "value": 42, "color": "#44ff99"}},
            "hud_buttons": [
                {
                    "name": "menu",
                    "style": "text",
                    "text": "Menu",
                    "icon": None,
                    "target": "::start",
                    "rect": [10, 12, 90, 30],
                }
            ],
            "music": {"path": "bgm.ogg", "loop": True},
            "waiting": {
                "type": "choice",
                "options": [["Go", "start"], ["Quit", "end"]],
                "selected": 1,
                "prompt": "Select",
                "timeout_ms": 8000,
                "timeout_default": 2,
                "timeout_elapsed_ms": 500,
            },
            "characters": {},
            "hotspots": [],
            "hotspot_debug": False,
            "map": {
                "active": True,
                "image": "world_map.png",
                "points": [
                    {"label": "Town", "target": "town", "pos": [100, 120], "points": [[80, 110], [120, 110], [120, 140]]}
                ],
            },
            "camera": {"pan_x": 3.5, "pan_y": -2.0, "zoom": 1.25},
        }

        with patch.object(self.runtime, "_load_script", return_value=(loaded_commands, loaded_labels, loaded_manifest)):
            self.runtime._apply_save_data(payload)

        self.assertEqual(self.runtime.current_script_path, scene_path)
        self.assertEqual(self.runtime.commands, loaded_commands)
        self.assertEqual(self.runtime.labels, loaded_labels)
        self.assertEqual(self.runtime.index, 1)
        self.assertEqual(self.runtime.variables.get("coins"), 7)
        self.assertTrue(self.runtime.inventory_active)
        self.assertIn("key", self.runtime.inventory)
        self.assertIn("trust", self.runtime.meters)
        self.assertIn("menu", self.runtime.hud_buttons)
        self.assertTrue(self.runtime.map_active)
        self.assertEqual(self.runtime.map_image, "world_map.png")
        self.assertEqual(len(self.runtime.map_points), 1)
        self.assertIsNotNone(self.runtime.current_choice)
        self.assertEqual(self.runtime.choice_selected, 1)
        self.assertEqual(self.runtime.choice_timeout_ms, 8000)
        self.assertEqual(self.runtime.choice_timeout_default, 2)
        self.assertIsNotNone(self.runtime.choice_timer_start_ms)

    def test_pause_menu_quick_save_and_quick_load_restore_state(self) -> None:
        self.runtime.variables["coins"] = 11
        self.runtime._pause_menu_open("menu")
        self.assertTrue(self.runtime.pause_menu_active)

        self.runtime._pause_menu_execute_action("quick_save")
        self.runtime.variables["coins"] = 99
        self.runtime._pause_menu_execute_action("quick_load")

        self.assertEqual(self.runtime.variables["coins"], 11)
        self.assertFalse(self.runtime.pause_menu_active)

    def test_pause_menu_slot_save_and_load(self) -> None:
        self.runtime.variables["chapter"] = "A"
        self.runtime._pause_menu_open("save")
        self.runtime._pause_menu_slot_action("slot_1")

        self.runtime.variables["chapter"] = "B"
        self.runtime._pause_menu_open("load")
        self.runtime._pause_menu_slot_action("slot_1")

        self.assertEqual(self.runtime.variables["chapter"], "A")
        self.assertFalse(self.runtime.pause_menu_active)

    def test_title_menu_new_game_runs_script_start(self) -> None:
        tmp_path = Path(self._tmp.name)
        screen = pygame.Surface((1280, 720))
        assets = _DummyAssets(tmp_path)
        runtime = VNRuntime(
            commands=[Label("start"), SetVar(name="coins", value=7)],
            labels={"start": 0},
            screen=screen,
            assets=assets,  # type: ignore[arg-type]
            save_path=tmp_path / "save.json",
            script_path=tmp_path / "script.vn",
            ui=UiConfig(title_menu_enabled=True, title_menu_file=""),
        )
        self.assertTrue(runtime.title_menu_active)
        runtime._title_menu_execute_action("new_game")
        self.assertFalse(runtime.title_menu_active)
        self.assertTrue(runtime.title_menu_started_game)
        self.assertEqual(runtime.variables.get("coins"), 7)

    def test_title_menu_continue_uses_quicksave(self) -> None:
        tmp_path = Path(self._tmp.name)
        screen = pygame.Surface((1280, 720))
        assets = _DummyAssets(tmp_path)
        runtime = VNRuntime(
            commands=[],
            labels={},
            screen=screen,
            assets=assets,  # type: ignore[arg-type]
            save_path=tmp_path / "save.json",
            script_path=tmp_path / "script.vn",
            ui=UiConfig(title_menu_enabled=True, title_menu_file=""),
        )
        runtime.variables["coins"] = 41
        runtime.save_quick()
        runtime.variables["coins"] = 999
        runtime._title_menu_execute_action("continue")
        self.assertEqual(runtime.variables.get("coins"), 41)
        self.assertFalse(runtime.title_menu_active)

    def test_cache_clear_scripts_only_clears_script_cache(self) -> None:
        tmp = Path(self._tmp.name)
        self.runtime._script_cache = {
            (tmp / "a.vn"): ([], {}, SceneManifest()),
            (tmp / "b.vn"): ([], {}, SceneManifest()),
        }
        self.runtime._apply_show(Show(kind="rect", name="hero", value="#fff", size=(8, 8)))
        self.runtime._apply_cache_clear(CacheClear(kind="scripts"))
        self.assertEqual(self.runtime._script_cache, {})
        self.assertIn("hero", self.runtime.sprites)

    def test_cache_clear_single_script_path(self) -> None:
        tmp = Path(self._tmp.name)
        a = (tmp / "a.vn").resolve()
        b = (tmp / "b.vn").resolve()
        self.runtime._script_cache = {
            a: ([], {}, SceneManifest()),
            b: ([], {}, SceneManifest()),
        }
        self.runtime._apply_cache_clear(CacheClear(kind="script", path="a.vn"))
        self.assertNotIn(a, self.runtime._script_cache)
        self.assertIn(b, self.runtime._script_cache)

    def test_cache_clear_single_script_current_also_resets_runtime(self) -> None:
        tmp = Path(self._tmp.name)
        current = (tmp / "script.vn").resolve()
        self.runtime.current_script_path = current
        self.runtime._script_cache = {current: ([], {}, SceneManifest())}
        self.runtime._apply_show(Show(kind="rect", name="hero", value="#fff", size=(10, 10)))
        self.runtime.current_say = ("narrator", "hello")
        self.runtime._apply_cache_clear(CacheClear(kind="script", path="script.vn"))
        self.assertNotIn(current, self.runtime._script_cache)
        self.assertEqual(self.runtime.sprites, {})
        self.assertIsNone(self.runtime.current_say)

    def test_cache_clear_runtime_clears_transient_state(self) -> None:
        tmp = Path(self._tmp.name)
        self.runtime._script_cache = {
            (tmp / "a.vn"): ([], {}, SceneManifest()),
        }
        self.runtime._apply_hotspot_add(HotspotAdd(name="door", x=10, y=10, w=20, h=20, target="next"))
        self.runtime._apply_show(Show(kind="rect", name="hero", value="#fff", size=(10, 10)))
        self.runtime.video_player = object()
        self.runtime.video_surface = pygame.Surface((4, 4), pygame.SRCALPHA)
        self.runtime.current_say = ("narrator", "hello")
        self.runtime.notify_message = "tip"
        self.runtime.wait_until_ms = pygame.time.get_ticks() + 500
        self.runtime.camera_pan_x = 10.0
        self.runtime.camera_pan_y = -5.0
        self.runtime.camera_zoom = 1.6
        self.runtime._apply_cache_clear(CacheClear(kind="runtime"))

        self.assertEqual(self.runtime._script_cache, {})
        self.assertEqual(self.runtime.sprites, {})
        self.assertEqual(self.runtime.hotspots, {})
        self.assertIsNone(self.runtime.video_player)
        self.assertIsNone(self.runtime.video_surface)
        self.assertIsNone(self.runtime.current_say)
        self.assertIsNone(self.runtime.notify_message)
        self.assertIsNone(self.runtime.wait_until_ms)
        self.assertEqual(self.runtime.background_state.kind, "color")
        self.assertEqual(self.runtime.background_state.value, "#000000")
        self.assertEqual(self.runtime.camera_pan_x, 0.0)
        self.assertEqual(self.runtime.camera_pan_y, 0.0)
        self.assertEqual(self.runtime.camera_zoom, 1.0)


if __name__ == "__main__":
    unittest.main()
