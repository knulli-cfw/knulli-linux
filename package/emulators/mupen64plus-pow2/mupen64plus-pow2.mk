################################################################################
#
# mupen64plus-pow2
#
################################################################################

MUPEN64PLUS_POW2_VERSION = 11ce3069f3d7d13af6bc0a9c42a8b05b46d09671
MUPEN64PLUS_POW2_SITE = https://github.com/beebono/mupen64plus-pow2.git
MUPEN64PLUS_POW2_SITE_METHOD = git
MUPEN64PLUS_POW2_GIT_SUBMODULES = YES
MUPEN64PLUS_POW2_LICENSE = GPL-3.0-or-later
MUPEN64PLUS_POW2_LICENSE_FILES = NOTICE LICENSES/GPL-3.0-or-later.txt
MUPEN64PLUS_POW2_DEPENDENCIES = sdl2 libpng zlib host-ninja $(BR2_CMAKE_HOST_DEPENDENCY)

define MUPEN64PLUS_POW2_BUILD_CMDS
	# Upstream's "sysroot" target is the distribution build: SDL2, zlib and
	# libpng are linked dynamically out of SYSROOT, the RSP is configured with
	# the given CMake toolchain file, and gcc-ar/gcc-ranlib are looked up on
	# PATH -- all three are what buildroot supplies.  0001 added a "buildroot"
	# target to the tree that predates that target; it is retired.
	#
	# The core and the audio/input plugins test for pkg-config as
	# "$(CROSS_COMPILE)pkg-config" at parse time and error out when it is
	# absent; buildroot ships one host pkg-config, not a cross-prefixed one.
	# PKG_CONFIG is only probed when the caller does not pass the flags, and
	# build-bundle.sh passes zlib/libpng/SDL2 explicitly, so pointing it at
	# the host tool with the sysroot as its search path is enough.
	cd $(@D) && $(TARGET_MAKE_ENV) \
		SYSROOT="$(STAGING_DIR)" CROSS_COMPILE="$(TARGET_CROSS)" \
		CMAKE_TOOLCHAIN_FILE="$(HOST_DIR)/share/buildroot/toolchainfile.cmake" \
		PKG_CONFIG="$(HOST_DIR)/bin/pkg-config" \
		PKG_CONFIG_PATH="$(STAGING_DIR)/usr/lib/pkgconfig" \
		JOBS=$(PARALLEL_JOBS) \
		bundle/build-bundle.sh sysroot $(@D)/out
endef

define MUPEN64PLUS_POW2_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/out/mupen64plus-pow2 $(TARGET_DIR)/usr/bin/mupen64plus-pow2
	$(INSTALL) -D -m 0644 $(@D)/ext/mupen64plus-core-dento/data/mupen64plus.ini \
		$(TARGET_DIR)/usr/share/mupen64plus-pow2/mupen64plus.ini
	$(INSTALL) -D -m 0644 $(@D)/ext/mupen64plus-core-dento/data/mupencheat.txt \
		$(TARGET_DIR)/usr/share/mupen64plus-pow2/mupencheat.txt
endef

$(eval $(generic-package))
