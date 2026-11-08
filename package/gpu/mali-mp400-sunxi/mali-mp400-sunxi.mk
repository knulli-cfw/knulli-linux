################################################################################
#
# mali-mp400-sunxi
#
################################################################################

MALI_MP400_SUNXI_VERSION = 04be24458df7e5f5c24b27effbea554bad130ebf
MALI_MP400_SUNXI_SITE = https://github.com/acm-cfw/sunxi-mali.git
MALI_MP400_SUNXI_SITE_METHOD = git
MALI_MP400_SUNXI_GIT_SUBMODULES = YES
MALI_MP400_SUNXI_INSTALL_STAGING = YES
MALI_MP400_SUNXI_PROVIDES = libegl libgles
MALI_MP400_SUNXI_LICENSE = Allwinner End User Licence Agreement

MALI_MP400_SUNXI_DEPENDENCIES = host-toolchain-optional-linaro-arm

MALI_MP400_SUNXI_REV = $(call qstrip,$(BR2_PACKAGE_MALI_MP400_SUNXI_REVISION))
MALI_MP400_SUNXI_ARCH=armhf

define MALI_MP400_SUNXI_INSTALL_STAGING_CMDS
	mkdir -p $(STAGING_DIR)/usr/lib $(STAGING_DIR)/usr/include

	cp -rf $(@D)/lib/mali/$(MALI_MP400_SUNXI_REV)/$(MALI_MP400_SUNXI_ARCH)/fbdev/*.so* \
		$(STAGING_DIR)/usr/lib/
        (cd $(STAGING_DIR)/usr/lib && ln -sf libMali.so libmali.so)

	cp -rf $(@D)/include/* $(STAGING_DIR)/usr/include/

	$(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-mp400-sunxi/egl.pc \
		$(STAGING_DIR)/usr/lib/pkgconfig/egl.pc
	$(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-mp400-sunxi/glesv2.pc \
		$(STAGING_DIR)/usr/lib/pkgconfig/glesv2.pc
endef

define MALI_MP400_SUNXI_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/lib
	cp -rf $(@D)/lib/mali/$(MALI_MP400_SUNXI_REV)/$(MALI_MP400_SUNXI_ARCH)/fbdev/*.so* \
		$(TARGET_DIR)/usr/lib/
        (cd $(TARGET_DIR)/usr/lib && ln -sf libMali.so libmali.so)
	# the shared cores drop is linked on rk3128, whose blob is libmali.so.1
	(cd $(TARGET_DIR)/usr/lib && ln -sf libMali.so libmali.so.1)
endef

$(eval $(generic-package))
