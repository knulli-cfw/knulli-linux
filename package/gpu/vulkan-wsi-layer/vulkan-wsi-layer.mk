################################################################################
#
# vulkan-wsi-layer
#
################################################################################

# ROCKNIX's pin and patches, which run it with the g29p1 Mali blob on sway.
VULKAN_WSI_LAYER_VERSION = 8f077c5c862e5259841d524de8280b8c2429990a
VULKAN_WSI_LAYER_SITE = https://gitlab.freedesktop.org/mesa/vulkan-wsi-layer/-/archive/$(VULKAN_WSI_LAYER_VERSION)
VULKAN_WSI_LAYER_SOURCE = vulkan-wsi-layer-$(VULKAN_WSI_LAYER_VERSION).tar.gz
VULKAN_WSI_LAYER_LICENSE = MIT
VULKAN_WSI_LAYER_LICENSE_FILES = LICENSE
VULKAN_WSI_LAYER_DEPENDENCIES = host-wayland libdrm wayland wayland-protocols \
	vulkan-headers vulkan-loader

# Swapchain images come from a dma-buf heap.  The Rockchip BSP names its CMA
# heap "reserved", not "linux,cma"; "system" needs no carve-out, and both the
# GPU and the VOP sit behind an IOMMU, so they do not need contiguous memory.
VULKAN_WSI_LAYER_CONF_OPTS = \
	-DVULKAN_CXX_INCLUDE=$(STAGING_DIR)/usr/include \
	-DBUILD_WSI_HEADLESS=OFF \
	-DBUILD_WSI_WAYLAND=ON \
	-DSELECT_EXTERNAL_ALLOCATOR=dma_buf_heaps \
	-DWSIALLOC_MEMORY_HEAP_NAME=system \
	-DENABLE_WAYLAND_FIFO_PRESENTATION_THREAD=ON \
	-DKERNEL_HEADER_DIR=$(STAGING_DIR)/usr/include \
	-DWAYLAND_SCANNER_EXEC=$(HOST_DIR)/bin/wayland-scanner \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5

# No install rules upstream.
define VULKAN_WSI_LAYER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(VULKAN_WSI_LAYER_BUILDDIR)/libVkLayer_window_system_integration.so \
		$(TARGET_DIR)/usr/lib/libVkLayer_window_system_integration.so
	$(INSTALL) -D -m 0644 $(VULKAN_WSI_LAYER_BUILDDIR)/VkLayer_window_system_integration.json \
		$(TARGET_DIR)/etc/vulkan/implicit_layer.d/VkLayer_window_system_integration.json
endef

# The WSI layer implements vkCreateSwapchainKHR/vkQueuePresentKHR itself, so a
# layer that draws at present -- knulli-overlay -- has to sit above it.  The
# loader's default order puts it below, whatever the manifests are called; its
# settings file fixes the order (overlay, WSI, then everything else).
ifeq ($(BR2_PACKAGE_KNULLI_OVERLAY),y)
define VULKAN_WSI_LAYER_INSTALL_LOADER_SETTINGS
	$(INSTALL) -D -m 0644 $(VULKAN_WSI_LAYER_PKGDIR)/vk_loader_settings.json \
		$(TARGET_DIR)/etc/vulkan/loader_settings.d/vk_loader_settings.json
endef
VULKAN_WSI_LAYER_POST_INSTALL_TARGET_HOOKS += VULKAN_WSI_LAYER_INSTALL_LOADER_SETTINGS
endif

$(eval $(cmake-package))
