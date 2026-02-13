# cython: language_level=3
# cython: wraparound=False
# cython: boundscheck=False

import ctypes
import ctypes.util
import os
import sys
from pathlib import Path

import pygame
from libc.string cimport memcpy
from libc.stdint cimport uint8_t, int64_t, uintptr_t
from cpython.bytes cimport PyBytes_FromStringAndSize, PyBytes_AsString

from .video import VideoBackendUnavailable

cdef int _VNE_FRAME_NONE = 0
cdef int _VNE_FRAME_VIDEO = 1
cdef int _VNE_FRAME_AUDIO = 2
cdef int _VNE_FRAME_EOF = 3
cdef int _VNE_FRAME_ERROR = -1
cdef int _MAX_AUDIO_PACKET_BACKLOG = 2048


class _VNEVideo(ctypes.Structure):
    pass

VNEVideoPtr = ctypes.POINTER(_VNEVideo)

class _VNEVideoInfo(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("fps_num", ctypes.c_int),
        ("fps_den", ctypes.c_int),
        ("duration_ms", ctypes.c_int64),
        ("has_audio", ctypes.c_int),
        ("sample_rate", ctypes.c_int),
        ("channels", ctypes.c_int),
    ]

class _VNEVideoFrame(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("stride", ctypes.c_int),
        ("pts_ms", ctypes.c_int64),
        ("data", ctypes.POINTER(ctypes.c_uint8)),
    ]

class _VNEAudioFrame(ctypes.Structure):
    _fields_ = [
        ("sample_rate", ctypes.c_int),
        ("channels", ctypes.c_int),
        ("nb_samples", ctypes.c_int),
        ("bytes_per_sample", ctypes.c_int),
        ("pts_ms", ctypes.c_int64),
        ("data", ctypes.POINTER(ctypes.c_uint8)),
    ]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]

def _candidate_library_paths() -> list[Path]:
    cdef object root = _repo_root()
    cdef list candidates = [
        root / "vnef-video" / "build" / "libvnef_video.so",
        root / "vnef-video" / "build" / "libvnef_video.dylib",
        root / "vnef-video" / "build" / "vnef_video.dll",
        root / "vnef-video" / "build" / "Release" / "vnef_video.dll",
        root / "vnef-video" / "build" / "Debug" / "vnef_video.dll",
    ]
    cdef str env_path = os.getenv("CPYVN_VNEF_VIDEO_LIB", "").strip()
    if env_path:
        candidates.insert(0, Path(env_path))
    return candidates

def _candidate_library_names() -> list[str]:
    if sys.platform.startswith("win"):
        return ["vnef_video.dll"]
    if sys.platform == "darwin":
        return ["libvnef_video.dylib", "vnef_video.dylib"]
    return ["libvnef_video.so", "vnef_video.so"]

def _load_vnef_library() -> ctypes.CDLL:
    cdef list attempts = []

    for path in _candidate_library_paths():
        if not path.exists():
            continue
        try:
            return ctypes.CDLL(str(path))
        except OSError as exc:
            attempts.append(f"{path}: {exc}")

    for name in _candidate_library_names():
        try:
            return ctypes.CDLL(name)
        except OSError as exc:
            attempts.append(f"{name}: {exc}")

    cdef object found = ctypes.util.find_library("vnef_video")
    if found:
        try:
            return ctypes.CDLL(found)
        except OSError as exc:
            attempts.append(f"{found}: {exc}")

    cdef str detail = "; ".join(attempts) if attempts else "library not found"
    raise VideoBackendUnavailable(
        "vnef backend unavailable. Build vnef-video and set CPYVN_VNEF_VIDEO_LIB if needed. "
        f"Attempts: {detail}"
    )

def _bind_vnef_api(object lib) -> None:
    lib.vne_video_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(_VNEVideoInfo)]
    lib.vne_video_open.restype = VNEVideoPtr

    lib.vne_video_close.argtypes = [VNEVideoPtr]
    lib.vne_video_close.restype = None

    lib.vne_video_last_error.argtypes = [VNEVideoPtr]
    lib.vne_video_last_error.restype = ctypes.c_char_p

    lib.vne_video_next.argtypes = [VNEVideoPtr, ctypes.POINTER(_VNEVideoFrame), ctypes.POINTER(_VNEAudioFrame)]
    lib.vne_video_next.restype = ctypes.c_int

    lib.vne_video_free_video_frame.argtypes = [ctypes.POINTER(_VNEVideoFrame)]
    lib.vne_video_free_video_frame.restype = None

    lib.vne_video_free_audio_frame.argtypes = [ctypes.POINTER(_VNEAudioFrame)]
    lib.vne_video_free_audio_frame.restype = None

    lib.vne_video_seek_ms.argtypes = [VNEVideoPtr, ctypes.c_int64]
    lib.vne_video_seek_ms.restype = ctypes.c_int


def _frame_to_surface(object frame) -> pygame.Surface | None:
    cdef int width = frame.width
    cdef int height = frame.height
    cdef int stride = frame.stride
    
    if width <= 0 or height <= 0:
        return None

    cdef object data_obj = frame.data
    if not data_obj:
        return None
        
    cdef uintptr_t src_addr = ctypes.cast(data_obj, ctypes.c_void_p).value
    if not src_addr:
        return None
        
    cdef uint8_t* src_ptr = <uint8_t*>src_addr
    cdef int row_bytes = width * 4
    
    if stride < row_bytes:
        stride = row_bytes

    cdef bytes packed_bytes
    cdef char* dst_ptr
    cdef int y
    
    if stride == row_bytes:
        packed_bytes = PyBytes_FromStringAndSize(<char*>src_ptr, stride * height)
    else:
        packed_bytes = PyBytes_FromStringAndSize(NULL, row_bytes * height)
        dst_ptr = PyBytes_AsString(packed_bytes)
        for y in range(height):
            memcpy(dst_ptr + (y * row_bytes), src_ptr + (y * stride), row_bytes)

    cdef object surface = pygame.image.frombuffer(packed_bytes, (width, height), "RGBA")
    
    try:
        if pygame.display.get_surface() is not None:
            return surface.convert_alpha()
    except pygame.error:
        pass
        
    return surface.copy()


class VnefVideoPlayback:
    backend_name = "vnef"

    def __init__(self, object path, bint loop=False, bint audio_enabled=True, bint framedrop=True) -> None:
        self.path = path
        self.loop = loop
        self.audio_enabled = audio_enabled
        self.framedrop = framedrop
        self.finished = False

        self._lib = _load_vnef_library()
        _bind_vnef_api(self._lib)

        self._info = _VNEVideoInfo()
        cdef bytes encoded_path = str(path).encode("utf-8")
        self._handle = self._lib.vne_video_open(encoded_path, ctypes.byref(self._info))
        
        if not self._handle:
            self._handle = None
            raise VideoBackendUnavailable(f"vnef open failed: {path}")

        self._clock_start_ms = None
        self._last_surface = None
        self._video_queue = []
        self._audio_packets = []
        self._decode_stalled = False
        self._eof_reached = False
        self.decoded_video_frames = 0
        self.decoded_audio_packets = 0
        self.dropped_video_frames = 0
        self.dropped_audio_packets = 0
        self.max_video_queue_depth = 0
        self.last_lag_ms = 0
        self.max_lag_ms = 0

    def _reset_loop_state(self) -> None:
        self._clock_start_ms = None
        self._video_queue.clear()
        self._audio_packets.clear()
        self._decode_stalled = False
        self._eof_reached = False

    def _last_error(self) -> str:
        try:
            raw = self._lib.vne_video_last_error(self._handle)
        except Exception:
            return ""
        if not raw:
            return ""
        try:
            return raw.decode("utf-8", errors="replace")
        except Exception:
            return str(raw)

    def _maybe_set_clock(self, int now_ms, int pts_ms) -> None:
        if self._clock_start_ms is None:
            self._clock_start_ms = now_ms - max(0, pts_ms)

    def _decode_until_video(self, int now_ms, int packet_budget=512) -> bool:
        cdef bint produced_video = False
        cdef int packets_left = max(1, packet_budget)
        cdef int frame_type
        cdef int pts_ms
        cdef int sample_rate, channels, bytes_per_sample, sample_count, frame_bytes
        cdef object surface
        cdef bytes pcm
        cdef int overflow
        
        video_frame = _VNEVideoFrame()
        audio_frame = _VNEAudioFrame()

        while packets_left > 0:
            packets_left -= 1
            frame_type = int(self._lib.vne_video_next(
                self._handle, 
                ctypes.byref(video_frame), 
                ctypes.byref(audio_frame)
            ))

            if frame_type == _VNE_FRAME_VIDEO:
                pts_ms = int(video_frame.pts_ms)
                try:
                    surface = _frame_to_surface(video_frame)
                finally:
                    self._lib.vne_video_free_video_frame(ctypes.byref(video_frame))
                
                if surface is None:
                    continue
                
                pts_ms = max(0, pts_ms)
                self._maybe_set_clock(now_ms, pts_ms)
                self._video_queue.append((surface, pts_ms))
                self.decoded_video_frames += 1
                
                if len(self._video_queue) > self.max_video_queue_depth:
                    self.max_video_queue_depth = len(self._video_queue)
                
                produced_video = True
                self._decode_stalled = False
                return True

            if frame_type == _VNE_FRAME_AUDIO:
                try:
                    if self.audio_enabled:
                        pts_ms = max(0, int(audio_frame.pts_ms))
                        sample_rate = int(audio_frame.sample_rate)
                        channels = int(audio_frame.channels)
                        bytes_per_sample = int(audio_frame.bytes_per_sample)
                        sample_count = max(0, int(audio_frame.nb_samples))
                        frame_bytes = sample_count * max(1, channels) * max(1, bytes_per_sample)
                        
                        if frame_bytes > 0 and audio_frame.data:
                            pcm = ctypes.string_at(audio_frame.data, frame_bytes)
                            self._maybe_set_clock(now_ms, pts_ms)
                            self._audio_packets.append((pts_ms, sample_rate, channels, bytes_per_sample, pcm))
                            self.decoded_audio_packets += 1
                            
                            if len(self._audio_packets) > _MAX_AUDIO_PACKET_BACKLOG:
                                overflow = len(self._audio_packets) - _MAX_AUDIO_PACKET_BACKLOG
                                if overflow > 0:
                                    del self._audio_packets[:overflow]
                                    self.dropped_audio_packets += overflow
                finally:
                    self._lib.vne_video_free_audio_frame(ctypes.byref(audio_frame))
                continue

            if frame_type == _VNE_FRAME_EOF:
                if self.loop and self._lib.vne_video_seek_ms(self._handle, ctypes.c_int64(0)) == 0:
                    self._reset_loop_state()
                    continue
                self._eof_reached = True
                self._decode_stalled = False
                return produced_video

            if frame_type == _VNE_FRAME_NONE:
                self._decode_stalled = True
                return produced_video

            if frame_type == _VNE_FRAME_ERROR:
                msg = self._last_error() or "unknown decode error"
                raise RuntimeError(f"vnef decode error: {msg}")

            raise RuntimeError(f"vnef decode returned unknown frame type: {frame_type}")

        return produced_video

    def set_framedrop(self, bint enabled) -> None:
        self.framedrop = enabled

    def update(self, int now_ms) -> tuple[pygame.Surface | None, bool]:
        if self.finished:
            return self._last_surface, True

        cdef int decode_attempts = 0
        cdef int target_queue_frames = 8
        
        while len(self._video_queue) < target_queue_frames and not self._eof_reached and decode_attempts < 8:
            decode_attempts += 1
            if not self._decode_until_video(now_ms, packet_budget=512):
                break

        if not self._video_queue:
            if self._eof_reached:
                self.finished = True
            return self._last_surface, self.finished

        cdef int clock_start = self._clock_start_ms if self._clock_start_ms is not None else now_ms
        cdef int next_pts, next_due_ms

        if self.framedrop:
            while len(self._video_queue) > 1:
                next_pts = self._video_queue[1][1]
                next_due_ms = clock_start + next_pts
                if now_ms >= next_due_ms:
                    self._video_queue.pop(0)
                    self.dropped_video_frames += 1
                else:
                    break

        frame_surface, frame_pts = self._video_queue[0]
        cdef int due_ms = clock_start + frame_pts
        cdef int lag_ms = now_ms - due_ms
        
        self.last_lag_ms = lag_ms
        if lag_ms > self.max_lag_ms:
            self.max_lag_ms = lag_ms
            
        if now_ms < due_ms:
            return self._last_surface, self.finished

        self._last_surface = frame_surface
        self._video_queue.pop(0)
        
        if self._eof_reached and not self._video_queue:
            self.finished = True
            
        return self._last_surface, self.finished

    def drain_audio_packets(self) -> list[tuple[int, int, int, int, bytes]]:
        if not self._audio_packets:
            return []
        packets = self._audio_packets
        self._audio_packets = []
        return packets

    def stats(self) -> dict[str, int | bool]:
        return {
            "decoded_video_frames": int(self.decoded_video_frames),
            "decoded_audio_packets": int(self.decoded_audio_packets),
            "dropped_video_frames": int(self.dropped_video_frames),
            "dropped_audio_packets": int(self.dropped_audio_packets),
            "video_queue_depth": int(len(self._video_queue)),
            "audio_packet_backlog": int(len(self._audio_packets)),
            "max_video_queue_depth": int(self.max_video_queue_depth),
            "lag_ms": int(self.last_lag_ms),
            "max_lag_ms": int(self.max_lag_ms),
            "decode_stalled": bool(self._decode_stalled),
            "eof_reached": bool(self._eof_reached),
            "framedrop": bool(self.framedrop),
        }

    def close(self) -> None:
        handle = self._handle
        self._handle = None
        if handle is not None:
            self._lib.vne_video_close(handle)
        self._reset_loop_state()
        self.finished = True

    def __dealloc__(self):
        try:
            self.close()
        except Exception:
            pass
