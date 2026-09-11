from __future__ import annotations

import configparser
from typing import TYPE_CHECKING, Final

from ... import Command
from ...batoceraPaths import BIOS, CONFIGS, SAVES, mkdir_if_not_exists
from ...controller import generate_sdl_game_controller_config
from ..Generator import Generator

if TYPE_CHECKING:
    from collections.abc import Mapping

    from ...controller import ControllerMapping
    from ...Emulator import Emulator
    from ...types import DeviceInfoMapping, GunMapping, HotkeysContext, Resolution

# DSperate resolves its config directory as $XDG_CONFIG_HOME/dsperate, so
# pointing XDG_CONFIG_HOME at the configs root puts the global file and the
# per-game overrides where every other emulator keeps them.
_CONFIG_ROOT: Final = CONFIGS
_CONFIG_DIR: Final = CONFIGS / 'dsperate'
_CONFIG_FILE: Final = _CONFIG_DIR / 'dsperate.ini'
_SAVES: Final = SAVES / 'nds' / 'dsperate'

# The pad hotkeys are chorded off a modifier, and these handhelds have no
# mode/home button, so Select stands in for it: DSperate withholds a modifier
# that doubles as a DS button while it is held and delivers it as a tap when
# it is released alone, which keeps Select usable in game.
_PAD_HOTKEYS: Final = {
    'modifier':     'back',
    'quit':         'mod+start',
    'fast_forward': 'mod++righttrigger',
    'save_state':   'mod+rightshoulder',
    'load_state':   'mod+leftshoulder',
    'slot_next':    'mod+dpright',
    'slot_prev':    'mod+dpleft',
    'layout_next':  'mod+dpup',
    'lid':          'mod+dpdown',
    'mic':          'leftstick',
    # volume and screenshots are knulli-wide hotkeys, not the emulator's
    'volume_up':    'none',
    'volume_down':  'none',
    'screenshot':   'none',
    'pause':        'none',
}


class DsperateGenerator(Generator):

    def getHotkeysContext(self) -> HotkeysContext:
        # Escape is the frontend's quit key and it writes the battery save on
        # the way out, the same as a launcher's SIGTERM.
        return {
            'name': 'dsperate',
            'keys': { 'exit': 'KEY_ESC' }
        }

    def getInGameRatio(self, config, gameResolution, rom):
        # Both DS screens, stacked or side by side.
        return 4/3 if config.get('dsperate_layout') == 'horizontal' else 2/3

    def generate(
        self,
        system: Emulator,
        rom: str,
        playersControllers: ControllerMapping,
        metadata: Mapping[str, str],
        guns: GunMapping,
        wheels: DeviceInfoMapping,
        gameResolution: Resolution,
    ) -> Command.Command:
        mkdir_if_not_exists(_CONFIG_DIR)
        mkdir_if_not_exists(_CONFIG_DIR / 'games')
        mkdir_if_not_exists(_SAVES)
        mkdir_if_not_exists(_SAVES / 'states')

        # Read what is there so anything hand-edited outside the keys below
        # survives.  DSperate's own default file has every key commented out.
        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str
        if _CONFIG_FILE.exists():
            config.read(_CONFIG_FILE)

        for section in ('paths', 'video', 'audio', 'emu', 'padhotkeys'):
            if not config.has_section(section):
                config.add_section(section)

        config.set('paths', 'bios9',    str(BIOS / 'bios9.bin'))
        config.set('paths', 'bios7',    str(BIOS / 'bios7.bin'))
        config.set('paths', 'firmware', str(BIOS / 'firmware.bin'))
        config.set('paths', 'saves',    str(_SAVES))
        config.set('paths', 'states',   str(_SAVES / 'states'))

        config.set('video', 'fullscreen', 'true')
        config.set('video', 'layout', system.config.get('dsperate_layout', 'vertical'))
        config.set('video', 'dual_window', _bool(system, 'dsperate_dual_window', False))
        config.set('video', 'linear', _bool(system, 'dsperate_linear', False))
        # The software renderer is the default on purpose: on a four core board
        # the GL driver's own threads cost more than the scale they save.
        config.set('video', 'accel', _bool(system, 'dsperate_accel', False))

        config.set('audio', 'mic', _bool(system, 'dsperate_mic', True))

        config.set('emu', 'jit', _bool(system, 'dsperate_jit', True))
        config.set('emu', 'quantum', system.config.get('dsperate_quantum', '0'))
        config.set('emu', 'idle_skip', system.config.get('dsperate_idle_skip', '1'))
        config.set('emu', 'ff_speed', system.config.get('dsperate_ff_speed', '0'))

        for key, value in _PAD_HOTKEYS.items():
            config.set('padhotkeys', key, value)

        with _CONFIG_FILE.open('w') as f:
            config.write(f)

        return Command.Command(
            array=['/usr/bin/dsperate-sdl', rom],
            env={
                'XDG_CONFIG_HOME': str(_CONFIG_ROOT),
                'SDL_GAMECONTROLLERCONFIG': generate_sdl_game_controller_config(playersControllers),
            })


def _bool(system: Emulator, key: str, default: bool) -> str:
    value = system.getOptBoolean(key) if system.isOptSet(key) else default
    return 'true' if value else 'false'
