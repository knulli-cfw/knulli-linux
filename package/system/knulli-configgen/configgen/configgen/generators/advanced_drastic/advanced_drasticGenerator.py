from __future__ import annotations

import filecmp
import os
import shutil
from os import environ
import subprocess
from typing import TYPE_CHECKING

from ... import Command
from ...batoceraPaths import CONFIGS
from ...controller import generate_sdl_game_controller_config
from ..Generator import Generator

if TYPE_CHECKING:
    from pathlib import Path

    from ...types import HotkeysContext

class Advanced_DrasticGenerator(Generator):

    def getHotkeysContext(self) -> HotkeysContext:
        return {
            "name": "drastic",
            "keys": { "exit": "KEY_ESC" }
        }

    def generate(self, system, rom, playersControllers, metadata, guns, wheels, gameResolution):

        advanced_drastic_root = "/userdata/system/configs/advanced_drastic"
        advanced_drastic_bin = "/userdata/system/configs/advanced_drastic/launch.sh"
        advanced_drastic_conf = "/userdata/system/configs/advanced_drastic/config/drastic.cfg"
        advanced_drastic_settings = "/userdata/system/configs/advanced_drastic/resources/settings.json"
        advanced_drastic_saves = "/userdata/saves/nds/advanced_drastic/saves"
        advanced_drastic_states = "/userdata/saves/nds/advanced_drastic/states"

        board = open("/boot/boot/knulli.board").read().strip()

        board_installed = ""
        board_file = f"{advanced_drastic_root}/knulli.board"
        if os.path.isfile(board_file):
            board_installed = open(board_file).read().strip()

        board_changed = (board != board_installed)

        # Reinstall/refresh default config if missing or board changed
        if (not os.path.exists(advanced_drastic_root)) or board_changed:
            os.makedirs(advanced_drastic_root, exist_ok=True)
            os.system(f"cp -rv /usr/share/advanced_drastic/* {advanced_drastic_root}")
            os.system(f"cp /boot/boot/knulli.board {advanced_drastic_root}")

        advanced_drastic_config_dir = f"{advanced_drastic_root}/config"
        advanced_drastic_resources_dir = f"{advanced_drastic_root}/resources"
        os.makedirs(advanced_drastic_config_dir, exist_ok=True)
        os.makedirs(advanced_drastic_resources_dir, exist_ok=True)

        config_missing = not os.path.isfile(advanced_drastic_conf)
        settings_missing = not os.path.isfile(advanced_drastic_settings)

        if board_changed or config_missing:
            # Restore if config missing
            if config_missing:
                os.system(f"cp -rv /usr/share/advanced_drastic/config/* {advanced_drastic_config_dir}/")

            # board config
            board_config_src = f"/usr/share/advanced_drastic/devices/{board}/config"
            if os.path.isdir(board_config_src):
                os.system(f"cp -rv {board_config_src}/* {advanced_drastic_config_dir}/")

        if board_changed or settings_missing:
            #Restore if settings missing
            if settings_missing:
                os.system(f"cp -rv /usr/share/advanced_drastic/resources/settings.json {advanced_drastic_resources_dir}/settings.json")

            # board config
            board_settings_src = f"/usr/share/advanced_drastic/devices/{board}/resources"
            if os.path.isdir(board_settings_src):
                os.system(f"cp -rv {board_settings_src}/settings.json {advanced_drastic_resources_dir}/settings.json")

        # Bind mount saves and states locations
        saves_target = os.path.join(advanced_drastic_root, "backup")
        states_target = os.path.join(advanced_drastic_root, "savestates")

        os.makedirs(saves_target, exist_ok=True)
        os.makedirs(states_target, exist_ok=True)
        os.makedirs(advanced_drastic_saves, exist_ok=True)
        os.makedirs(advanced_drastic_states, exist_ok=True)

        # Moves original files before binding
        def move_data(src_dir, dst_dir):
            if os.path.exists(src_dir):
                for filename in os.listdir(src_dir):
                    shutil.move(os.path.join(src_dir, filename), os.path.join(dst_dir, filename))

        # Check if already mounted
        def is_mounted(mount_point: str) -> bool:
            path = os.path.realpath(mount_point)
            with open("/proc/self/mountinfo", "r") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) >= 5 and os.path.realpath(parts[4]) == path:
                        return True
            return False

        # Set bind mounts for exfat. No symlinks
        if not is_mounted(saves_target):
            move_data(saves_target, advanced_drastic_saves)
            subprocess.call(["mount", "--bind", advanced_drastic_saves, saves_target])

        if not is_mounted(states_target):
            move_data(states_target, advanced_drastic_states)
            subprocess.call(["mount", "--bind", advanced_drastic_states, states_target])


        # User Settings
        settings_to_update = {}

        if system.isOptSet("adv_drastic_hires") and system.getOptBoolean('adv_drastic_hires') == True:
            settings_to_update["hires_3d"] = "1"
        else:
            settings_to_update["hires_3d"] = "0"

        if system.isOptSet("adv_drastic_threaded") and system.getOptBoolean('adv_drastic_threaded') == True:
            settings_to_update["threaded_3d"] = "1"
        else:
            settings_to_update["threaded_3d"] = "0"

        if system.isOptSet("adv_drastic_frameskip_type") and system.getOptBoolean('adv_drastic_frameskip_type') == True:
            settings_to_update["frameskip_type"] = "1"
        else:
            settings_to_update["frameskip_type"] = "0"

        if system.isOptSet("adv_drastic_frameskip_value"):
            settings_to_update["frameskip_value"] = str(system.config["adv_drastic_frameskip_value"])

        # Only apply if there are changes detected
        if settings_to_update:
            configureSettings(settings_to_update, advanced_drastic_conf)

        # JSON Settings
        json_settings_to_update = {}

        if system.isOptSet("adv_drastic_pip"):
            json_settings_to_update["position"] = int(system.config["adv_drastic_pip"])
        else:
            json_settings_to_update["position"] = 1

        if system.isOptSet("adv_drastic_blur") and system.getOptBoolean('adv_drastic_blur') == True:
            json_settings_to_update["pixel_filter"] = 0
        else:
            json_settings_to_update["pixel_filter"] = 1

        # Only apply if there are changes detected
        if json_settings_to_update:
            configureJsonSettings(json_settings_to_update, advanced_drastic_settings)

        os.chdir(advanced_drastic_root)
        commandArray = [advanced_drastic_bin, rom]
        return Command.Command(
            array=commandArray,
            env={
                'DISPLAY': '0.0',
                'LIB_FB': '3',
                'SDL_GAMECONTROLLERCONFIG': generate_sdl_game_controller_config(playersControllers)
            })

def configureSettings(settings_to_update: dict, config_path: str):
    if not os.path.isfile(config_path):
        return

    with open(config_path, "r") as file:
        lines = file.readlines()

    with open(config_path, "w") as file:
        for line in lines:
            stripped = line.strip()
            if "=" in stripped:
                key, value = map(str.strip, stripped.split("=", 1))
                if key in settings_to_update:
                    new_value = settings_to_update[key]
                    if value != new_value:
                        file.write(f"{key} = {new_value}\n")
                    else:
                        file.write(line)
                else:
                    file.write(line)
            else:
                file.write(line)

def configureJsonSettings(settings_to_update: dict, json_path: str):
    if not os.path.isfile(json_path):
        return

    with open(json_path, "r", encoding="utf-8") as file:
        lines = file.readlines()

    with open(json_path, "w", encoding="utf-8") as file:
        for line in lines:
            stripped = line.strip()

            if ":" in stripped and stripped.startswith('"'):
                key_part, value_part = stripped.split(":", 1)
                key = key_part.strip().strip('"')

                if key in settings_to_update:
                    new_value = settings_to_update[key]

                    has_comma = value_part.strip().endswith(",")

                    if isinstance(new_value, bool):
                        literal = "true" if new_value else "false"
                    elif isinstance(new_value, (int, float)):
                        literal = str(new_value)
                    else:
                        literal = f'"{new_value}"'

                    comma = "," if has_comma else ""
                    file.write(f'  "{key}":{literal}{comma}\n')
                else:
                    file.write(line)
            else:
                file.write(line)
