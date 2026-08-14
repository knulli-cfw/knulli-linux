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

# vaixterm's Makefile expects libvterm sources under vendor/libvterm/ (vendored mode).
# Upstream CI fetches libvterm 0.3.3 from Ubuntu; buildroot has no libvterm package,
# so replicate the vendoring step ourselves as a post-patch hook.
VAIXTERM_LIBVTERM_VERSION = 0.3.3
VAIXTERM_LIBVTERM_TARBALL = libvterm-$(VAIXTERM_LIBVTERM_VERSION).tar.gz
VAIXTERM_LIBVTERM_URL = http://archive.ubuntu.com/ubuntu/pool/universe/libv/libvterm/libvterm_$(VAIXTERM_LIBVTERM_VERSION).orig.tar.gz

define VAIXTERM_VENDOR_LIBVTERM
	if [ ! -f $(DL_DIR)/vaixterm/$(VAIXTERM_LIBVTERM_TARBALL) ]; then \
		mkdir -p $(DL_DIR)/vaixterm; \
		$(WGET) -O $(DL_DIR)/vaixterm/$(VAIXTERM_LIBVTERM_TARBALL) $(VAIXTERM_LIBVTERM_URL); \
	fi; \
	mkdir -p $(@D)/vendor; \
	tar xzf $(DL_DIR)/vaixterm/$(VAIXTERM_LIBVTERM_TARBALL) -C $(@D)/vendor; \
	mv $(@D)/vendor/libvterm-$(VAIXTERM_LIBVTERM_VERSION) $(@D)/vendor/libvterm
endef

VAIXTERM_POST_PATCH_HOOKS += VAIXTERM_VENDOR_LIBVTERM

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