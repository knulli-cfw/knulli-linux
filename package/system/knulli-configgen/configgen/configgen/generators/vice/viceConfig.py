from __future__ import annotations

from typing import TYPE_CHECKING, Final

from ...batoceraPaths import mkdir_if_not_exists
from ...utils.configparser import CaseSensitiveRawConfigParser

if TYPE_CHECKING:
    from collections.abc import Mapping
    from pathlib import Path

    from ...Emulator import Emulator
    from ...types import GunMapping


_SYSTEM_CORE_MAP: Final = {
    'x64': 'C64',
    'x64dtv': 'C64DTV',
    'xplus4': 'PLUS4',
    'xscpu64': 'SCPU64',
    'xvic': 'VIC20',
    'xpet': 'PET',
}

# Each machine names its video resources after the chip it emulates, so a
# setting written as VIC* only reaches the VIC20 and is dropped everywhere else.
_CORE_CHIP_MAP: Final = {
    'C64':    ['VICII'],
    'C64DTV': ['VICII'],
    'PLUS4':  ['TED'],
    'SCPU64': ['VICII'],
    'VIC20':  ['VIC'],
    'PET':    ['Crtc'],
    'C128':   ['VICII', 'VDC'],
}


def setViceConfig(vice_config_dir: Path, system: Emulator, metadata: Mapping[str, str], guns: GunMapping, rom: str) -> None:

    # Path
    viceController = vice_config_dir / "sdl-joymap.vjm"
    viceConfigRC   = vice_config_dir / "sdl-vicerc"

    mkdir_if_not_exists(viceConfigRC.parent)

    # config file
    viceConfig = CaseSensitiveRawConfigParser(interpolation=None)

    if viceConfigRC.exists():
        viceConfig.read(viceConfigRC)

    systemCore = _SYSTEM_CORE_MAP.get(system.config['core'], 'C128')

    if not viceConfig.has_section(systemCore):
        viceConfig.add_section(systemCore)

    viceConfig.set(systemCore, "SaveResourcesOnExit",    "0")
    viceConfig.set(systemCore, "SoundDeviceName",        "alsa")

    if system.isOptSet('noborder') and system.getOptBoolean('noborder') == True:
        aspect_mode = "0"
        border_mode = "3"
    else:
        aspect_mode = "2"
        border_mode = "0"

    for chip in _CORE_CHIP_MAP.get(systemCore, ['VICII']):
        viceConfig.set(systemCore, f"{chip}Fullscreen",     "1")
        viceConfig.set(systemCore, f"{chip}FullscreenMode", "0")  # 0 = desktop resolution
        viceConfig.set(systemCore, f"{chip}AspectMode",     aspect_mode)
        # only the VIC-II, VIC-I and TED have a border to hide
        if chip in ['VICII', 'VIC', 'TED']:
            viceConfig.set(systemCore, f"{chip}BorderMode", border_mode)

    if system.isOptSet('use_guns') and system.getOptBoolean('use_guns') and len(guns) >= 1:
        if "gun_type" in metadata and metadata["gun_type"] == "stack_light_rifle":
            viceConfig.set(systemCore, "JoyPort1Device",             "15")
        else:
            viceConfig.set(systemCore, "JoyPort1Device",             "14")
    else:
        viceConfig.set(systemCore, "JoyPort1Device",             "1")
    viceConfig.set(systemCore, "JoyDevice1",             "4")
    if not systemCore == "VIC20":
        viceConfig.set(systemCore, "JoyDevice2",             "4")
    viceConfig.set(systemCore, "JoyMapFile",  str(viceController))

    # custom : allow the user to configure directly sdl-vicerc via batocera.conf via lines like : vice.section.option=value
    for user_config in system.config:
        if user_config[:5] == "vice.":
            section_option = user_config[5:]
            section_option_splitter = section_option.find(".")
            custom_section = section_option[:section_option_splitter]
            custom_option = section_option[section_option_splitter+1:]
            if not viceConfig.has_section(custom_section):
                viceConfig.add_section(custom_section)
            viceConfig.set(custom_section, custom_option, system.config[user_config])

    # update the configuration file
    with viceConfigRC.open('w') as configfile:
        viceConfig.write(EqualsSpaceRemover(configfile))

class EqualsSpaceRemover:
    output_file = None
    def __init__( self, new_output_file ):
        self.output_file = new_output_file

    def write( self, what ):
        self.output_file.write( what.replace( " = ", "=", 1 ) )
