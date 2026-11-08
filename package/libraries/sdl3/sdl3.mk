################################################################################
#
# sdl3
#
################################################################################

SDL3_VERSION = 3.4.2
SDL3_SOURCE = SDL3-$(SDL3_VERSION).tar.gz
SDL3_SITE = http://www.libsdl.org/release
SDL3_LICENSE = Zlib
SDL3_LICENSE_FILES = LICENSE.txt
SDL3_CPE_ID_VENDOR = libsdl
SDL3_CPE_ID_PRODUCT = simple_directmedia_layer
SDL3_INSTALL_STAGING = YES

SDL3_CONF_OPTS += -DCMAKE_BUILD_TYPE=Release
SDL3_CONF_OPTS += -DSDL_RENDER_METAL=OFF
SDL3_CONF_OPTS += -DSDL_CCACHE=ON
SDL3_CONF_OPTS += -DSDL_JACK=OFF
SDL3_CONF_OPTS += -DSDL_HIDAPI=OFF
SDL3_CONF_OPTS += -DSDL_HIDAPI_LIBUSB=OFF
SDL3_CONF_OPTS += -DSDL_HIDAPI_LIBUSB_SHARED=OFF

ifeq ($(BR2_PACKAGE_ALSA_LIB),y)
SDL3_DEPENDENCIES += alsa-lib
SDL3_CONF_OPTS += -DSDL_ALSA=ON
SDL3_CONF_OPTS += -DSDL_ALSA_SHARED=ON
else
SDL3_CONF_OPTS += -DSDL_ALSA=OFF
SDL3_CONF_OPTS += -DSDL_ALSA_SHARED=OFF
endif

ifeq ($(BR2_PACKAGE_DBUS),y)
SDL3_DEPENDENCIES += dbus
SDL3_CONF_OPTS += -DSDL_DBUS=ON
else
SDL3_CONF_OPTS += -DSDL_DBUS=OFF
endif

ifeq ($(BR2_PACKAGE_PULSEAUDIO),y)
SDL3_DEPENDENCIES += pulseaudio
SDL3_CONF_OPTS += -DSDL_PULSEAUDIO=ON
SDL3_CONF_OPTS += -DSDL_PULSEAUDIO_SHARED=ON
else
SDL3_CONF_OPTS += -DSDL_PULSEAUDIO=OFF
SDL3_CONF_OPTS += -DSDL_PULSEAUDIO_SHARED=OFF
endif

ifeq ($(BR2_PACKAGE_MESA3D),y)
SDL3_DEPENDENCIES += mesa3d
SDL3_CONF_OPTS += -DSDL_RENDER_GPU=ON
else
SDL3_CONF_OPTS += -DSDL_RENDER_GPU=OFF
endif

ifeq ($(BR2_PACKAGE_PIPEWIRE),y)
SDL3_DEPENDENCIES += pipewire
SDL3_CONF_OPTS += -DSDL_PIPEWIRE=ON
else
SDL3_CONF_OPTS += -DSDL_PIPEWIRE=OFF
endif

ifeq ($(BR2_PACKAGE_HAS_UDEV),y)
SDL3_DEPENDENCIES += udev
SDL3_CONF_OPTS += -DSDL_LIBUDEV=ON
else
SDL3_CONF_OPTS += -DSDL_LIBUDEV=OFF
endif

ifeq ($(BR2_PACKAGE_BATOCERA_VULKAN),y)
# vulkan-loader only: Vulkan does not imply mesa3d.  On the mali/powervr boards
# the ICD comes from a vendor blob and BR2_PACKAGE_MESA3D is off, so naming
# mesa3d here trips buildroot's "added to _DEPENDENCIES without selecting it"
# check.  The mesa3d case is already handled above, gated on BR2_PACKAGE_MESA3D.
SDL3_DEPENDENCIES += vulkan-loader
SDL3_CONF_OPTS += -DSDL_VULKAN=ON
SDL3_CONF_OPTS += -DSDL_RENDER_VULKAN=ON
else
SDL3_CONF_OPTS += -DSDL_VULKAN=OFF
SDL3_CONF_OPTS += -DSDL_RENDER_VULKAN=OFF
endif

ifeq ($(BR2_PACKAGE_SDL3_KMSDRM),y)
SDL3_DEPENDENCIES += libdrm
SDL3_CONF_OPTS += -DSDL_KMSDRM=ON
else
SDL3_CONF_OPTS += -DSDL_KMSDRM=OFF
endif

ifeq ($(BR2_PACKAGE_SDL3_OPENGL),y)
SDL3_DEPENDENCIES += libgl
SDL3_CONF_OPTS += -DSDL_OPENGL=ON
else
SDL3_CONF_OPTS += -DSDL_OPENGL=OFF
endif

ifeq ($(BR2_PACKAGE_SDL3_OPENGLES),y)
SDL3_DEPENDENCIES += libgles
SDL3_CONF_OPTS += -DSDL_OPENGLES=ON
else
SDL3_CONF_OPTS += -DSDL_OPENGLES=OFF
endif

ifeq ($(BR2_PACKAGE_SDL3_WAYLAND),y)
SDL3_DEPENDENCIES += wayland wayland-protocols libxkbcommon
SDL3_CONF_OPTS += -DSDL_WAYLAND=ON
else
SDL3_CONF_OPTS += -DSDL_WAYLAND=OFF
endif

ifeq ($(BR2_PACKAGE_SDL3_X11),y)
SDL3_DEPENDENCIES += xlib_libX11 xlib_libXext xlib_libXi
SDL3_CONF_OPTS += -DSDL_X11=ON
SDL3_CONF_OPTS += -DSDL_X11_SHARED=ON
# find_package(X11) does not populate X11_Xi_LIB against the buildroot sysroot,
# so the FindLibraryAndSONAME("Xi") loop in cmake/sdlchecks.cmake leaves XI_LIB
# empty and the "if(HAVE_XINPUT2_H AND XI_LIB)" test fails -- even though
# XInput2.h, libXi.so.6 and xi.pc are all staged.  The other X11 extensions
# (Xcursor/Xfixes/Xrandr) resolve, so only this one needs help.
#
# It is not merely a lost feature: with SDL_VIDEO_DRIVER_X11_XINPUT2 undefined,
# SDL_x11xinput2.c still compiles X11_InitXinput2Multitouch and
# X11_Xinput2HandlesMotionForWindow (they sit AFTER the #endif at line 749)
# while the statics they use are declared only under the narrower
# SUPPORTS_SCROLLINFO/SUPPORTS_MULTITOUCH guard -- so the build fails outright.
SDL3_CONF_OPTS += -DX11_Xi_LIB=$(STAGING_DIR)/usr/lib/libXi.so
SDL3_CONF_OPTS += -DX11_Xi_INCLUDE_PATH=$(STAGING_DIR)/usr/include
ifeq ($(BR2_PACKAGE_XLIB_LIBXCURSOR),y)
SDL3_DEPENDENCIES += xlib_libXcursor
SDL3_CONF_OPTS += -DSDL_X11_XCURSOR=ON
else
SDL3_CONF_OPTS += -DSDL_X11_XCURSOR=OFF
endif
ifeq ($(BR2_PACKAGE_XLIB_LIBXFIXES),y)
SDL3_DEPENDENCIES += xlib_libXfixes
SDL3_CONF_OPTS += -DSDL_X11_XFIXES=ON
else
SDL3_CONF_OPTS += -DSDL_X11_XFIXES=OFF
endif
ifeq ($(BR2_PACKAGE_XLIB_LIBXRANDR),y)
SDL3_DEPENDENCIES += xlib_libXrandr
SDL3_CONF_OPTS += -DSDL_X11_XRANDR=ON
else
SDL3_CONF_OPTS += -DSDL_X11_XRANDR=OFF
endif
ifeq ($(BR2_PACKAGE_XLIB_LIBXSCRNSAVER),y)
SDL3_DEPENDENCIES += xlib_libXScrnSaver
SDL3_CONF_OPTS += -DSDL_X11_XSCRNSAVER=ON
else
SDL3_CONF_OPTS += -DSDL_X11_XSCRNSAVER=OFF
endif
# SDL's XInput2 support needs the CLIENT LIBRARY libXi, not the xinput
# command-line tool.  This tested BR2_PACKAGE_XAPP_XINPUT (the tool), which is
# off on our boards, so SDL_X11_XINPUT went OFF even with libXi and XInput2.h
# staged -- and SDL_x11xinput2.c does not build in that state: its
# X11_InitXinput2Multitouch / X11_Xinput2HandlesMotionForWindow sit after the
# "#endif // SDL_VIDEO_DRIVER_X11_XINPUT2" yet use statics declared only inside it.
ifeq ($(BR2_PACKAGE_XLIB_LIBXI),y)
SDL3_CONF_OPTS += -DSDL_X11_XINPUT=ON
else
SDL3_CONF_OPTS += -DSDL_X11_XINPUT=OFF
endif
else
SDL3_CONF_OPTS += -DSDL_X11=OFF
SDL3_CONF_OPTS += -DSDL_X11_SHARED=OFF
endif

# Add option for a system without a standard desktop windowing environment.
ifeq ($(BR2_PACKAGE_SDL3_WAYLAND)$(BR2_PACKAGE_SDL3_X11),)
SDL3_CONF_OPTS += -DSDL_UNIX_CONSOLE_BUILD=ON
endif

$(eval $(cmake-package))
