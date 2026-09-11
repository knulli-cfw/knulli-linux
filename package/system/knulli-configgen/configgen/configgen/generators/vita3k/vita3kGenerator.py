from __future__ import annotations

import re
import shutil
import subprocess
from typing import TYPE_CHECKING

import ruamel.yaml
import ruamel.yaml.util

from ... import Command
from ...batoceraPaths import CACHE, CONFIGS, SAVES, mkdir_if_not_exists
from ...controller import generate_sdl_game_controller_config
from ..Generator import Generator

if TYPE_CHECKING:
    from ...types import HotkeysContext

vitaConfig = CONFIGS / 'vita3k'
vitaSaves = SAVES / 'psvita'
vitaConfigFile = vitaConfig / 'config.yml'

# SDL3 enumerates evdev buttons with code >= BTN_JOYSTICK (288) first (ascending),
# then code < BTN_JOYSTICK (ascending). SDL2 enumerates all buttons 0..KEY_MAX.
# When a device has buttons below BTN_JOYSTICK (e.g. KEY_F4=68, KEY_VOLUMEDOWN=114),
# SDL3 pushes those to higher indices while SDL2 assigns them the lowest indices.
_BTN_JOYSTICK = 288

def _generate_sdl_config_for_sdl3(controllers) -> str:
    """
    Generate SDL_GAMECONTROLLERCONFIG with button IDs corrected for SDL3's
    enumeration order. Vita3k bundles SDL3 which numbers buttons differently
    from SDL2 when the device has evdev button codes below BTN_JOYSTICK (288).
    """
    sdl2_config = generate_sdl_game_controller_config(controllers)
    lines = sdl2_config.split('\n')
    fixed_lines = []

    for line, ctrl in zip(lines, controllers.values()):
        # Collect (evdev_code, sdl2_button_id) for all button inputs
        buttons = []
        for inp in ctrl.inputs.values():
            if inp.type == 'button' and inp.code is not None:
                try:
                    buttons.append((int(inp.code), int(inp.id)))
                except ValueError:
                    pass

        # If all buttons are above BTN_JOYSTICK, SDL2 and SDL3 order is identical
        if not buttons or all(code >= _BTN_JOYSTICK for code, _ in buttons):
            fixed_lines.append(line)
            continue

        # Build SDL2 -> SDL3 index map
        sdl2_order = sorted(buttons, key=lambda x: x[0])  # ascending by code = SDL2 order
        high = [(c, i) for c, i in sdl2_order if c >= _BTN_JOYSTICK]
        low  = [(c, i) for c, i in sdl2_order if c <  _BTN_JOYSTICK]
        id_map = {sdl2_idx: sdl3_idx for sdl3_idx, (_, sdl2_idx) in enumerate(high + low)}

        def remap_button(m):
            return f'b{id_map.get(int(m.group(1)), int(m.group(1)))}'

        fixed_lines.append(re.sub(r'\bb(\d+)', remap_button, line))

    # Preserve any trailing lines beyond the controller count
    fixed_lines.extend(lines[len(fixed_lines):])
    return '\n'.join(fixed_lines)


class Vita3kGenerator(Generator):


    def getHotkeysContext(self) -> HotkeysContext:
        return {
            "name": "vita3k",
            "keys": { "exit": ["KEY_LEFTALT", "KEY_F4"], "menu": "KEY_ENTER", "pause": "KEY_ENTER" }
        }

    def generate(self, system, rom, playersControllers, metadata, guns, wheels, gameResolution):

        # Create save folder
        mkdir_if_not_exists(vitaSaves)
        
        # Create config folder
        mkdir_if_not_exists(vitaConfig)


        # Move saves if necessary
        if (vitaConfig / 'ux0').is_dir():
            # Move all folders from vitaConfig to vitaSaves except "data", "lang", and "shaders-builtin"
            for item in vitaConfig.iterdir():
                if item.name not in ['data', 'lang', 'shaders-builtin']:
                    if item.is_dir():
                        shutil.move(item, vitaSaves)

        # Create the config.yml file if it doesn't exist
        vita3kymlconfig = {}
        if vitaConfigFile.is_file():
            with vitaConfigFile.open('r') as stream:
                vita3kymlconfig, indent, block_seq_indent = ruamel.yaml.util.load_yaml_guess_indent(stream)
        
        if not vitaConfigFile.exists():
            vitaConfigFile.touch()

        if vita3kymlconfig is None:
            vita3kymlconfig = {}

        # ensure the correct path is set
        vita3kymlconfig["pref-path"] = f"{vitaSaves!s}"

        # Set the renderer
        if system.isOptSet("vita3k_gfxbackend"):
            vita3kymlconfig["backend-renderer"] = system.config["vita3k_gfxbackend"]
        else:
            have_vulkan = subprocess.check_output(["/usr/bin/knulli-vulkan", "hasVulkan"], text=True).strip()
            if have_vulkan == "true":
                eslog.debug("Vulkan driver is available on the system.")
                vita3kymlconfig["backend-renderer"] = "Vulkan"
            else:
                vita3kymlconfig["backend-renderer"] = "OpenGL"
        # Set the resolution multiplier
        if system.isOptSet("vita3k_resolution"):
            vita3kymlconfig["resolution-multiplier"] = int(system.config["vita3k_resolution"])
        else:
            vita3kymlconfig["resolution-multiplier"] = 1
        # Set FXAA
        if system.isOptSet("vita3k_fxaa") and system.getOptBoolean("vita3k_fxaa") == True:
            vita3kymlconfig["enable-fxaa"] = "true"
        else:
            vita3kymlconfig["enable-fxaa"] = "false"
        # Set VSync
        if system.isOptSet("vita3k_vsync") and system.getOptBoolean("vita3k_vsync") == False:
            vita3kymlconfig["v-sync"] = "false"
        else:
            vita3kymlconfig["v-sync"] = "true"
        # Set the anisotropic filtering
        if system.isOptSet("vita3k_anisotropic"):
            vita3kymlconfig["anisotropic-filtering"] = int(system.config["vita3k_anisotropic"])
        else:
            vita3kymlconfig["anisotropic-filtering"] = 1
        # Set the linear filtering option
        if system.isOptSet("vita3k_linear") and system.getOptBoolean("vita3k_linear") == True:
            vita3kymlconfig["enable-linear-filter"] = "true"
        else:
            vita3kymlconfig["enable-linear-filter"] = "false"
        # Screen filter
        if system.isOptSet("vita3k_filter"):
            vita3kymlconfig["screen-filter"] = system.config["vita3k_filter"]
        else:
            vita3kymlconfig["screen-filter"] = "Bilinear"
        # Compile pipelines in the background rather than stalling on them
        if system.isOptSet("vita3k_sync"):
            vita3kymlconfig["async-pipeline-compilation"] = system.getOptBoolean("vita3k_sync")
        else:
            vita3kymlconfig["async-pipeline-compilation"] = True
        # Pixel perfect scaling in HD fullscreen
        if system.isOptSet("vita3k_hd_pixel"):
            vita3kymlconfig["fullscreen_hd_res_pixel_perfect"] = system.getOptBoolean("vita3k_hd_pixel")
        else:
            vita3kymlconfig["fullscreen_hd_res_pixel_perfect"] = False
        # Accurate but slower rendering
        if system.isOptSet("vita3k_accuracy"):
            vita3kymlconfig["high-accuracy"] = system.getOptBoolean("vita3k_accuracy")
        else:
            vita3kymlconfig["high-accuracy"] = False
        # Caches, worth keeping on: they cost storage and save a lot of stutter
        if system.isOptSet("vita3k_texture"):
            vita3kymlconfig["texture-cache"] = system.getOptBoolean("vita3k_texture")
        else:
            vita3kymlconfig["texture-cache"] = True
        if system.isOptSet("vita3k_shader"):
            vita3kymlconfig["shader-cache"] = system.getOptBoolean("vita3k_shader")
        else:
            vita3kymlconfig["shader-cache"] = True
        # Memory mapping strategy
        if system.isOptSet("vita3k_mapping"):
            vita3kymlconfig["memory-mapping"] = system.config["vita3k_mapping"]
        else:
            vita3kymlconfig["memory-mapping"] = "double-buffer"
        # Emulated system language
        if system.isOptSet("vita3k_system_language"):
            vita3kymlconfig["sys-lang"] = int(system.config["vita3k_system_language"])
        else:
            vita3kymlconfig["sys-lang"] = 1
        # Surface Sync
        if system.isOptSet("vita3k_surface") and system.getOptBoolean("vita3k_surface") == False:
            vita3kymlconfig["disable-surface-sync"] = "false"
        else:
            vita3kymlconfig["disable-surface-sync"] = "true"

        # Vita3k is fussy over its yml file
        # We try to match it as close as possible, but the 'vectors' cause yml formatting issues
        yaml = ruamel.yaml.YAML()
        yaml.explicit_start = True
        yaml.explicit_end = True
        yaml.indent(mapping=indent, sequence=indent, offset=block_seq_indent)

        with vitaConfigFile.open('w') as fp:
            yaml.dump(vita3kymlconfig, fp)

        # Simplify the rom name (strip the directory & extension)
        begin, end = rom.find('['), rom.rfind(']')
        smplromname = rom[begin+1: end]
        # because of the yml formatting, we don't allow Vita3k to modify it
        # using the -w & -f options prevents Vita3k from re-writing & prompting the user in GUI
        # we want to avoid that so roms load straight away
        if (vitaSaves / 'ux0' / 'app' / smplromname).is_dir():
            commandArray = ["/usr/bin/vita3k/Vita3K", "-F", "-w", "-f", "-c", vitaConfigFile, "-r", smplromname]
        else:
            # Game not installed yet, let's open the menu
            commandArray = ["/usr/bin/vita3k/Vita3K", "-F", "-w", "-f", "-c", vitaConfigFile, rom]

        return Command.Command(
            array=commandArray,
            env={
#                "SDL_GAMECONTROLLERCONFIG": generate_sdl_game_controller_config(playersControllers),
                "SDL_GAMECONTROLLERCONFIG": _generate_sdl_config_for_sdl3(playersControllers),
                "SDL_JOYSTICK_HIDAPI": "0",
                "XDG_CONFIG_HOME": CONFIGS,
                "XDG_DATA_HOME": SAVES,
                "XDG_CACHE_HOME": CACHE
            }
        )

    # Show mouse for touchscreen actions
    def getMouseMode(self, config, rom):
        if "vita3k_show_pointer" in config and config["vita3k_show_pointer"] == "0":
             return False
        else:
             return True

    def getInGameRatio(self, config, gameResolution, rom):
        return 16/9
