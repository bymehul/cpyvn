# cython: language_level=3
# cython: wraparound=False
# cython: boundscheck=False

from typing import List, Optional, Tuple

cdef class Label:
    cdef readonly str name

    def __init__(self, str name):
        self.name = name

    def __repr__(self):
        return f"Label(name={self.name!r})"


cdef class Say:
    cdef readonly object speaker
    cdef readonly str text

    def __init__(self, object speaker, str text):
        self.speaker = speaker
        self.text = text

    def __repr__(self):
        return f"Say(speaker={self.speaker!r}, text={self.text!r})"


cdef class Scene:
    cdef readonly str kind
    cdef readonly str value
    cdef readonly object fade
    cdef readonly object transition_style
    cdef readonly object transition_seconds
    cdef readonly object float_amp
    cdef readonly object float_speed

    def __init__(self, str kind, str value, 
                 object fade=None, 
                 object transition_style=None, 
                 object transition_seconds=None, 
                 object float_amp=None, 
                 object float_speed=None):
        self.kind = kind
        self.value = value
        self.fade = fade
        self.transition_style = transition_style
        self.transition_seconds = transition_seconds
        self.float_amp = float_amp
        self.float_speed = float_speed

    def __repr__(self):
        return f"Scene(kind={self.kind!r}, value={self.value!r})"


cdef class Show:
    cdef readonly str kind
    cdef readonly str name
    cdef readonly str value
    cdef readonly object size
    cdef readonly object pos
    cdef readonly object anchor
    cdef readonly int z
    cdef readonly object fade
    cdef readonly object transition_style
    cdef readonly object transition_seconds
    cdef readonly object float_amp
    cdef readonly object float_speed

    def __init__(self, str kind, str name, str value,
                 object size=None, object pos=None, object anchor=None, int z=0,
                 object fade=None, object transition_style=None, 
                 object transition_seconds=None, object float_amp=None, 
                 object float_speed=None):
        self.kind = kind
        self.name = name
        self.value = value
        self.size = size
        self.pos = pos
        self.anchor = anchor
        self.z = z
        self.fade = fade
        self.transition_style = transition_style
        self.transition_seconds = transition_seconds
        self.float_amp = float_amp
        self.float_speed = float_speed

    def __repr__(self):
        return f"Show(name={self.name!r}, value={self.value!r}, z={self.z})"


cdef class Hide:
    cdef readonly str name
    cdef readonly object fade
    cdef readonly object transition_style
    cdef readonly object transition_seconds

    def __init__(self, str name, object fade=None, object transition_style=None, object transition_seconds=None):
        self.name = name
        self.fade = fade
        self.transition_style = transition_style
        self.transition_seconds = transition_seconds

    def __repr__(self):
        return f"Hide(name={self.name!r})"


cdef class Animate:
    cdef readonly str name
    cdef readonly str action
    cdef readonly object v1
    cdef readonly object v2
    cdef readonly double seconds
    cdef readonly str ease

    def __init__(self, str name, str action, object v1=None, object v2=None, double seconds=0.0, str ease="linear"):
        self.name = name
        self.action = action
        self.v1 = v1
        self.v2 = v2
        self.seconds = seconds
        self.ease = ease

    def __repr__(self):
        return f"Animate(name={self.name!r}, action={self.action!r})"

cdef class Music:
    cdef readonly str path
    cdef readonly bint loop

    def __init__(self, str path, bint loop=True):
        self.path = path
        self.loop = loop

    def __repr__(self):
        return f"Music(path={self.path!r}, loop={self.loop})"


cdef class Sound:
    cdef readonly str path

    def __init__(self, str path):
        self.path = path

    def __repr__(self):
        return f"Sound(path={self.path!r})"


cdef class Echo:
    cdef readonly object path
    cdef readonly str action

    def __init__(self, object path, str action="start"):
        self.path = path
        self.action = action

    def __repr__(self):
        return f"Echo(action={self.action!r})"


cdef class Voice:
    cdef readonly object character
    cdef readonly str path

    def __init__(self, object character, str path):
        self.character = character
        self.path = path

    def __repr__(self):
        return f"Voice(character={self.character!r}, path={self.path!r})"


cdef class Video:
    cdef readonly str action
    cdef readonly object path
    cdef readonly bint loop
    cdef readonly str fit

    def __init__(self, str action, object path=None, bint loop=False, str fit="contain"):
        self.action = action
        self.path = path
        self.loop = loop
        self.fit = fit

    def __repr__(self):
        return f"Video(action={self.action!r}, path={self.path!r})"

cdef class CharacterDef:
    cdef readonly str ident
    cdef readonly object display_name
    cdef readonly object color
    cdef readonly dict sprites
    cdef readonly object voice_tag
    cdef readonly object pos
    cdef readonly object anchor
    cdef readonly int z
    cdef readonly object float_amp
    cdef readonly object float_speed

    def __init__(self, str ident, object display_name=None, object color=None, 
                 dict sprites=None, object voice_tag=None, object pos=None, 
                 object anchor=None, int z=0, object float_amp=None, object float_speed=None):
        self.ident = ident
        self.display_name = display_name
        self.color = color
        self.sprites = sprites
        self.voice_tag = voice_tag
        self.pos = pos
        self.anchor = anchor
        self.z = z
        self.float_amp = float_amp
        self.float_speed = float_speed

    def __repr__(self):
        return f"CharacterDef(ident={self.ident!r}, name={self.display_name!r})"


cdef class ShowChar:
    cdef readonly str ident
    cdef readonly object expression
    cdef readonly object pos
    cdef readonly object anchor
    cdef readonly object z
    cdef readonly object fade
    cdef readonly object transition_style
    cdef readonly object transition_seconds
    cdef readonly object float_amp
    cdef readonly object float_speed

    def __init__(self, str ident, object expression=None, object pos=None, 
                 object anchor=None, object z=None, object fade=None, 
                 object transition_style=None, object transition_seconds=None, 
                 object float_amp=None, object float_speed=None):
        self.ident = ident
        self.expression = expression
        self.pos = pos
        self.anchor = anchor
        self.z = z
        self.fade = fade
        self.transition_style = transition_style
        self.transition_seconds = transition_seconds
        self.float_amp = float_amp
        self.float_speed = float_speed

    def __repr__(self):
        return f"ShowChar(ident={self.ident!r}, expression={self.expression!r})"

cdef class HotspotAdd:
    cdef readonly str name
    cdef readonly int x, y, w, h
    cdef readonly str target

    def __init__(self, str name, int x, int y, int w, int h, str target):
        self.name = name
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.target = target

    def __repr__(self):
        return f"HotspotAdd(name={self.name!r}, target={self.target!r})"


cdef class HotspotRemove:
    cdef readonly object name

    def __init__(self, object name=None):
        self.name = name

    def __repr__(self):
        return f"HotspotRemove(name={self.name!r})"


cdef class HotspotDebug:
    cdef readonly bint enabled

    def __init__(self, bint enabled):
        self.enabled = enabled

    def __repr__(self):
        return f"HotspotDebug(enabled={self.enabled})"


cdef class HotspotPoly:
    cdef readonly str name
    cdef readonly list points
    cdef readonly str target

    def __init__(self, str name, list points, str target):
        self.name = name
        self.points = points
        self.target = target

    def __repr__(self):
        return f"HotspotPoly(name={self.name!r})"


cdef class HudAdd:
    cdef readonly str name
    cdef readonly str style
    cdef readonly object text
    cdef readonly object icon
    cdef readonly int x, y, w, h
    cdef readonly str target

    def __init__(self, str name, str style, object text, object icon,
                 int x, int y, int w, int h, str target):
        self.name = name
        self.style = style
        self.text = text
        self.icon = icon
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.target = target

    def __repr__(self):
        return f"HudAdd(name={self.name!r}, style={self.style!r}, target={self.target!r})"


cdef class HudRemove:
    cdef readonly object name

    def __init__(self, object name=None):
        self.name = name

    def __repr__(self):
        return f"HudRemove(name={self.name!r})"


cdef class CameraSet:
    cdef readonly double pan_x
    cdef readonly double pan_y
    cdef readonly double zoom

    def __init__(self, double pan_x, double pan_y, double zoom):
        self.pan_x = pan_x
        self.pan_y = pan_y
        self.zoom = zoom

    def __repr__(self):
        return f"CameraSet(x={self.pan_x}, y={self.pan_y}, zoom={self.zoom})"

cdef class Mute:
    cdef readonly str target

    def __init__(self, str target="all"):
        self.target = target
        
    def __repr__(self):
        return f"Mute(target={self.target!r})"


cdef class Preload:
    cdef readonly str kind
    cdef readonly str path

    def __init__(self, str kind, str path):
        self.kind = kind
        self.path = path

    def __repr__(self):
        return f"Preload({self.kind}={self.path!r})"


cdef class CacheClear:
    cdef readonly str kind
    cdef readonly object path

    def __init__(self, str kind, object path=None):
        self.kind = kind
        self.path = path

    def __repr__(self):
        return f"CacheClear(kind={self.kind!r})"


cdef class CachePin:
    cdef readonly str kind
    cdef readonly str path

    def __init__(self, str kind, str path):
        self.kind = kind
        self.path = path

    def __repr__(self):
        return f"CachePin({self.kind}={self.path!r})"


cdef class CacheUnpin:
    cdef readonly str kind
    cdef readonly str path

    def __init__(self, str kind, str path):
        self.kind = kind
        self.path = path

    def __repr__(self):
        return f"CacheUnpin({self.kind}={self.path!r})"


cdef class Loading:
    cdef readonly str action
    cdef readonly object text

    def __init__(self, str action, object text=None):
        self.action = action
        self.text = text

    def __repr__(self):
        return f"Loading(action={self.action!r})"


cdef class GarbageCollect:
    def __repr__(self):
        return "GarbageCollect()"


cdef class Wait:
    cdef readonly double seconds

    def __init__(self, double seconds):
        self.seconds = seconds

    def __repr__(self):
        return f"Wait({self.seconds})"


cdef class WaitVoice:
    def __repr__(self):
        return "WaitVoice()"


cdef class WaitVideo:
    def __repr__(self):
        return "WaitVideo()"


cdef class Notify:
    cdef readonly str text
    cdef readonly object seconds

    def __init__(self, str text, object seconds=None):
        self.text = text
        self.seconds = seconds

    def __repr__(self):
        return f"Notify(text={self.text!r})"


cdef class Blend:
    cdef readonly str style
    cdef readonly double seconds

    def __init__(self, str style, double seconds):
        self.style = style
        self.seconds = seconds

    def __repr__(self):
        return f"Blend(style={self.style!r}, seconds={self.seconds})"


cdef class Jump:
    cdef readonly str target

    def __init__(self, str target):
        self.target = target

    def __repr__(self):
        return f"Jump(target={self.target!r})"


cdef class Save:
    cdef readonly str slot

    def __init__(self, str slot):
        self.slot = slot

    def __repr__(self):
        return f"Save(slot={self.slot!r})"


cdef class Load:
    cdef readonly str slot

    def __init__(self, str slot):
        self.slot = slot

    def __repr__(self):
        return f"Load(slot={self.slot!r})"


cdef class Call:
    cdef readonly str path
    cdef readonly str label

    def __init__(self, str path, str label):
        self.path = path
        self.label = label

    def __repr__(self):
        return f"Call(path={self.path!r}, label={self.label!r})"


cdef class SetVar:
    cdef readonly str name
    cdef readonly object value

    def __init__(self, str name, object value):
        self.name = name
        self.value = value

    def __repr__(self):
        return f"SetVar({self.name!r}={self.value!r})"


cdef class AddVar:
    cdef readonly str name
    cdef readonly int amount

    def __init__(self, str name, int amount):
        self.name = name
        self.amount = amount

    def __repr__(self):
        return f"AddVar({self.name!r}+={self.amount})"


cdef class IfJump:
    cdef readonly str name
    cdef readonly str op
    cdef readonly object value
    cdef readonly str target

    def __init__(self, str name, str op, object value, str target):
        self.name = name
        self.op = op
        self.value = value
        self.target = target

    def __repr__(self):
        return f"IfJump({self.name!r} {self.op} {self.value!r} -> {self.target!r})"


cdef class Choice:
    cdef readonly list options
    cdef readonly object prompt
    cdef readonly object timeout
    cdef readonly object timeout_default

    def __init__(self, list options, object prompt=None, object timeout=None, object timeout_default=None):
        self.options = options
        self.prompt = prompt
        self.timeout = timeout
        self.timeout_default = timeout_default

    def __repr__(self):
        return f"Choice(options={len(self.options)}, timeout={self.timeout}, default={self.timeout_default})"


cdef class Input:
    cdef readonly str variable
    cdef readonly str prompt
    cdef readonly object default_value

    def __init__(self, str variable, str prompt, object default_value=None):
        self.variable = variable
        self.prompt = prompt
        self.default_value = default_value

    def __repr__(self):
        return f"Input({self.variable!r}, {self.prompt!r})"


cdef class Phone:
    cdef readonly str action
    cdef readonly str contact
    cdef readonly str side
    cdef readonly str text

    def __init__(self, str action, str contact=None, str side=None, str text=None):
        self.action = action
        self.contact = contact
        self.side = side
        self.text = text

    def __repr__(self):
        return f"Phone({self.action!r})"


cdef class Meter:
    cdef readonly str action
    cdef readonly str variable
    cdef readonly str label
    cdef readonly object min_val
    cdef readonly object max_val
    cdef readonly str color

    def __init__(self, str action, str variable=None, str label=None,
                 object min_val=None, object max_val=None, str color=None):
        self.action = action
        self.variable = variable
        self.label = label
        self.min_val = min_val
        self.max_val = max_val
        self.color = color

    def __repr__(self):
        return f"Meter({self.action!r}, {self.variable!r})"


cdef class Item:
    cdef readonly str action
    cdef readonly str item_id
    cdef readonly str name
    cdef readonly str description
    cdef readonly str icon
    cdef readonly int amount

    def __init__(self, str action, str item_id=None, str name=None, str description=None, str icon=None, int amount=1):
        self.action = action
        self.item_id = item_id
        self.name = name
        self.description = description
        self.icon = icon
        self.amount = amount

    def __repr__(self):
        return f"Item({self.action!r}, {self.item_id!r})"


cdef class Map:
    cdef readonly str action
    cdef readonly str value    # image path for show
    cdef readonly str label    # display label for poi
    cdef readonly object pos   # (x, y) for poi (deprecated)
    cdef readonly object points # list of (x, y) for poly poi
    cdef readonly str target   # target label for poi

    def __init__(self, str action, str value=None, str label=None, object pos=None, object points=None, str target=None):
        self.action = action
        self.value = value
        self.label = label
        self.pos = pos
        self.points = points
        self.target = target

    def __repr__(self):
        return f"Map({self.action!r}, {self.value or self.label!r})"


Command = (
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
    Meter,
    Music,
    Mute,
    Notify,
    Phone,
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
