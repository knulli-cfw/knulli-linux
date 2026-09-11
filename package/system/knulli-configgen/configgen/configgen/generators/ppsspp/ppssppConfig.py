from __future__ import annotations

import logging
import subprocess
from typing import TYPE_CHECKING, Final

from ...batoceraPaths import ensure_parents_and_open
from ...utils.configparser import CaseSensitiveConfigParser
from .ppssppPaths import PPSSPP_PSP_SYSTEM_DIR

if TYPE_CHECKING:
    from ...Emulator import Emulator


eslog = logging.getLogger(__name__)

ppssppConfig: Final   = PPSSPP_PSP_SYSTEM_DIR / 'ppsspp.ini'
ppssppControls: Final = PPSSPP_PSP_SYSTEM_DIR / 'controls.ini'
ppssppRetroach: Final = PPSSPP_PSP_SYSTEM_DIR / 'ppsspp_retroachievements.dat'
ppssppFailedGfx: Final = PPSSPP_PSP_SYSTEM_DIR / 'FailedGraphicsBackends.txt'

def writePPSSPPConfig(system: Emulator):
    iniConfig = CaseSensitiveConfigParser(interpolation=None)
    if ppssppConfig.exists():
        try:
            with ppssppConfig.open('r', encoding='utf_8_sig') as fp:
                iniConfig.readfp(fp)
        except:
            pass

    createPPSSPPConfig(iniConfig, system)
    # Save the ini file
    with ensure_parents_and_open(ppssppConfig, 'w') as configfile:
        iniConfig.write(configfile)

def writeRetroAchievements(token: str):
    if token:
        with ensure_parents_and_open(ppssppRetroach, 'w') as retroach_file:
            retroach_file.write(token)

def createPPSSPPConfig(iniConfig, system):

    ## [GRAPHICS]
    if not iniConfig.has_section("Graphics"):
        iniConfig.add_section("Graphics")

    # Graphics Backend
    # PPSSPP records the backend it is about to try in FailedGraphicsBackends.txt and
    # only removes it after 10 rendered frames, so any early exit leaves it behind and
    # the next run silently switches backend.  We pick the backend here, so drop it.
    ppssppFailedGfx.unlink(missing_ok=True)

    have_vulkan = subprocess.run(["/usr/bin/knulli-vulkan", "hasVulkan"], text=True, capture_output=True).stdout.strip()
    # A board that asks for OpenGL means it: PPSSPP reaches the display through
    # VK_KHR_display, which cannot see a framebuffer SDL rotates for it, and
    # then finds no video mode matching the size it asked for.
    wanted = system.config['gfxbackend'] if system.isOptSet('gfxbackend') else None

    if have_vulkan == "true" and wanted in (None, "vulkan"):
        eslog.debug("Vulkan driver is available on the system.")
        iniConfig.set("Graphics", "GraphicsBackend", "3 (VULKAN)")
        iniConfig.set("Graphics", "DisabledGraphicsBackends", "")
    else:
        if have_vulkan == "true":
            eslog.debug(f"Vulkan is available but the system asks for {wanted}. Using OpenGL")
        else:
            eslog.debug("Vulkan driver is not available on the system. Falling back to OpenGL")
        iniConfig.set("Graphics", "GraphicsBackend", "0 (OPENGL)")
        # Without this PPSSPP falls back to Vulkan on its own and dies in SDL_CreateWindow
        iniConfig.set("Graphics", "DisabledGraphicsBackends", "VULKAN")

    # Display FPS
    if system.isOptSet('showFPS') and system.getOptBoolean('showFPS') == True:
        iniConfig.set("Graphics", "ShowFPSCounter", "3") # 1 for Speed%, 2 for FPS, 3 for both
    else:
        iniConfig.set("Graphics", "ShowFPSCounter", "0")

    # Frameskip
    iniConfig.set("Graphics", "FrameSkipType", "0") # Use number and not percent
    if system.isOptSet("frameskip") and not system.config["frameskip"] == "automatic":
        iniConfig.set("Graphics", "FrameSkip", str(system.config["frameskip"]))
    elif system.isOptSet('skip_buffer_effects') and system.getOptBoolean('skip_buffer_effects') == True:
        iniConfig.set("Graphics", "FrameSkip", "0")
    else:
        iniConfig.set("Graphics", "FrameSkip", "2")

    # Buffered rendering
    if system.isOptSet('skip_buffer_effects') and system.getOptBoolean('skip_buffer_effects') == True:
        iniConfig.set("Graphics", "SkipBufferEffects", "True")
        # Have to force autoframeskip off here.
        iniConfig.set("Graphics", "AutoFrameSkip", "False")
    else:
        iniConfig.set("Graphics", "SkipBufferEffects", "False")
        # Both internal resolution and auto frameskip are dependent on buffered rendering being on, only check these if the user is actually using buffered rendering.
        # Internal Resolution
        if system.isOptSet('internal_resolution'):
            iniConfig.set("Graphics", "InternalResolution", str(system.config["internal_resolution"]))
        else:
            iniConfig.set("Graphics", "InternalResolution", "1")
        # Auto frameskip
        if system.isOptSet("autoframeskip") and system.getOptBoolean("autoframeskip") == False:
            iniConfig.set("Graphics", "AutoFrameSkip", "False")
        else:
            iniConfig.set("Graphics", "AutoFrameSkip", "True")

    # VSync Interval
    if system.isOptSet('vsyncinterval') and system.getOptBoolean('vsyncinterval') == False:
        iniConfig.set("Graphics", "VSyncInterval", "False")
    else:
        iniConfig.set("Graphics", "VSyncInterval", "True")

    # Texture Scaling Level
    if system.isOptSet('texture_scaling_level'):
        iniConfig.set("Graphics", "TexScalingLevel", system.config["texture_scaling_level"])
    else:
        iniConfig.set("Graphics", "TexScalingLevel", "1")
    # Texture Scaling Type
    if system.isOptSet('texture_scaling_type'):
        iniConfig.set("Graphics", "TexScalingType", system.config["texture_scaling_type"])
    else:
        iniConfig.set("Graphics", "TexScalingType", "0")
    # Texture Deposterize
    if system.isOptSet('texture_deposterize'):
        iniConfig.set("Graphics", "TexDeposterize", system.config["texture_deposterize"])
    else:
        iniConfig.set("Graphics", "TexDeposterize", "True")

    # Anisotropic Filtering
    if system.isOptSet('anisotropic_filtering'):
        iniConfig.set("Graphics", "AnisotropyLevel", system.config["anisotropic_filtering"])
    else:
        iniConfig.set("Graphics", "AnisotropyLevel", "3")
    # Texture Filtering
    if system.isOptSet('texture_filtering'):
        iniConfig.set("Graphics", "TextureFiltering", system.config["texture_filtering"])
    else:
        iniConfig.set("Graphics", "TextureFiltering", "1")

   ## [SYSTEM PARAM]
    # Rendering tweaks, mostly performance levers on low power hardware.
    # Software skinning is the one that is worth having on by default.
    for opt, key, default in (
            ('vsync',                 "VSync",                 False),
            ('disable_culling',       "DisableRangeCulling",   False),
            ('lazy_texture_caching',  "TextureBackoffCache",   False),
            ('duplicate_frames',      "RenderDuplicateFrames", False),
            ('software_skinning',     "SoftwareSkinning",      True),
            ('hardware_tessellation', "HardwareTessellation",  False),
            ('smart_2d',              "Smart2DTexFiltering",   False),
    ):
        if system.isOptSet(opt):
            iniConfig.set("Graphics", key, str(system.getOptBoolean(opt)))
        else:
            iniConfig.set("Graphics", key, str(default))

    for opt, key, default in (
            ('skip_gpu_readbacks', "SkipGPUReadbackMode", "0"),
            ('curves_quality',     "SplineBezierQuality", "2"),
            ('buffer_graphics',    "InflightFrames",      "3"),
    ):
        if system.isOptSet(opt):
            iniConfig.set("Graphics", key, str(system.config[opt]))
        else:
            iniConfig.set("Graphics", key, default)

    if not iniConfig.has_section("SystemParam"):
        iniConfig.add_section("SystemParam")

    # Forcing Nickname to Batocera or User name
    if system.isOptSet('retroachievements') and system.getOptBoolean('retroachievements') == True and system.isOptSet('retroachievements.username') and system.config.get('retroachievements.username', "") != "":
        iniConfig.set("SystemParam", "NickName", system.config.get('retroachievements.username', ""))
    else:
        iniConfig.set("SystemParam", "NickName", "Batocera")
    # Disable Encrypt Save (permit to exchange save with different machines)
    iniConfig.set("SystemParam", "EncryptSave", "False")


    ## [GENERAL]
    if not iniConfig.has_section("General"):
        iniConfig.add_section("General")

    # Rewinding
    if system.isOptSet('rewind') and system.getOptBoolean('rewind') == True:
        iniConfig.set("General", "RewindFlipFrequency", "300") # 300 = every 5 seconds
    else:
        iniConfig.set("General", "RewindFlipFrequency",  "0")
    # Cheats
    if system.isOptSet('enable_cheats'):
        iniConfig.set("General", "EnableCheats", system.config["enable_cheats"])
    else:
        iniConfig.set("General", "EnableCheats", "False")
    # Don't check for a new version
    iniConfig.set("General", "CheckForNewVersion", "False")

    # SaveState
    if system.isOptSet('state_slot'):
        iniConfig.set("General", "StateSlot", str(system.config["state_slot"]))
    else:
        iniConfig.set("General", "StateSlot", "0")

    ## [UPGRADE] - don't upgrade
    if not iniConfig.has_section("Upgrade"):
        iniConfig.add_section("Upgrade")
    iniConfig.set("Upgrade", "UpgradeMessage", "")
    iniConfig.set("Upgrade", "UpgradeVersion", "")
    iniConfig.set("Upgrade", "DismissedVersion", "")

    ## [RetroAchievements]
    if not iniConfig.has_section("Achievements"):
        iniConfig.add_section("Achievements")
        
    # Achievements enabled
    if system.isOptSet('retroachievements') and system.getOptBoolean('retroachievements') == True:
      iniConfig.set("Achievements", "AchievementsEnable", "True")
    else:
      iniConfig.set("Achievements", "AchievementsEnable", "False")
    
    # Achievements credentials
    iniConfig.set("Achievements", "AchievementsUserName", system.config.get("retroachievements.username", ""))
    writeRetroAchievements(str(system.config.get("retroachievements.token", None)))
    
    # Achievements hardcore mode
    if system.isOptSet('retroachievements.hardcore') and system.getOptBoolean('retroachievements.hardcore') == True:
        iniConfig.set("Achievements", "AchievementsChallengeMode", "True")
    else:
        iniConfig.set("Achievements", "AchievementsChallengeMode", "False")
    
    # Achievements encore mode
    if system.isOptSet('retroachievements.encore') and system.getOptBoolean('retroachievements.encore') == True:
        iniConfig.set("Achievements", "AchievementsEncoreMode", "True")
    else:
        iniConfig.set("Achievements", "AchievementsEncoreMode", "False")

    # Achievements sound enabled
    if system.isOptSet("retroachievements.sound") and system.config["retroachievements.sound"] != "none":
        iniConfig.set("Achievements", "AchievementsSoundEffects", "True")
    else:
        iniConfig.set("Achievements", "AchievementsSoundEffects", "False")

    ## [NETWORK]
    if not iniConfig.has_section("Network"):
        iniConfig.add_section("Network")

    network_enable = system.isOptSet("network_enable") and system.getOptBoolean("network_enable")
    iniConfig.set("Network", "EnableWlan", str(network_enable))

    if network_enable:
        lan_adhoc_mode = system.config["lan_adhoc_mode"] if system.isOptSet("lan_adhoc_mode") else "off"
        port_offset = str(system.config["adhoc_port_offset"]) if system.isOptSet("adhoc_port_offset") else "10000"

        # only a LAN host runs the adhoc server itself
        iniConfig.set("Network", "EnableAdhocServer", str(lan_adhoc_mode == "host"))

        adhoc_server = system.config["adhoc_server"] if system.isOptSet("adhoc_server") else ""
        if adhoc_server and adhoc_server != "__manual__":
            iniConfig.set("Network", "proAdhocServer", adhoc_server)

        iniConfig.set("Network", "PortOffset", port_offset)
        upnp = system.isOptSet("upnp_enable") and system.getOptBoolean("upnp_enable")
        iniConfig.set("Network", "EnableUPnP", str(upnp))

        # relay and infrastructure settings only apply away from LAN host mode
        if lan_adhoc_mode == "off":
            relay = str(system.config["adhoc_relay_mode"]) if system.isOptSet("adhoc_relay_mode") else "0"
            iniConfig.set("Network", "AdhocServerRelayMode", relay)
            forced = system.isOptSet("adhoc_forced_connect") and system.getOptBoolean("adhoc_forced_connect")
            iniConfig.set("Network", "ForcedFirstConnect", str(forced))

            if not iniConfig.has_option("Network", "PrimaryDNSServer"):
                iniConfig.set("Network", "PrimaryDNSServer", "67.222.156.250")
            infra_auto_dns = system.config["infra_auto_dns"] if system.isOptSet("infra_auto_dns") else "auto"
            iniConfig.set("Network", "InfrastructureAutoDNS", "False" if infra_auto_dns == "manual" else "True")

    # Custom : allow the user to configure directly PPSSPP via knulli.conf via lines like : ppsspp.section.option=value
    for user_config in system.config:
        if user_config[:7] == "ppsspp.":
            section_option = user_config[7:]
            section_option_splitter = section_option.find(".")
            custom_section = section_option[:section_option_splitter]
            custom_option = section_option[section_option_splitter+1:]
            if not iniConfig.has_section(custom_section):
                iniConfig.add_section(custom_section)
            iniConfig.set(custom_section, custom_option, str(system.config[user_config]))
