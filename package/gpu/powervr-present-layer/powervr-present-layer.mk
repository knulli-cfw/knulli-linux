################################################################################
#
# powervr-present-layer
#
################################################################################

POWERVR_PRESENT_LAYER_VERSION = 1.0
POWERVR_PRESENT_LAYER_SITE = $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/powervr-present-layer
POWERVR_PRESENT_LAYER_SITE_METHOD = local
POWERVR_PRESENT_LAYER_LICENSE = MIT
POWERVR_PRESENT_LAYER_DEPENDENCIES = vulkan-headers vulkan-loader

define POWERVR_PRESENT_LAYER_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -fPIC -shared -Wall \
		-o $(@D)/libVkLayer_knulli_powervr_present.so \
		$(@D)/powervr_present_layer.c -lpthread
endef

define POWERVR_PRESENT_LAYER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libVkLayer_knulli_powervr_present.so \
		$(TARGET_DIR)/usr/lib/libVkLayer_knulli_powervr_present.so
	$(INSTALL) -D -m 0644 $(@D)/knulli_powervr_present.json \
		$(TARGET_DIR)/usr/share/vulkan/implicit_layer.d/knulli_powervr_present.json
endef

$(eval $(generic-package))
