#!/usr/bin/env python3
"""Forward Linux input events to PowerVLC while direct DRM/KMS owns the VT."""

import fcntl
import glob
import ctypes
import os
import re
import select
import socket
import struct
import subprocess
import sys
import time


if len(sys.argv) not in (2, 3):
    raise SystemExit("usage: powervlc-kms3d-input.py RC_SOCKET [WINDOWED_REQUEST]")

socket_path = sys.argv[1]
windowed_request = sys.argv[2] if len(sys.argv) == 3 else None

EV_KEY, EV_REL, EV_ABS = 1, 2, 3
REL_X, REL_Y = 0, 1
ABS_X, ABS_Y, ABS_MT_X, ABS_MT_Y = 0, 1, 53, 54
BTN_LEFT, BTN_TOUCH = 272, 330
WIDTH, HEIGHT = 1920, 1080
EVENT_FMT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FMT)
ABSINFO_FMT = "iiiiii"
ABSINFO_SIZE = struct.calcsize(ABSINFO_FMT)

CTRL_KEYS = {29, 97}
SHIFT_KEYS = {42, 54}
ALT_KEYS = {56, 100}
META_KEYS = {125, 126}
MODIFIER_KEYS = CTRL_KEYS | SHIFT_KEYS | ALT_KEYS | META_KEYS

# VLC key codes are a Unicode character or one of these portable special-key
# values, ORed with modifier bits.  Transporting key codes lets VLC resolve
# every current and user-customized shortcut through its normal key map.
VLC_MOD_ALT = 0x01000000
VLC_MOD_SHIFT = 0x02000000
VLC_MOD_CTRL = 0x04000000
VLC_MOD_META = 0x08000000
VLC_SPECIAL_KEYS = {
    1: 0x1B, 14: 0x08, 15: 0x09, 28: 0x0D, 96: 0x0D,
    105: 0x00210000, 106: 0x00220000,
    103: 0x00230000, 108: 0x00240000,
    59: 0x00270000, 60: 0x00280000, 61: 0x00290000,
    62: 0x002A0000, 63: 0x002B0000, 64: 0x002C0000,
    65: 0x002D0000, 66: 0x002E0000, 67: 0x002F0000,
    68: 0x00300000, 87: 0x00310000, 88: 0x00320000,
    102: 0x00330000, 107: 0x00340000, 110: 0x00350000,
    111: 0x00360000, 139: 0x00370000, 104: 0x00390000,
    109: 0x003A0000, 99: 0x003B0000, 119: 0x003D0000,
    158: 0x003F0000, 159: 0x00400000, 173: 0x00410000,
    128: 0x00420000, 217: 0x00430000, 156: 0x00440000,
    172: 0x00450000, 113: 0x00460000, 114: 0x00470000,
    115: 0x00480000, 163: 0x00490000, 165: 0x004A0000,
    166: 0x004B0000, 164: 0x004C0000, 167: 0x004D0000,
    168: 0x004E0000, 208: 0x004F0000,
}


class XkbRuleNames(ctypes.Structure):
    _fields_ = [(name, ctypes.c_char_p) for name in
                ("rules", "model", "layout", "variant", "options")]


def desktop_xkb_names():
    values = {"model": "pc105", "layout": None,
              "variant": None, "options": None}
    try:
        output = subprocess.check_output(
            ["gsettings", "get", "org.gnome.desktop.input-sources", "sources"],
            text=True, stderr=subprocess.DEVNULL, timeout=2)
        match = re.search(r"\('xkb',\s*'([^']+)'\)", output)
        if match:
            layout, separator, variant = match.group(1).partition("+")
            values["layout"] = layout
            values["variant"] = variant if separator else None
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        with open("/etc/default/keyboard", encoding="utf-8") as stream:
            for line in stream:
                match = re.match(r"XKB(MODEL|LAYOUT|VARIANT|OPTIONS)=['\"]?([^'\"\n]*)",
                                 line.strip())
                if match and not values[match.group(1).lower()]:
                    values[match.group(1).lower()] = match.group(2) or None
    except OSError:
        pass
    for name in ("model", "layout", "variant", "options"):
        override = os.environ.get("XKB_DEFAULT_" + name.upper())
        if override:
            values[name] = override
    return values


def create_xkb_mapper():
    try:
        library = ctypes.CDLL("libxkbcommon.so.0")
        library.xkb_context_new.argtypes = [ctypes.c_int]
        library.xkb_context_new.restype = ctypes.c_void_p
        library.xkb_keymap_new_from_names.argtypes = [
            ctypes.c_void_p, ctypes.POINTER(XkbRuleNames), ctypes.c_int]
        library.xkb_keymap_new_from_names.restype = ctypes.c_void_p
        library.xkb_keymap_key_get_syms_by_level.argtypes = [
            ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32,
            ctypes.c_uint32, ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
        library.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
        library.xkb_keysym_to_utf32.argtypes = [ctypes.c_uint32]
        library.xkb_keysym_to_utf32.restype = ctypes.c_uint32
        context = library.xkb_context_new(0)
        values = desktop_xkb_names()
        encoded = {name: value.encode() if value else None
                   for name, value in values.items()}
        names = XkbRuleNames(None, encoded["model"], encoded["layout"],
                             encoded["variant"], encoded["options"])
        keymap = library.xkb_keymap_new_from_names(context,
                                                    ctypes.byref(names), 0)
        if not keymap:
            return None

        def lookup(evdev_code):
            symbols = ctypes.POINTER(ctypes.c_uint32)()
            count = library.xkb_keymap_key_get_syms_by_level(
                keymap, evdev_code + 8, 0, 0, ctypes.byref(symbols))
            if count < 1:
                return 0
            codepoint = library.xkb_keysym_to_utf32(symbols[0])
            if 0x41 <= codepoint <= 0x5A:
                codepoint += 0x20
            return codepoint

        print("XKB layout: " + (values["layout"] or "system default"),
              flush=True)
        return lookup
    except (AttributeError, OSError):
        return None


xkb_lookup = create_xkb_mapper()


def input_name(path):
    event = os.path.basename(path)
    try:
        with open(f"/sys/class/input/{event}/device/name", encoding="utf-8") as stream:
            return stream.read().strip()
    except OSError:
        return event


def capability(path, kind):
    event = os.path.basename(path)
    try:
        with open(f"/sys/class/input/{event}/device/capabilities/{kind}",
                  encoding="ascii") as stream:
            return int(stream.read().replace(" ", ""), 16)
    except (OSError, ValueError):
        return 0


def has_code(bits, code):
    return bool(bits & (1 << code))


def eviocgabs(axis):
    return (2 << 30) | (ord("E") << 8) | (ABSINFO_SIZE << 16) | (0x40 + axis)


def abs_range(fd, axis):
    buffer = bytearray(ABSINFO_SIZE)
    try:
        fcntl.ioctl(fd, eviocgabs(axis), buffer, True)
        _, minimum, maximum, _, _, _ = struct.unpack(ABSINFO_FMT, buffer)
        return (minimum, maximum) if maximum > minimum else None
    except OSError:
        return None


def classify(path, name):
    keys = capability(path, "key")
    rel = capability(path, "rel")
    absolute = capability(path, "abs")
    # Requiring ordinary typing keys excludes touchpads that merely expose
    # BTN_LEFT/BTN_TOUCH. It also accepts USB keyboards with arbitrary names.
    keyboard = has_code(keys, 57) and has_code(keys, 28) and has_code(keys, 30)
    pointer = (has_code(keys, BTN_LEFT) and
               ((has_code(rel, REL_X) and has_code(rel, REL_Y)) or
                (has_code(absolute, ABS_X) and has_code(absolute, ABS_Y))))
    if keyboard:
        return "keyboard"
    if pointer or "touchpad" in name.lower() or "mouse" in name.lower():
        return "pointer"
    return None


devices = []
for path in sorted(glob.glob("/dev/input/event*")):
    name = input_name(path)
    kind = classify(path, name)
    if kind:
        devices.append((path, name, kind))

keyboards = [device for device in devices if device[2] == "keyboard"]
pointers = [device for device in devices if device[2] == "pointer"]
# Touchpads often expose absolute and compatibility-mouse interfaces. Reading
# both duplicates movement. Prefer one full absolute touchpad interface.
pointers.sort(key=lambda item: (0 if "touchpad" in item[1].lower() else 1,
                                item[0]))
selected = keyboards + pointers[:1]

fds = []
states = {}
for path, name, kind in selected:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError as error:
        print(f"skip {path} ({name}): {error}", flush=True)
        continue
    fds.append(fd)
    states[fd] = {
        "path": path, "name": name, "kind": kind, "buffer": b"",
        "x": WIDTH // 2, "y": HEIGHT // 2, "dirty": False,
        "contact": False, "last_abs": {}, "last_send": 0.0,
        "last_click": 0.0, "last_click_x": 0, "last_click_y": 0,
        "ranges": {axis: abs_range(fd, axis)
                   for axis in (ABS_X, ABS_Y, ABS_MT_X, ABS_MT_Y)},
    }
    print(f"opened {path}: {name} ({kind})", flush=True)

if not fds:
    raise SystemExit("no readable keyboard or pointer input device")

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for _ in range(300):
    try:
        client.connect(socket_path)
        break
    except OSError:
        time.sleep(0.05)
else:
    raise SystemExit("PowerVLC navigation socket did not appear")
print(f"connected to {socket_path}", flush=True)


def send(command):
    data = command if isinstance(command, bytes) else command.encode()
    client.sendall(data)
    print(data.decode().rstrip(), flush=True)


def send_keycode(keycode):
    send(f"keycode {keycode}\n")


windowed_sent = False


def request_windowed():
    global windowed_sent
    if windowed_sent:
        return
    windowed_sent = True
    if windowed_request:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        flags |= getattr(os, "O_NOFOLLOW", 0)
        try:
            marker_fd = os.open(windowed_request, flags, 0o600)
            os.write(marker_fd, b"windowed\n")
            os.close(marker_fd)
        except FileExistsError:
            pass
    # The root supervisor closes this helper's RC connection before issuing
    # the display switch itself. This keeps one client on oldrc's single Unix
    # socket and makes the transition ordering deterministic.


pressed_modifiers = set()


def modifier_state():
    return (bool(pressed_modifiers & CTRL_KEYS),
            bool(pressed_modifiers & SHIFT_KEYS),
            bool(pressed_modifiers & ALT_KEYS),
            bool(pressed_modifiers & META_KEYS))


def modifier_mask():
    ctrl, shift, alt, meta = modifier_state()
    return ((VLC_MOD_CTRL if ctrl else 0) |
            (VLC_MOD_SHIFT if shift else 0) |
            (VLC_MOD_ALT if alt else 0) |
            (VLC_MOD_META if meta else 0))


def vlc_key_for_evdev(code):
    base = VLC_SPECIAL_KEYS.get(code, 0)
    if not base and xkb_lookup:
        base = xkb_lookup(code)
    return base | modifier_mask() if base else 0


while True:
    ready, _, _ = select.select(fds, [], [], 0.02)
    for fd in ready:
        state = states[fd]
        try:
            state["buffer"] += os.read(fd, EVENT_SIZE * 64)
        except BlockingIOError:
            continue
        while len(state["buffer"]) >= EVENT_SIZE:
            raw = state["buffer"][:EVENT_SIZE]
            state["buffer"] = state["buffer"][EVENT_SIZE:]
            _, _, event_type, code, value = struct.unpack(EVENT_FMT, raw)
            if state["kind"] == "keyboard":
                if event_type != EV_KEY:
                    continue
                if code in MODIFIER_KEYS:
                    if value:
                        pressed_modifiers.add(code)
                    else:
                        pressed_modifiers.discard(code)
                    continue
                if value not in (1, 2):
                    continue
                ctrl, shift, alt, meta = modifier_state()
                unmodified = not (ctrl or shift or alt or meta)
                if code in (1, 33) and unmodified and value == 1:
                    request_windowed()
                elif unmodified and code in (28, 96, 103, 108, 105, 106):
                    # Interactive BD-J menus need synchronous input controls;
                    # ordinary configured shortcuts still use keycode below.
                    navigation = {28: "activate", 96: "activate",
                                  103: "up", 108: "down",
                                  105: "left", 106: "right"}
                    send(f"nav {navigation[code]}\n")
                elif unmodified and code in (57, 164) and value == 1:
                    # Some BD-J titles own the input state in a way that makes
                    # the generic play/pause hotkey a no-op.
                    send("pause\n")
                else:
                    keycode = vlc_key_for_evdev(code)
                    if keycode:
                        send_keycode(keycode)
                continue

            if event_type == EV_REL:
                if code == REL_X:
                    state["x"] = max(0, min(WIDTH - 1,
                                              state["x"] + value * 4))
                    state["dirty"] = True
                elif code == REL_Y:
                    state["y"] = max(0, min(HEIGHT - 1,
                                              state["y"] + value * 4))
                    state["dirty"] = True
            elif event_type == EV_ABS:
                if code in (ABS_X, ABS_MT_X, ABS_Y, ABS_MT_Y):
                    if code in (ABS_MT_X, ABS_MT_Y) and \
                       state["ranges"][code - ABS_MT_X] is not None:
                        continue
                    previous = state["last_abs"].get(code)
                    state["last_abs"][code] = value
                    limits = state["ranges"][code]
                    if state["contact"] and previous is not None and limits:
                        extent = WIDTH if code in (ABS_X, ABS_MT_X) else HEIGHT
                        delta = round((value - previous) * extent * 1.8 /
                                      (limits[1] - limits[0]))
                        if code in (ABS_X, ABS_MT_X):
                            state["x"] = max(0, min(WIDTH - 1,
                                                      state["x"] + delta))
                        else:
                            state["y"] = max(0, min(HEIGHT - 1,
                                                      state["y"] + delta))
                        state["dirty"] = state["dirty"] or delta != 0
            elif event_type == EV_KEY and code == BTN_TOUCH:
                state["contact"] = value != 0
                state["last_abs"].clear()
            elif event_type == EV_KEY and code == BTN_LEFT and value == 1:
                now = time.monotonic()
                close = (abs(state["x"] - state["last_click_x"]) <= 48 and
                         abs(state["y"] - state["last_click_y"]) <= 48)
                # The lower quarter belongs to the fullscreen controller.
                # Repeated presses there are seek/pause commands, not a
                # request to leave fullscreen.
                if state["y"] >= HEIGHT * 3 // 4:
                    send(f"mouse-click {state['x']} {state['y']}\n")
                    state["last_click"] = 0.0
                elif now - state["last_click"] <= 0.40 and close:
                    state["last_click"] = 0.0
                    request_windowed()
                else:
                    send(f"mouse-click {state['x']} {state['y']}\n")
                    state["last_click"] = now
                    state["last_click_x"] = state["x"]
                    state["last_click_y"] = state["y"]

    now = time.monotonic()
    for state in states.values():
        if state["kind"] == "pointer" and state["dirty"] and \
           now - state["last_send"] >= 1 / 30:
            send(f"mouse {state['x']} {state['y']}\n")
            state["dirty"] = False
            state["last_send"] = now
