################################################################################
#
# vaixterm
#
################################################################################

VAIXTERM_VERSION = main
VAIXTERM_SITE = https://github.com/Stanley00/vaixterm.git
VAIXTERM_SITE_METHOD = git
VAIXTERM_LICENSE = MIT
VAIXTERM_LICENSE_FILES = LICENSE

VAIXTERM_DEPENDENCIES = sdl2 sdl2_ttf sdl2_image

# libvterm is built in from vendor/libvterm (upstream CI layout)
VAIXTERM_VTERM_VERSION = 0.3.3
VAIXTERM_EXTRA_DOWNLOADS = https://www.leonerd.org.uk/code/libvterm/libvterm-$(VAIXTERM_VTERM_VERSION).tar.gz

define VAIXTERM_EXTRACT_VTERM
	mkdir -p $(@D)/vendor/libvterm
	$(TAR) -xzf $(VAIXTERM_DL_DIR)/libvterm-$(VAIXTERM_VTERM_VERSION).tar.gz \
		-C $(@D)/vendor/libvterm --strip-components=1 \
		libvterm-$(VAIXTERM_VTERM_VERSION)/src libvterm-$(VAIXTERM_VTERM_VERSION)/include
endef
VAIXTERM_POST_EXTRACT_HOOKS += VAIXTERM_EXTRACT_VTERM

# Get SDL2 compilation and linking flags
VAIXTERM_SDL_CFLAGS = $(shell $(PKG_CONFIG_HOST_BINARY) --cflags sdl2 SDL2_ttf SDL2_image)
VAIXTERM_SDL_LIBS = $(shell $(PKG_CONFIG_HOST_BINARY) --libs sdl2 SDL2_ttf SDL2_image)

# Try to use the project's Makefile with proper environment variables
define VAIXTERM_BUILD_CMDS
    $(MAKE) $(TARGET_CONFIGURE_OPTS) \
        PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
        CFLAGS="$(TARGET_CFLAGS) $(VAIXTERM_SDL_CFLAGS) -Iinclude -Isrc -Ivendor/libvterm/include -Ivendor/libvterm/src" \
        LDFLAGS="$(TARGET_LDFLAGS) $(VAIXTERM_SDL_LIBS) -lm" \
        -C $(@D)
endef

define VAIXTERM_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(@D)/vaixterm $(TARGET_DIR)/usr/bin/vaixterm
endef

# Install resource files if they exist
define VAIXTERM_INSTALL_RES_CMDS
    if [ -d $(@D)/res ]; then \
        $(INSTALL) -d $(TARGET_DIR)/usr/share/vaixterm/res && \
        cp -r $(@D)/res/* $(TARGET_DIR)/usr/share/vaixterm/res/; \
    fi
endef

VAIXTERM_POST_INSTALL_TARGET_HOOKS += VAIXTERM_INSTALL_RES_CMDS

$(eval $(generic-package))