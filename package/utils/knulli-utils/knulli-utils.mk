################################################################################
#
# KNULLI Utils
#
################################################################################
# Version.: Commits on March 3, 2026
KNULLI_UTILS_VERSION = 1
KNULLI_UTILS_SOURCE =
KNULLI_UTILS_LICENSE = GPLv2

KNULLI_UTILS_DEPENDENCIES = sdl2 sdl2_image sdl2_ttf sdl2_gfx zlib

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H700),y)
KNULLI_UTILS_DEPENDENCIES += sdl sdl_image sdl_ttf sdl_gfx
endif

KNULLI_UTILS_CXXFLAGS = -fdata-sections -ffunction-sections -fPIC -flto -Wall -D_RG28XX_
KNULLI_UTILS_CXXFLAGS += -DTRIPLE_BUFFER=1 $(TARGET_CXXFLAGS)

# SDL2 flags for progressbar
KNULLI_UTILS_SDL2_LDFLAGS = -lSDL2 -lSDL2_image -lSDL2_ttf -lSDL2_gfx -lz -lpthread -lm
KNULLI_UTILS_SDL2_LDFLAGS += -Wl,--as-needed -Wl,--gc-sections -flto $(TARGET_LDFLAGS)

# SDL1 flags for charger
KNULLI_UTILS_SDL1_LDFLAGS = -lSDL -lSDL_image -lSDL_ttf -lSDL_gfx -lz -lpthread -lm
KNULLI_UTILS_SDL1_LDFLAGS += -Wl,--as-needed -Wl,--gc-sections -flto $(TARGET_LDFLAGS)

define KNULLI_UTILS_BUILD_CMDS
	$(TARGET_CXX) $(KNULLI_UTILS_CXXFLAGS) \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/utils/knulli-utils/progressbar.cpp \
		$(KNULLI_UTILS_SDL2_LDFLAGS) -o $(@D)/progressbar
	$(if $(BR2_PACKAGE_BATOCERA_TARGET_H700), \
		$(TARGET_CXX) $(KNULLI_UTILS_CXXFLAGS) \
			$(BR2_EXTERNAL_KNULLI_PATH)/package/utils/knulli-utils/charger.cpp \
			$(KNULLI_UTILS_SDL1_LDFLAGS) -o $(@D)/charger)
endef

define KNULLI_UTILS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/progressbar $(TARGET_DIR)/usr/bin/progressbar
	$(if $(BR2_PACKAGE_BATOCERA_TARGET_H700), \
		$(INSTALL) -m 0755 -D $(@D)/charger $(TARGET_DIR)/usr/bin/charger)
endef

$(eval $(generic-package))
