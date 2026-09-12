BR2_EXTERNAL_BATOCERA_PATH = $(BR2_EXTERNAL_KNULLI_PATH)

# Define packages that knulli overrides
KNULLI_OVERRIDE_PACKAGES = libretro-flycastvl es-background-musics retroarch-assets \
							retroarch libretro-parallel-n64 libretro-yabasanshiro \
							common-shaders glsl-shaders slang-shaders batocera-shaders \
							batocera-triggerhappy azahar zramswap syncthing \
							libretro-gpsp libretro-melonds-ds dolphin-emu vita3k gzdoom \
							rocknix-abl rocknix-joypad libretro-gearcoleco \
							cargo-c sdl3 wildmidi \
							ppsspp mangohud toolchain-optional-linaro-aarch64 \
							uboot-rk3326 rk915

# Knulli packages
include $(sort $(wildcard $(BR2_EXTERNAL_KNULLI_PATH)/package/audio/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/boot/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/controllers/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/cores/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/emulators/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/emulators/*/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/firmwares/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/kernels/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/libraries/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/modules/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/music/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/retroarch/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/retroarch/*/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/system/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/themes/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/toolchain/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/utils/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/package/weston-legacy/*/*.mk))

# Include batocera packages but exclude conflicting ones
include $(sort $(filter-out $(addprefix %/,$(addsuffix .mk,$(KNULLI_OVERRIDE_PACKAGES))), \
$(wildcard $(BR2_EXTERNAL_KNULLI_PATH)/batocera/package/batocera/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/batocera/package/batocera/*/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/batocera/package/batocera/*/*/*/*.mk \
$(BR2_EXTERNAL_KNULLI_PATH)/batocera/package/batocera/*/*/*/*/*.mk )))
