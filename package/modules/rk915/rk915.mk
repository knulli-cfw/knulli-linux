################################################################################
#
# rk915 - Rockchip RK915 SDIO WiFi out-of-tree driver
#
# Same upstream and commit as batocera's package (ImanolBarba/rk915, vendor BSP
# driver ported to mainline 6.18); redefined here because it needs a 6.1
# compatibility patch to build against the rk3326 BSP kernel. Firmware ships in
# the repo and is loaded by the driver from /lib/firmware with filp_open, so it
# must be on the rootfs, not in an initramfs.
#
################################################################################

RK915_VERSION = bf237144d8fde7dffaef1777350b23d5d40d0920
RK915_SITE = $(call github,ImanolBarba,rk915,$(RK915_VERSION))
RK915_LICENSE = GPL-2.0
RK915_LICENSE_FILES = LICENSE
RK915_DEPENDENCIES = linux

RK915_MODULE_MAKE_OPTS = CONFIG_RK915=m

define RK915_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211)
endef

define RK915_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0644 -D $(@D)/firmware/rk915_fw.bin $(TARGET_DIR)/lib/firmware/rk915_fw.bin
	$(INSTALL) -m 0644 -D $(@D)/firmware/rk915_patch.bin $(TARGET_DIR)/lib/firmware/rk915_patch.bin
endef

$(eval $(kernel-module))
$(eval $(generic-package))
