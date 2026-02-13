# cython: language_level=3
# cython: wraparound=False
# cython: boundscheck=False

from pathlib import Path
from .video import VideoBackendUnavailable
from .video_vnef import VnefVideoPlayback

def normalize_video_backend(object value, str default="auto") -> str:
    if value is None:
        return default
    cdef str text = str(value).strip().lower()
    
    if not text:
        return default
    if text in {"auto", "default"}:
        return "auto"
    if text in {"vnef", "native", "vnef-video", "vnef_video"}:
        return "vnef"
    if text in {"imageio", "imageio-ffmpeg"}:
        return "vnef"
        
    return default


def create_video_playback(
    object path,
    bint loop=False,
    str backend="auto",
    bint audio_enabled=True,
    bint framedrop=True,
):
    cdef str selected = normalize_video_backend(backend, default="auto")
    if selected not in {"auto", "vnef"}:
        selected = "auto"

    try:
        return VnefVideoPlayback(
            path=path, 
            loop=loop, 
            audio_enabled=audio_enabled, 
            framedrop=framedrop
        )
    except Exception as exc:
        raise VideoBackendUnavailable(f"vnef: {type(exc).__name__}: {exc}") from exc
