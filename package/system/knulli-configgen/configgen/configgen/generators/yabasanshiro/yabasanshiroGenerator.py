from __future__ import annotations

import logging
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import TYPE_CHECKING, Final, Dict, Any

from ... import Command
from ...batoceraPaths import BIOS, HOME, SAVES, ES_SETTINGS, ensure_parents_and_open
from ...controller import generate_sdl_game_controller_config
from ..Generator import Generator

if TYPE_CHECKING:
    from ...types import HotkeysContext
    from ...controller import ControllerMapping

eslog = logging.getLogger(__name__)

ES_INPUT_SRC: Final = Path("/usr/share/emulationstation/es_input.cfg")
YABA_ROOT: Final = HOME / ".yabasanshiro"
YABA_ES_INPUT: Final = YABA_ROOT / "es_temporaryinput.cfg"
YABA_KEYMAP:   Final = YABA_ROOT / "keymapv2.json"
YABA_SAVES: Final = SAVES / "saturn" / "yabasanshiro-sa"
YABA_BIOS: Final = BIOS / "saturn_bios.bin"

UNBOUND = {"id": -1, "type": "", "value": -999}
HAT_VAL = {"up": 1, "right": 2, "down": 4, "left": 8}

ES_TO_YABA = {
    "a": "b",
    "b": "a",
    "x": "y",
    "y": "x",
    "pageup": "z",
    "pagedown": "c",
    "l2": "l",
    "r2": "r",
    "start": "start",
    "select": "select",
    "up": "up",
    "down": "down",
    "left": "left",
    "right": "right",
    "joystick1left": "analogx",
    "joystick1up": "analogy",
}


# Temp fix for rk3566
def ensure_libmali_symlink() -> bool:
    libdir = Path("/usr/lib")
    link = libdir / "libmali.so.0"

    def _target_exists(p: Path) -> bool:
        try:
            p.resolve(strict=True)
            return True
        except Exception:
            return False

    # If it exists and isn't a symlink, leave it alone.
    if link.exists() and not link.is_symlink():
        return True

    # If it is a symlink, ensure target exists.
    if link.is_symlink():
        if _target_exists(link):
            return True
        # remove broken link if needed so we can recreate
        try:
            link.unlink()
        except Exception as e:
            eslog.warning("libmali: failed to remove broken symlink %s: %s", link, e)
            return False

    # Prefer "libMali.so*" then "libmali.so*".
    candidates: list[Path] = []

    for pattern in ("libMali.so*", "libmali.so*"):
        for p in libdir.glob(pattern):
            # we want a real file.
            if p.name == link.name:
                continue
            try:
                if p.is_file() and not p.is_symlink():
                    candidates.append(p)
            except Exception:
                continue

    if not candidates:
        eslog.warning("libmali: no Mali library candidates found in %s", libdir)
        return False

    # Prefer the latest version
    candidates.sort(key=lambda p: p.name)
    target = candidates[-1]

    try:
        link.symlink_to(target)
        eslog.info("libmali: created symlink %s -> %s", link, target)
    except Exception as e:
        eslog.warning("libmali: failed to create symlink %s -> %s: %s", link, target, e)
        return False

    return _target_exists(link)

def generateESInput(playersControllers: "ControllerMapping", swap_ab: bool = False) -> bool:
    c = playersControllers.get(1)
    if c is None:
        eslog.warning("yaba-es-input: no P1 controller; not writing %s", YABA_ES_INPUT)
        return False

    guid = (c.guid or "").strip()
    name = (c.name or "").strip() or "Unknown Controller"

    out_root = ET.Element("inputList")
    out_ic = ET.SubElement(out_root, "inputConfig", attrib={
        "type": "joystick",
        "deviceName": name,
        "deviceGUID": guid,
    })

    by_name = {inp.name: inp for inp in c.inputs.values() if inp.name is not None}

    def emit(nm: str, inp_obj) -> None:
        attrib = {
            "name": nm,
            "type": str(inp_obj.type),
            "id": str(inp_obj.id),
            "value": str(inp_obj.value),
        }
        code = getattr(inp_obj, "code", None)
        if code is not None:
            attrib["code"] = str(code)
        ET.SubElement(out_ic, "input", attrib=attrib)

    try:
        # DPAD
        emit("up", by_name["up"])
        emit("down", by_name["down"])
        emit("left", by_name["left"])
        emit("right", by_name["right"])

        # A/B mapping for menu
        a_obj = by_name["a"]
        b_obj = by_name["b"]
        if not swap_ab:
            emit("a", b_obj)
            emit("b", a_obj)
        else:
            emit("a", a_obj)
            emit("b", b_obj)

        # select = hotkey
        emit("select", by_name["hotkey"])

        xml_bytes = ET.tostring(out_root, encoding="utf-8", xml_declaration=True)
        with ensure_parents_and_open(YABA_ES_INPUT, "wb") as f:
            f.write(xml_bytes)

        return True

    except KeyError as e:
        # If something is unexpectedly missing, log once and fail.
        eslog.warning("yaba-es-input: missing required input %s; not writing %s", e, YABA_ES_INPUT)
        return False
    except Exception as e:
        eslog.warning("yaba-es-input: failed to write %s: %s", YABA_ES_INPUT, e)
        return False

def generateYabaKeymap(playersControllers: ControllerMapping):
    store = {}

    for player_index in (1, 2):
        if player_index not in playersControllers:
            continue

        controller = playersControllers[player_index]
        name = controller.name
        guid = controller.guid
        device_id = controller.index
        dev_key = f"{device_id}_{name}_{guid}"

        actions = ["a","b","c","x","y","z","l","r","start","select",
                "up","down","left","right","analogx","analogy","analogleft","analogright"]
        block = {k: dict(UNBOUND) for k in actions}

        for idx in controller.inputs:
            inp = controller.inputs[idx]
            src = inp.name
            if src not in ES_TO_YABA:
                continue
            action = ES_TO_YABA[src]

            if inp.type == "button":
                block[action] = {"id": int(inp.id), "type": "button", "value": 1}

            elif inp.type == "hat" and action in ("up","down","left","right"):
                block[action] = {"id": int(inp.id), "type": "hat", "value": HAT_VAL[action]}

            elif inp.type == "axis":
                v = -1 if int(inp.value) < 0 else (1 if int(inp.value) > 0 else 0)

                if src == "joystick1left":
                    block["analogx"] = {"id": int(inp.id), "type": "axis", "value": v}

                elif src == "joystick1up":
                    block["analogy"] = {"id": int(inp.id), "type": "axis", "value": v}
                else:
                    block[action] = {"id": int(inp.id), "type": "axis", "value": v}

        if block["analogx"]["id"] == -1:
            block["analogx"] = {"id": 0, "type": "axis", "value": 0}
        if block["analogy"]["id"] == -1:
            block["analogy"] = {"id": 1, "type": "axis", "value": 0}

        store[dev_key] = block
        store[f"player{player_index}"] = {
            "DeviceID": device_id,
            "deviceGUID": guid,
            "deviceName": name,
            "padmode": 0
        }

    with ensure_parents_and_open(YABA_KEYMAP, "w") as f:
        json.dump(store, f, indent=2, ensure_ascii=False)
    return YABA_KEYMAP

def generateConfig(system, rom: str) -> Path:
    rom_path = Path(rom)
    cfg_path = YABA_ROOT / (rom_path.name + ".config")

    cfg: dict[str, object] = {}

    if system.isOptSet('yaba_res'):
        cfg["Resolution"] = int(system.config.get('yaba_res'))
    else:
        cfg["Resolution"] = 3

    if system.isOptSet('yaba_ratio'):
        cfg["Aspect rate"] = int(system.config.get('yaba_res'))
    else:
        cfg["Aspect rate"] = 1


    if system.isOptSet('yaba_rotate') and system.config['yaba_rotate'] == '1':
        cfg["Rotate screen"] = True
    else:
        cfg["Rotate screen"] = False

    if system.isOptSet('yaba_rotate_res'):
        cfg["Rotate screen resolution"] = int(system.config.get('yaba_rotate_res'))
    else:
        cfg["Rotate screen resolution"] = 0


    if system.isOptSet('yaba_compute_shader') and system.config['yaba_compute_shader'] == '1':
        cfg["Use compute shader"] = True
    else:
        cfg["Use compute shader"] = False

    with ensure_parents_and_open(cfg_path, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

    return cfg_path

class YabasanshiroGenerator(Generator):

    def supportsExternalBezels(self) -> bool:
        return False

    def getHotkeysContext(self) -> HotkeysContext:
        return {
            "name": "yabasanshiro",
            "keys": { "exit": ["KEY_LEFTALT", "KEY_F4"] }
        }
    # Return value for es invertedbuttons
    def getInvertButtonsValue(self) -> bool:
        try:
            tree = ET.parse(ES_SETTINGS)
            root = tree.getroot()
            # Find the InvertButtons element and return value
            elem = root.find(".//bool[@name='InvertButtons']")
            if elem is not None:
                return elem.get('value') == 'true'
            return False  # Return False if not found
        except:
            return False # when file is not yet here or malformed

    def generate(self, system, rom, playersControllers, metadata, guns, wheels, gameResolution):
        # temp fix for rk3566
        ensure_libmali_symlink()

        YABA_SAVES.mkdir(parents=True, exist_ok=True)

        generateESInput(playersControllers, swap_ab=self.getInvertButtonsValue())
        generateYabaKeymap(playersControllers)
        generateConfig(system, rom)

        commandArray = ["yabasanshiro", "-i", rom]

        if not (system.isOptSet('yaba_bios_hle') and system.config['yaba_bios_hle'] == '1'):
            if YABA_BIOS.exists():
                commandArray[1:1] = ["-b", str(YABA_BIOS)]

        return Command.Command(array=commandArray,env={
            "SDL_GAMECONTROLLERCONFIG": generate_sdl_game_controller_config(playersControllers)
        })
