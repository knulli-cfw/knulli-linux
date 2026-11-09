################################################################################
#
# libretro-makecode-arcade
#
################################################################################

LIBRETRO_MAKECODE_ARCADE_VERSION = b4aff558fa6fa00600b140f71802d432223752f1
LIBRETRO_MAKECODE_ARCADE_SITE = $(call github,whmzsu,makecode-arcade-libretro,$(LIBRETRO_MAKECODE_ARCADE_VERSION))
LIBRETRO_MAKECODE_ARCADE_LICENSE = MIT
LIBRETRO_MAKECODE_ARCADE_LICENSE_FILES = LICENSE

# The libretro core lives in core/, the PXT runtime it embeds in runtime/ —
# same tree, so the plain generic-package build is enough.
define LIBRETRO_MAKECODE_ARCADE_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) CXX="$(TARGET_CXX)" CC="$(TARGET_CC)" \
		-C $(@D)/core -f Makefile platform=unix
endef

define LIBRETRO_MAKECODE_ARCADE_INSTALL_TARGET_CMDS
	$(INSTALL) -D $(@D)/core/makecode_arcade_libretro.so \
		$(TARGET_DIR)/usr/lib/libretro/makecode_arcade_libretro.so
endef

$(eval $(generic-package))
