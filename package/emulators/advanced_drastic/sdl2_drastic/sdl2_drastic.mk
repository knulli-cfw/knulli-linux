################################################################################
#
# sdl2 for drastic
#
################################################################################

SDL2_DRASTIC_VERSION = eb2e00f8b7459df90e273208f6cc49427c64267f
#SDL2_DRASTIC_VERSION = 2.32.8
#SDL2_DRASTIC_SOURCE = SDL2-$(SDL2_VERSION).tar.gz
#SDL2_DRASTIC_SITE = http://www.libsdl.org/release
#SDL2_DRASTIC_VERSION = 2.32.8
SDL2_DRASTIC_SITE = $(call github,trngaje,SDL_drastic,$(SDL2_DRASTIC_VERSION))
SDL2_DRASTIC_LICENSE = Zlib
SDL2_DRASTIC_LICENSE_FILES = LICENSE.txt
SDL2_DRASTIC_CPE_ID_VENDOR = libsdl
SDL2_DRASTIC_CPE_ID_PRODUCT = simple_directmedia_layer
#SDL2_DRASTIC_INSTALL_STAGING = YES
SDL2_DRASTIC_CONFIG_SCRIPTS = sdl2-config

# batocera - Removed --disable-video-wayland and --disable-video-vulkan
SDL2_DRASTIC_CONF_OPTS += \
	--disable-rpath \
	--disable-arts \
	--disable-esd \
	--disable-dbus \
	--disable-pulseaudio \
	--disable-video-vivante \
	--disable-video-cocoa \
	--disable-video-metal \
	--disable-video-dummy \
	--disable-video-offscreen \
	--disable-ime \
	--disable-ibus \
	--disable-fcitx \
	--disable-joystick-mfi \
	--disable-directx \
	--disable-xinput \
	--disable-wasapi \
	--disable-hidapi-joystick \
	--disable-hidapi-libusb \
	--disable-joystick-virtual \
	--disable-render-d3d

# We are using autotools build system for sdl2, so the sdl2-config.cmake
# include path are not resolved like for sdl2-config script.
# Change the absolute /usr path to resolve relatively to the sdl2-config.cmake location.
# https://bugzilla.libsdl.org/show_bug.cgi?id=4597
define SDL2_DRASTIC_FIX_SDL2_CONFIG_CMAKE
	$(SED) '2iget_filename_component(PACKAGE_PREFIX_DIR "$${CMAKE_CURRENT_LIST_DIR}/../../../" ABSOLUTE)\n' \
		$(STAGING_DIR)/usr/lib/cmake/SDL2/sdl2-config.cmake
	$(SED) 's%"/usr"%$${PACKAGE_PREFIX_DIR}%' \
		$(STAGING_DIR)/usr/lib/cmake/SDL2/sdl2-config.cmake
endef

# batocera
define SDL2_DRASTIC_FIX_WAYLAND_SCANNER_PATH
	sed -i "s+/usr/bin/wayland-scanner+$(HOST_DIR)/usr/bin/wayland-scanner+g" $(@D)/Makefile
endef

define SDL2_DRASTIC_FIX_CONFIGURE_PATHS
	sed -i "s+/host/bin/\.\.+/host+g" $(@D)/config.log
	sed -i "s+/host/bin/\.\.+/host+g" $(@D)/config.status
	sed -i "s+/host/bin/\.\.+/host+g" $(@D)/libtool
	sed -i "s+/host/bin/\.\.+/host+g" $(@D)/Makefile
	sed -i "s+/host/bin/\.\.+/host+g" $(@D)/sdl2-config
	sed -i "s+/host/bin/\.\.+/host+g" $(@D)/sdl2.pc
	sed -i "s+-I/.* ++g"              $(@D)/sdl2.pc
endef

SDL2_DRASTIC_POST_CONFIGURE_HOOKS += SDL2_DRASTIC_FIX_WAYLAND_SCANNER_PATH
SDL2_DRASTIC_POST_CONFIGURE_HOOKS += SDL2_DRASTIC_FIX_CONFIGURE_PATHS

SDL2_DRASTIC_POST_INSTALL_STAGING_HOOKS += SDL2_DRASTIC_FIX_SDL2_CONFIG_CMAKE

# We must enable static build to get compilation successful.
SDL2_DRASTIC_CONF_OPTS += --enable-static

# batocera - disable hidapi
SDL2_DRASTIC_CONF_OPTS += --disable-hidapi

# batocera - sdl2 set the rpi video output from the host name
ifeq ($(BR2_PACKAGE_RPI_USERLAND),y)
SDL2_DRASTIC_CONF_OPTS += --host=arm-raspberry-linux-gnueabihf
endif

SDL2_DRASTIC_CONF_OPTS += --host=aarch64-buildroot-linux-gnu

# batocera - Used in screen rotation (SDL and Retroarch)
ifeq ($(BR2_PACKAGE_ROCKCHIP_RGA),y)
SDL2_DRASTIC_DEPENDENCIES += rockchip-rga
endif

# batocera - use Pipewire audio
ifeq ($(BR2_PACKAGE_PIPEWIRE),y)
SDL2_DRASTIC_CONF_OPTS += --enable-pipewire
endif

# batocera - ensure mesa for riscv is built before sdl2
ifeq ($(BR2_PACKAGE_IMG_MESA3D),y)
SDL2_DRASTIC_DEPENDENCIES += img-mesa3d
endif

ifeq ($(BR2_ARM_INSTRUCTIONS_THUMB),y)
SDL2_DRASTIC_CONF_ENV += CFLAGS="$(TARGET_CFLAGS) -marm"
endif

ifeq ($(BR2_PACKAGE_HAS_UDEV),y)
SDL2_DRASTIC_DEPENDENCIES += udev
SDL2_DRASTIC_CONF_OPTS += --enable-libudev
else
SDL2_DRASTIC_CONF_OPTS += --disable-libudev
endif

ifeq ($(BR2_X86_CPU_HAS_SSE),y)
SDL2_DRASTIC_CONF_OPTS += --enable-sse
else
SDL2_DRASTIC_CONF_OPTS += --disable-sse
endif

# batocera / with patch sdl2_add_video_mali_gles2.patch / mrfixit
ifeq ($(BR2_PACKAGE_HAS_LIBMALI),y)
SDL2_DRASTIC_CONF_OPTS += --enable-video-mali
endif

ifeq ($(BR2_X86_CPU_HAS_3DNOW),y)
SDL2_DRASTIC_CONF_OPTS += --enable-3dnow
else
SDL2_DRASTIC_CONF_OPTS += --disable-3dnow
endif

ifeq ($(BR2_PACKAGE_SDL2_DIRECTFB),y)
SDL2_DRASTIC_DEPENDENCIES += directfb
SDL2_DRASTIC_CONF_OPTS += --enable-video-directfb
SDL2_DRASTIC_CONF_ENV += ac_cv_path_DIRECTFBCONFIG=$(STAGING_DIR)/usr/bin/directfb-config
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-directfb
endif

ifeq ($(BR2_PACKAGE_SDL2_OPENGLES)$(BR2_PACKAGE_RPI_USERLAND),yy)
SDL2_DRASTIC_DEPENDENCIES += rpi-userland
SDL2_DRASTIC_CONF_OPTS += --enable-video-rpi
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-rpi
endif

# x-includes and x-libraries must be set for cross-compiling
# By default x_includes and x_libraries contains unsafe paths.
# (/usr/X11R6/include and /usr/X11R6/lib)
ifeq ($(BR2_PACKAGE_SDL2_X11),y)
SDL2_DRASTIC_DEPENDENCIES += xlib_libX11 xlib_libXext

# X11/extensions/shape.h is provided by libXext.
SDL2_DRASTIC_CONF_OPTS += --enable-video-x11 \
	--with-x=$(STAGING_DIR) \
	--x-includes=$(STAGING_DIR)/usr/include \
	--x-libraries=$(STAGING_DIR)/usr/lib \
	--enable-video-x11-xshape

ifeq ($(BR2_PACKAGE_XLIB_LIBXCURSOR),y)
SDL2_DRASTIC_DEPENDENCIES += xlib_libXcursor
SDL2_DRASTIC_CONF_OPTS += --enable-video-x11-xcursor
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-x11-xcursor
endif

ifeq ($(BR2_PACKAGE_XLIB_LIBXI),y)
SDL2_DRASTIC_DEPENDENCIES += xlib_libXi
SDL2_DRASTIC_CONF_OPTS += --enable-video-x11-xinput
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-x11-xinput
endif

ifeq ($(BR2_PACKAGE_XLIB_LIBXRANDR),y)
SDL2_DRASTIC_DEPENDENCIES += xlib_libXrandr
SDL2_DRASTIC_CONF_OPTS += --enable-video-x11-xrandr
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-x11-xrandr
endif

ifeq ($(BR2_PACKAGE_XLIB_LIBXSCRNSAVER),y)
SDL2_DRASTIC_DEPENDENCIES += xlib_libXScrnSaver
SDL2_DRASTIC_CONF_OPTS += --enable-video-x11-scrnsaver
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-x11-scrnsaver
endif

else
SDL2_DRASTIC_CONF_OPTS += --disable-video-x11 --without-x
endif

ifeq ($(BR2_PACKAGE_SDL2_OPENGL),y)
SDL2_DRASTIC_CONF_OPTS += --enable-video-opengl
SDL2_DRASTIC_DEPENDENCIES += libgl
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-opengl
endif

ifeq ($(BR2_PACKAGE_SDL2_OPENGLES),y)
SDL2_DRASTIC_CONF_OPTS += \
	--enable-video-opengles \
	--enable-video-opengles1 \
	--enable-video-opengles2
SDL2_DRASTIC_DEPENDENCIES += libgles
else
SDL2_DRASTIC_CONF_OPTS += \
	--disable-video-opengles \
	--disable-video-opengles1 \
	--disable-video-opengles2
endif

ifeq ($(BR2_PACKAGE_ALSA_LIB),y)
SDL2_DRASTIC_DEPENDENCIES += alsa-lib
SDL2_DRASTIC_CONF_OPTS += --enable-alsa
else
SDL2_DRASTIC_CONF_OPTS += --disable-alsa
endif

ifeq ($(BR2_PACKAGE_SDL2_KMSDRM),y)
SDL2_DRASTIC_DEPENDENCIES += libdrm
SDL2_DRASTIC_CONF_OPTS += --enable-video-kmsdrm
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-kmsdrm
endif

# batocera - enable/disable Wayland video driver
ifeq ($(BR2_PACKAGE_SDL2_WAYLAND),y)
SDL2_DRASTIC_DEPENDENCIES += wayland wayland-protocols libxkbcommon
SDL2_DRASTIC_CONF_OPTS += --enable-video-wayland
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-wayland
endif

# batocera - libdecor
ifeq ($(BR2_PACKAGE_LIBDECOR),y)
SDL2_DRASTIC_DEPENDENCIES += libdecor
endif

# batocera - enable/disable Vulkan support
ifeq ($(BR2_PACKAGE_VULKAN_HEADERS)$(BR2_PACKAGE_VULKAN_LOADER),yy)
SDL2_DRASTIC_DEPENDENCIES += vulkan-headers vulkan-loader
SDL2_DRASTIC_CONF_OPTS += --enable-video-vulkan
else
SDL2_DRASTIC_CONF_OPTS += --disable-video-vulkan
endif

#SDL2_DRASTIC_TARGET_CFLAGS +=  -DRG35XXH -DRG35XXH_GL -I$(STAGING_DIR)/usr/include/SDL2
SDL2_DRASTIC_TARGET_CFLAGS += -I$(STAGING_DIR)/usr/include/SDL2
SDL2_DRASTIC_TARGET_LDFLAGS += -lSDL2_image -lSDL2_ttf -ljson-c -lpthread
#$(BR2_PACKAGE_BATOCERA_TARGET_H700)
ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_A133),y)
SDL2_DRASTIC_TARGET_LDFLAGS += -lEGL -lGLESv2
SDL2_DRASTIC_TARGET_CFLAGS += -DDEVICE_TRIMUI
else
SDL2_DRASTIC_TARGET_LDFLAGS += -lmali
endif

# rk3568/rk3566: rockchip mali blob rejects trngaje's standalone
# DRM+GBM+EGL setup. Have egl_init adopt SDL's KMSDRM context instead
# so we present through SDL's already-patched rockchip render path
# (see 0007-rk3566-adopt-sdl-egl-context.patch).
ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3568),y)
SDL2_DRASTIC_TARGET_CFLAGS += -DADVDRASTIC_SDL_GL
endif

define SDL2_DRASTIC_CONFIGURE_CMDS
        (cd $(@D); rm -rf config.cache; \
                $(TARGET_CONFIGURE_ARGS) \
                $(TARGET_CONFIGURE_OPTS) \
                CFLAGS="$(TARGET_CFLAGS) $(SDL2_DRASTIC_TARGET_CFLAGS)" \
                LDFLAGS="$(TARGET_LDFLAGS) $(SDL2_DRASTIC_TARGET_LDFLAGS) -lc" \
                CROSS_COMPILE="$(HOST_DIR)/usr/bin/" \
                ./configure \
                --prefix=/usr \
                $(SDL2_DRASTIC_CONF_OPTS) \
        )
endef

define SDL2_DRASTIC_BUILD_CMDS
        $(TARGET_CONFIGURE_OPTS) $(MAKE) CXX="$(TARGET_CXX)" CC="$(TARGET_CC)" LD="$(TARGET_LD)" -C $(@D)
endef

define SDL2_DRASTIC_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/advanced_drastic/libs/

	cp -f $(@D)/build/.libs/libSDL2-2.0.so.0 $(TARGET_DIR)/usr/share/advanced_drastic/libs/
endef

#$(eval $(autotools-package))
$(eval $(generic-package)) 
