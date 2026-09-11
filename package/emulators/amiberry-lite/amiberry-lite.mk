################################################################################
#
# amiberry-lite
#
# The SDL2 branch of amiberry.  Everything it installs is named after itself --
# /usr/bin/amiberry-lite, /usr/share/amiberry-lite, /usr/lib/amiberry-lite -- so
# it coexists with the SDL3 amiberry rather than replacing it, and a board can
# ship either or both.
#
################################################################################

AMIBERRY_LITE_VERSION = v5.9.2
AMIBERRY_LITE_SITE = $(call github,BlitterStudio,amiberry-lite,$(AMIBERRY_LITE_VERSION))
AMIBERRY_LITE_LICENSE = GPLv3
AMIBERRY_LITE_SUPPORTS_IN_SOURCE_BUILD = NO

AMIBERRY_LITE_DEPENDENCIES += sdl2 sdl2_image sdl2_ttf mpg123 libmpeg2 flac libpng
AMIBERRY_LITE_DEPENDENCIES += libserialport libportmidi zlib zstd libenet

AMIBERRY_LITE_CONF_OPTS += -DCMAKE_BUILD_TYPE=Release
AMIBERRY_LITE_CONF_OPTS += -DWITH_LTO=ON

# StandardProjectSettings.cmake blanks CMAKE_C_FLAGS/CMAKE_CXX_FLAGS for a
# Release build, which discards buildroot's -O2, and its Release branch adds no
# -O of its own.  The _RELEASE variables survive, so put the flags back there.
AMIBERRY_LITE_CONF_OPTS += -DCMAKE_C_FLAGS_RELEASE="$(TARGET_CFLAGS) -O3 -DNDEBUG"
AMIBERRY_LITE_CONF_OPTS += -DCMAKE_CXX_FLAGS_RELEASE="$(TARGET_CXXFLAGS) -O3 -DNDEBUG"

# Upstream marks its GL path WIP and it wants GLEW, which the handhelds do not
# carry.  The SDL renderer is the point of this build anyway.
AMIBERRY_LITE_CONF_OPTS += -DUSE_OPENGL=OFF

# PCem needs an x86 host to emulate the bridgeboards, so it never applies here.
AMIBERRY_LITE_CONF_OPTS += -DUSE_PCEM=OFF

# The upstream install rules already place the binary, the plugins it dlopens
# and its data under amiberry-lite names, so they are used as-is.  Only the
# desktop integration and the AROS roms need adjusting.
define AMIBERRY_LITE_INSTALL_EXTRAS
	# AROS (open source alternative BIOS).  Same files amiberry ships, so do
	# not clobber whichever package installed them first.
	mkdir -p $(TARGET_DIR)/usr/share/batocera/datainit/bios/amiga
	cp -prn $(@D)/roms/aros-ext.bin \
	    $(TARGET_DIR)/usr/share/batocera/datainit/bios/amiga/
	cp -prn $(@D)/roms/aros-rom.bin \
	    $(TARGET_DIR)/usr/share/batocera/datainit/bios/amiga/

	# no desktop on these images
	rm -rf $(TARGET_DIR)/usr/share/applications/Amiberry-Lite.desktop \
	       $(TARGET_DIR)/usr/share/icons/hicolor/scalable/apps/amiberry-lite.svg \
	       $(TARGET_DIR)/usr/share/metainfo/Amiberry-Lite.metainfo.xml \
	       $(TARGET_DIR)/usr/share/mime/packages/amiberry-lite.xml
endef

AMIBERRY_LITE_POST_INSTALL_TARGET_HOOKS = AMIBERRY_LITE_INSTALL_EXTRAS

$(eval $(cmake-package))
