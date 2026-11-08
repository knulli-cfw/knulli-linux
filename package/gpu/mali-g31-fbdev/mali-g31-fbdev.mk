################################################################################
#
# mali g31 fbdev
#
################################################################################
# Version.: Commits on Apr 11, 2024
MALI_G31_FBDEV_VERSION = e992dcf03183862410dcb26ab3d596b7b207ce34
MALI_G31_FBDEV_SITE = $(call github,ben-willmore,t507_gpu_drivers,$(MALI_G31_FBDEV_VERSION))
MALI_G31_FBDEV_LICENSE = Proprietary
MALI_G31_FBDEV_LICENSE_FILES = END_USER_LICENCE_AGREEMENT.txt

MALI_G31_FBDEV_INSTALL_STAGING = YES
MALI_G31_FBDEV_PROVIDES = libegl libgles libmali

ifeq ($(BR2_aarch64),y)
LIB_SRC_DIR = aarch64-linux-gnu-7.4.1/lib64
endif

ifeq ($(BR2_arm),y)
LIB_SRC_DIR = armhf-linux-gnu/lib32
endif

define MALI_G31_FBDEV_INSTALL_STAGING_CMDS
	mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig

	cp -rf $(@D)/include/* $(STAGING_DIR)/usr/include/
	cp -rf $(@D)/fbdev/include/EGL/* $(STAGING_DIR)/usr/include/EGL/

	cp -rf $(@D)/fbdev/mali-g31/$(LIB_SRC_DIR)/* $(STAGING_DIR)/usr/lib/

        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-g31-fbdev/egl.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/egl.pc
        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-g31-fbdev/glesv2.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/glesv2.pc

endef

define MALI_G31_FBDEV_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/lib

        cp -rf $(@D)/fbdev/mali-g31/$(LIB_SRC_DIR)/* $(TARGET_DIR)/usr/lib/
	$(MALI_G31_FBDEV_LINK_SONAME)
endef

# This blob declares soname libmali.so.0, but the aarch64-v8a emulator drop is
# built on rk3576, where mali-libs ships libmali.so.1 -- so payload binaries
# record "NEEDED libmali.so.1" and will not load here without that filename.
#
# The link points at whatever real blob this package installed, so each board
# still runs its own driver; only the filename the loader looks for is shared.
# Created only when absent, so a future blob shipping libmali.so.1 itself wins.
define MALI_G31_FBDEV_LINK_SONAME
	cd $(TARGET_DIR)/usr/lib && \
	if [ ! -e libmali.so.1 ]; then \
		real=$$(ls -1 libmali.so.0.* 2>/dev/null | head -1); \
		if [ -z "$$real" ]; then real=$$(ls -1 libmali.so.0 2>/dev/null); fi; \
		if [ -n "$$real" ]; then \
			ln -sf "$$real" libmali.so.1; \
			echo "mali-g31-fbdev: linked libmali.so.1 -> $$real"; \
		fi; \
	fi
endef

$(eval $(generic-package))
