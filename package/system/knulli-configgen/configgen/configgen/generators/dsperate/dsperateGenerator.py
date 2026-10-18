from __future__ import annotations

import configparser
from typing import TYPE_CHECKING, Final

from ... import Command
from ...batoceraPaths import BIOS, CONFIGS, SAVES, SCREENSHOTS, mkdir_if_not_exists
from ...controller import _DEFAULT_SDL_MAPPING, generate_sdl_game_controller_config
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

# Boards with two panels: one window per DS screen by default.  SDL's KMSDRM
# backend only registers the panel EmulationStation runs on (drmConn), unless
# SDL_KMSDRM_ALL_DISPLAYS is set.
_DUAL_SCREEN_BOARDS: Final = ('rg-ds', 'rg-ds-plus')

# DS_DUAL_SCREENS per board: each panel's SDL display and its touch devices.
# Our SDL hands evdev touches window 1 (the upper one), so a touch panel has
# to be routed explicitly.
_DUAL_SCREENS: Final = {
    # both RG DS panels are "goodix-ts": by SDL touch index, upper probes first
    'rg-ds': 'upper=1:#0,lower=0:#1',
    'rg-ds-plus': 'upper=1,lower=0:goodix',
}


def _board() -> str:
    try:
        with open('/boot/boot/knulli.board') as f:
            return f.read().strip()
    except OSError:
        return ''

# Knulli's hotkey layout, as RetroArch has it, in SDL's names: SDL names the
# face buttons by Xbox position, so knulli's Y (west) is 'x', X (north) is 'y'
# and B (south) is 'a'.  The DS-only actions take the slots RetroArch spends on
# rewind, shaders and the AI service, which have no DS counterpart.
_PAD_HOTKEYS: Final = {
    'quit':                'mod+start',
    'pause':               'mod+a',
    'save_state':          'mod+x',
    'load_state':          'mod+y',
    'slot_next':           'mod+dpup',
    'slot_prev':           'mod+dpdown',
    'fast_forward':        'mod+dpright',
    'fast_forward_toggle': 'none',
    'screenshot':          'mod+leftshoulder',
    'screen_swap':         'mod+rightshoulder',
    'layout_prev':         'mod++lefttrigger',
    'layout_next':         'mod++righttrigger',
    'lid':                 'mod+b',
    'mic':                 'leftstick',
    # the volume keys are the system's
    'volume_up':           'none',
    'volume_down':         'none',
    'mute':                'none',
    'pip_corner_next':     'none',
    'fps':                 'none',
}


def _pad_modifier(playersControllers: ControllerMapping) -> str:
    """The SDL name of player 1's hotkey button.

    generate_sdl_game_controller_config maps hotkey to 'guide' only when no
    other input shares its button; where it doubles as one (Select, on the pads
    with no function button) the modifier has to be that button's name instead.
    DSperate withholds a modifier that is also a DS button while it is held and
    delivers it as a tap when released alone.
    """
    controller = next((c for c in playersControllers.values() if c.player_number == 1), None)
    hotkey = controller.inputs.get('hotkey') if controller else None
    if hotkey is None or hotkey.type != 'button':
        return 'guide'
    for name, input in controller.inputs.items():
        if name != 'hotkey' and input.type == 'button' and input.id == hotkey.id and name in _DEFAULT_SDL_MAPPING:
            return _DEFAULT_SDL_MAPPING[name]
    return 'guide'


class DsperateGenerator(Generator):

    def getHotkeysContext(self) -> HotkeysContext:
        # Escape is the frontend's quit key and it writes the battery save on
        # the way out, the same as a launcher's SIGTERM.
        return {
            'name': 'dsperate',
            'keys': { 'exit': 'KEY_ESC' }
        }

    def getInGameRatio(self, config, gameResolution, rom):
        # One DS screen is 4:3; stacked is 2:3, side by side 8:3, and the
        # single, pip and dominant layouts fill a 4:3 frame.
        layout = config.get('dsperate_layout', 'vertical')
        if layout == 'vertical':
            return 2/3
        if layout == 'horizontal':
            return 8/3
        return 4/3

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
        config.set('paths', 'screenshots', str(SCREENSHOTS))

        config.set('video', 'fullscreen', 'true')
        config.set('video', 'layout', system.config.get('dsperate_layout', 'vertical'))
        dual_window = _bool(system, 'dsperate_dual_window', _board() in _DUAL_SCREEN_BOARDS)
        config.set('video', 'dual_window', dual_window)
        config.set('video', 'linear', _bool(system, 'dsperate_linear', False))
        # video.accel is gone upstream: the GPU renderer is only a fallback now.
        config.remove_option('video', 'accel')

        config.set('audio', 'mic', _bool(system, 'dsperate_mic', True))

        config.set('emu', 'jit', _bool(system, 'dsperate_jit', True))
        config.set('emu', 'quantum', system.config.get('dsperate_quantum', '0'))
        config.set('emu', 'idle_skip', system.config.get('dsperate_idle_skip', '1'))
        config.set('emu', 'ff_speed', system.config.get('dsperate_ff_speed', '0'))

        modifier = _pad_modifier(playersControllers)
        config.set('padhotkeys', 'modifier', modifier)
        for key, value in _PAD_HOTKEYS.items():
            # A modifier of Start would leave quit unreachable.
            if value == f'mod+{modifier}':
                value = 'mod+back'
            config.set('padhotkeys', key, value)

        with _CONFIG_FILE.open('w') as f:
            config.write(f)

        env = {
            'XDG_CONFIG_HOME': str(_CONFIG_ROOT),
            'SDL_GAMECONTROLLERCONFIG': generate_sdl_game_controller_config(playersControllers),
        }
        if dual_window == 'true':
            env['SDL_KMSDRM_ALL_DISPLAYS'] = '1'
            screens = _DUAL_SCREENS.get(_board())
            if screens:
                env['DS_DUAL_SCREENS'] = screens

        return Command.Command(array=['/usr/bin/dsperate', rom], env=env)


def _bool(system: Emulator, key: str, default: bool) -> str:
    value = system.getOptBoolean(key) if system.isOptSet(key) else default
    return 'true' if value else 'false'
