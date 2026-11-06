from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING, Final

from ... import Command
from ...batoceraPaths import CONFIGS, SAVES, SCREENSHOTS, ensure_parents_and_open, mkdir_if_not_exists
from ...controller import generate_sdl_game_controller_config
from ...utils.configparser import CaseSensitiveConfigParser
from ..Generator import Generator

if TYPE_CHECKING:
    from ...types import HotkeysContext

# own config dir: the stock mupen64plus.cfg names plugins pow2 ignores
_CONFIG_DIR: Final = CONFIGS / 'mupen64plus-pow2'
_CONFIG_FILE: Final = _CONFIG_DIR / 'mupen64plus.cfg'
# suxty keeps its own ini next to the configdir: <configdir>/suxty/suxty.cfg
_SUXTY_FILE: Final = _CONFIG_DIR / 'suxty' / 'suxty.cfg'
_DATA_DIR: Final = Path('/usr/share/mupen64plus-pow2')
_SAVES: Final = SAVES / 'n64'


class Mupen64plusPow2Generator(Generator):

    def getHotkeysContext(self) -> HotkeysContext:
        return {
            "name": "mupen64plus-pow2",
            "keys": { "exit": "KEY_ESC" }
        }

    def generate(self, system, rom, playersControllers, metadata, guns, wheels, gameResolution):
        mkdir_if_not_exists(_SAVES)

        ini = CaseSensitiveConfigParser(interpolation=None)
        ini.read(_CONFIG_FILE)

        for section in ("Core", "Video-General"):
            if not ini.has_section(section):
                ini.add_section(section)
        ini.set("Core", "Version", "1.01")
        ini.set("Core", "ScreenshotPath", str(SCREENSHOTS))
        ini.set("Core", "SaveStatePath", str(_SAVES))
        ini.set("Core", "SaveSRAMPath", str(_SAVES))
        ini.set("Core", "SharedDataPath", str(_DATA_DIR))
        ini.set("Core", "SaveFilenameFormat", "1000")

        # rotated panels report portrait
        width, height = gameResolution["width"], gameResolution["height"]
        if width < height:
            width, height = height, width
        ini.set("Video-General", "Version", "1")
        ini.set("Video-General", "ScreenWidth", str(width))
        ini.set("Video-General", "ScreenHeight", str(height))
        ini.set("Video-General", "Fullscreen", "True")

        with ensure_parents_and_open(_CONFIG_FILE, 'w') as f:
            ini.write(f)

        # knulli conventions: the in-game menu opens with hotkey+B and quits
        # with hotkey+START. suxty ships with select+start menu / hotkey+b
        # quit, so seed the knulli combos; user tweaks made from suxty's menu
        # (which writes to the same file) are never overwritten.
        sx = CaseSensitiveConfigParser(interpolation=None)
        sx.read(_SUXTY_FILE)
        for section, options in (("menu", {"menu_combo": "hotkey+b"}),
                                 ("hotkeys", {"hotkey_button": "guide", "quit": "hotkey+start"})):
            if not sx.has_section(section):
                sx.add_section(section)
            for key, value in options.items():
                if not sx.has_option(section, key):
                    sx.set(section, key, value)
        with ensure_parents_and_open(_SUXTY_FILE, 'w') as f:
            sx.write(f)

        commandArray: list[str | Path] = ['/usr/bin/mupen64plus-pow2', '--configdir', _CONFIG_DIR, '--datadir', _DATA_DIR]
        if system.isOptSet('state_filename'):
            commandArray.extend(['--savestate', system.config['state_filename']])
        commandArray.append(rom)

        # suxty, the bundled input plugin, binds pads through SDL2 game
        # controller mappings; knulli's SDL2 build drops SDL's internal mapping
        # database, so without this the pad falls back to a generic button-order
        # guess and the controls come out wrong. suxty maps the N64 buttons
        # one-to-one onto the SDL names, and knulli's logical button names
        # already carry this pad's A/B swap, so the swap built into the default
        # SDL mapping would undo itself here: use the direct mapping so N64 A/B
        # land on the buttons the front end calls A/B.
        env = {"SDL_GAMECONTROLLERCONFIG": generate_sdl_game_controller_config(playersControllers, xbox_layout=True)}

        return Command.Command(array=commandArray, env=env)

    def getInGameRatio(self, config, gameResolution, rom):
        return 4/3
