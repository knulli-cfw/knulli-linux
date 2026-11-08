################################################################################
#
# knulli-overlay
#
################################################################################

KNULLI_OVERLAY_VERSION = 70ccb7881b8fc94d5acee1028a221f4c397ccf18
KNULLI_OVERLAY_SITE = https://github.com/knulli-cfw/knulli-overlay.git
KNULLI_OVERLAY_SITE_METHOD = git
KNULLI_OVERLAY_LICENSE = GPL-3.0
KNULLI_OVERLAY_LICENSE_FILES = LICENSE

# The Vulkan layer is built only where the headers are; the loader never gets
# linked, so the headers alone are enough.
ifeq ($(BR2_PACKAGE_VULKAN_HEADERS),y)
KNULLI_OVERLAY_DEPENDENCIES += vulkan-headers
endif

# CC has to be passed on the command line: the project's Makefile derives it
# from CROSS_COMPILE, which would win over the environment.  CFLAGS/LDFLAGS
# must stay in the environment, so the Makefile can still append to them.
define KNULLI_OVERLAY_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(TARGET_CONFIGURE_OPTS) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" OUTDIR=build
endef

define KNULLI_OVERLAY_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/build/libknulli-overlay.so \
		$(TARGET_DIR)/usr/lib/libknulli-overlay.so
	$(INSTALL) -D -m 0755 $(@D)/build/knulli-overlay \
		$(TARGET_DIR)/usr/bin/knulli-overlay
	$(INSTALL) -D -m 0755 $(@D)/scripts/knulli-overlay-watch \
		$(TARGET_DIR)/usr/bin/knulli-overlay-watch
endef

# An implicit layer: the loader picks it up for every Vulkan process, and
# OV_DISABLE_VK_LAYER=1 turns it off again.
#
# The manifest is named to sort last in implicit_layer.d.  The loader activates
# implicit layers in the order it reads the directory -- sorted, on squashfs --
# and the first one read sits closest to the application.  The overlay has to be
# *under* knulli_powervr_present, whose vkCmdCopyImage tells it which shadow
# image belongs to which swapchain image; above it, that call never arrives and
# every frame is skipped without a word.
KNULLI_OVERLAY_LAYER_MANIFEST = zz_knulli_overlay.json

ifeq ($(BR2_PACKAGE_VULKAN_HEADERS),y)
define KNULLI_OVERLAY_INSTALL_VULKAN_LAYER
	$(INSTALL) -D -m 0755 $(@D)/build/libVkLayer_knulli_overlay.so \
		$(TARGET_DIR)/usr/lib/libVkLayer_knulli_overlay.so
	$(INSTALL) -D -m 0644 $(@D)/config/knulli_overlay_layer.json \
		$(TARGET_DIR)/usr/share/vulkan/implicit_layer.d/$(KNULLI_OVERLAY_LAYER_MANIFEST)
endef
KNULLI_OVERLAY_POST_INSTALL_TARGET_HOOKS += KNULLI_OVERLAY_INSTALL_VULKAN_LAYER
endif

$(eval $(generic-package))
