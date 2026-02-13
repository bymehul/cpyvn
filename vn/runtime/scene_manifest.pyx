from __future__ import annotations

from dataclasses import dataclass

import cython

from ..script import (
    CachePin,
    Call,
    CharacterDef,
    Command,
    Echo,
    Music,
    Preload,
    Scene,
    Show,
    ShowChar,
    Sound,
    Video,
    Voice,
)


@dataclass(frozen=True)
class SceneManifest:
    bg_images: tuple[str, ...] = ()
    sprite_images: tuple[str, ...] = ()
    audio_paths: tuple[str, ...] = ()
    video_paths: tuple[str, ...] = ()
    script_calls: tuple[str, ...] = ()


@cython.cfunc
@cython.inline
def _norm(path: str) -> str:
    return path.strip()


cpdef str _resolve_voice_path(object character, str raw_path, dict voice_tags):
    if not character:
        return raw_path
    tag = voice_tags.get(character)
    if not tag:
        return raw_path
    if "/" in raw_path or raw_path.startswith("./") or raw_path.startswith("../"):
        return raw_path
    return f"{tag}/{raw_path}"


cpdef object build_scene_manifest(list commands):
    cdef set bg_images = set()
    cdef set sprite_images = set()
    cdef set audio_paths = set()
    cdef set video_paths = set()
    cdef set script_calls = set()
    cdef dict character_sprites = {}
    cdef dict voice_tags = {}
    cdef object cmd
    cdef dict sprites
    cdef object key
    cdef object sprite_path

    for cmd in commands:
        if isinstance(cmd, CharacterDef):
            if cmd.sprites:
                character_sprites[cmd.ident] = dict(cmd.sprites)
            if cmd.voice_tag:
                voice_tags[cmd.ident] = cmd.voice_tag

    for cmd in commands:
        if isinstance(cmd, Scene):
            if cmd.kind == "image":
                bg_images.add(_norm(cmd.value))
            continue

        if isinstance(cmd, Show):
            if cmd.kind == "image":
                sprite_images.add(_norm(cmd.value))
            continue

        if isinstance(cmd, ShowChar):
            sprites = character_sprites.get(cmd.ident)
            if not sprites:
                # fallback mode where expression is used directly as image path
                if cmd.expression:
                    sprite_images.add(_norm(cmd.expression))
                continue
            key = cmd.expression or "default"
            sprite_path = sprites.get(key) or sprites.get("default")
            if sprite_path:
                sprite_images.add(_norm(sprite_path))
            continue

        if isinstance(cmd, Music):
            audio_paths.add(_norm(cmd.path))
            continue

        if isinstance(cmd, Sound):
            audio_paths.add(_norm(cmd.path))
            continue

        if isinstance(cmd, Echo):
            if cmd.action == "start" and cmd.path:
                audio_paths.add(_norm(cmd.path))
            continue

        if isinstance(cmd, Voice):
            voice_path = _resolve_voice_path(cmd.character, cmd.path, voice_tags)
            audio_paths.add(_norm(voice_path))
            continue

        if isinstance(cmd, Preload):
            if cmd.kind == "audio":
                audio_paths.add(_norm(cmd.path))
            elif cmd.kind == "bg":
                bg_images.add(_norm(cmd.path))
            elif cmd.kind == "sprites":
                sprite_images.add(_norm(cmd.path))
            continue

        if isinstance(cmd, CachePin):
            if cmd.kind == "audio":
                audio_paths.add(_norm(cmd.path))
            elif cmd.kind == "bg":
                bg_images.add(_norm(cmd.path))
            elif cmd.kind == "sprites":
                sprite_images.add(_norm(cmd.path))
            continue

        if isinstance(cmd, Video):
            if cmd.action == "play" and cmd.path:
                video_paths.add(_norm(cmd.path))
            continue

        if isinstance(cmd, Call):
            script_calls.add(_norm(cmd.path))
            continue

    return SceneManifest(
        bg_images=tuple(sorted(bg_images)),
        sprite_images=tuple(sorted(sprite_images)),
        audio_paths=tuple(sorted(audio_paths)),
        video_paths=tuple(sorted(video_paths)),
        script_calls=tuple(sorted(script_calls)),
    )
