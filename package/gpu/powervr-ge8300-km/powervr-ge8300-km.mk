################################################################################
#
# powervr-ge8300-km
#
################################################################################

POWERVR_GE8300_KM_VERSION = fbb38f3f712a9b151f7482450bafd939b8269ae8
POWERVR_GE8300_KM_SITE = $(call github,pocketforge-os,gpu-km-tsp,$(POWERVR_GE8300_KM_VERSION))
POWERVR_GE8300_KM_LICENSE = MIT or GPL-2.0
POWERVR_GE8300_KM_LICENSE_FILES = MIT-COPYING GPL-COPYING
POWERVR_GE8300_KM_DEPENDENCIES = linux

POWERVR_GE8300_KM_MODULE_MAKE_OPTS = CONFIG_DRM_IMG_ROGUE=m PVR_SYSTEM=sunxi_a133

# the GPU sits behind its own power domain; without the provider it never probes
define POWERVR_GE8300_KM_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_AW_GPU_PM_DOMAINS)
endef

# Installed by hand: the DDK's modules.order lists "<dir>/./<mod>.ko", which
# modules_install cannot map, so it installs nothing.  Straight into
# /lib/modules/<version>/: pvrsrvctl --start (rcS) loads them from there.
define POWERVR_GE8300_KM_INSTALL_MODULES
	for m in pvrsrvkm dc_sunxi; do \
		$(INSTALL) -D -m 0644 $(@D)/$$m.ko \
			$(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/$$m.ko && \
		$(TARGET_STRIP) --strip-debug \
			$(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/$$m.ko || exit 1; \
	done
endef
POWERVR_GE8300_KM_POST_INSTALL_TARGET_HOOKS += POWERVR_GE8300_KM_INSTALL_MODULES

$(eval $(kernel-module))
$(eval $(generic-package))
