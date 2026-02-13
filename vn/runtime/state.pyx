# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False

import pygame

cdef class BackgroundState:
    cdef public str kind
    cdef public str value
    cdef public object float_amp
    cdef public object float_speed

    def __init__(self, str kind, str value, object float_amp=None, object float_speed=None):
        self.kind = kind
        self.value = value
        self.float_amp = float_amp
        self.float_speed = float_speed

    def __repr__(self):
        return f"BackgroundState(kind={self.kind}, value={self.value})"


cdef class SpriteState:
    cdef public str kind
    cdef public str value
    cdef public object size
    cdef public object pos
    cdef public object anchor
    cdef public int z
    cdef public object float_amp
    cdef public object float_speed
    cdef public double float_phase
    cdef public int alpha

    cdef public object fade_start_ms
    cdef public int fade_duration_ms
    cdef public int fade_from
    cdef public int fade_to
    cdef public bint fade_remove

    cdef public object transition_style
    cdef public object transition_start_ms
    cdef public int transition_duration_ms
    cdef public str transition_mode
    cdef public bint transition_remove
    cdef public int transition_seed

    def __init__(self, 
                 str kind, 
                 str value, 
                 object size, 
                 object pos, 
                 object anchor, 
                 int z, 
                 object float_amp=None, 
                 object float_speed=None, 
                 double float_phase=0.0, 
                 int alpha=255, 
                 object fade_start_ms=None, 
                 int fade_duration_ms=0, 
                 int fade_from=255, 
                 int fade_to=255, 
                 bint fade_remove=False, 
                 object transition_style=None, 
                 object transition_start_ms=None, 
                 int transition_duration_ms=0, 
                 str transition_mode="in", 
                 bint transition_remove=False, 
                 int transition_seed=0):
        
        self.kind = kind
        self.value = value
        self.size = size
        self.pos = pos
        self.anchor = anchor
        self.z = z
        self.float_amp = float_amp
        self.float_speed = float_speed
        self.float_phase = float_phase
        self.alpha = alpha
        
        self.fade_start_ms = fade_start_ms
        self.fade_duration_ms = fade_duration_ms
        self.fade_from = fade_from
        self.fade_to = fade_to
        self.fade_remove = fade_remove
        
        self.transition_style = transition_style
        self.transition_start_ms = transition_start_ms
        self.transition_duration_ms = transition_duration_ms
        self.transition_mode = transition_mode
        self.transition_remove = transition_remove
        self.transition_seed = transition_seed

    def __repr__(self):
        return f"SpriteState(kind={self.kind}, value={self.value}, z={self.z})"


cdef class SpriteInstance:
    cdef public SpriteState state
    cdef public object surface
    cdef public object rect
    cdef public object source_surface

    def __init__(self, SpriteState state, object surface, object rect, object source_surface=None):
        self.state = state
        self.surface = surface
        self.rect = rect
        self.source_surface = source_surface


cdef class HotspotArea:
    cdef public str name
    cdef public list points
    cdef public str target

    def __init__(self, str name, list points, str target):
        self.name = name
        self.points = points
        self.target = target


cdef class HudButton:
    cdef public str name
    cdef public str style
    cdef public object text
    cdef public object icon_path
    cdef public object icon_surface
    cdef public object rect
    cdef public str target

    def __init__(self, str name, str style, object text, object icon_path,
                 object icon_surface, object rect, str target):
        self.name = name
        self.style = style
        self.text = text
        self.icon_path = icon_path
        self.icon_surface = icon_surface
        self.rect = rect
        self.target = target


cdef class SpriteAnimation:
    cdef public str action
    cdef public double start_v1
    cdef public double start_v2
    cdef public double end_v1
    cdef public double end_v2
    cdef public int start_ms
    cdef public int duration_ms
    cdef public str ease

    def __init__(self, 
                 str action, 
                 double start_v1, 
                 double start_v2, 
                 double end_v1, 
                 double end_v2, 
                 int start_ms, 
                 int duration_ms, 
                 str ease):
        self.action = action
        self.start_v1 = start_v1
        self.start_v2 = start_v2
        self.end_v1 = end_v1
        self.end_v2 = end_v2
        self.start_ms = start_ms
        self.duration_ms = duration_ms
        self.ease = ease
