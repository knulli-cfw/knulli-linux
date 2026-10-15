################################################################################
#
# rtl8733bu - Realtek RTL8733BU USB WiFi out-of-tree vendor driver
#
# Used by the Miyoo Flip (USB combo chip 0bda:b733 / 0bda:f72b). The WiFi side
# is NOT in mainline nor in our rockchip BSP (only rkwifi/bcmdhd is vendored
# there); the BT side is handled by in-tree btusb. Source is taken from the
# GammaOS BSP kernel tree (supports up to kernel 6.9, builds clean against 6.1).
# cfg80211/nl80211 mode is the driver default (drv_conf.h defines
# CONFIG_IOCTL_CFG80211) -> registers a proper wiphy, works with connman.
#
################################################################################

RTL8733BU_VERSION = 49f8481f6da77183972a07df248d14db0c485316
RTL8733BU_SITE = $(call github,knulli-cfw,rtl8733bu,$(RTL8733BU_VERSION))
RTL8733BU_LICENSE = GPL-2.0
RTL8733BU_LICENSE_FILES = LICENSE
RTL8733BU_DEPENDENCIES = linux

RTL8733BU_USER_EXTRA_CFLAGS = \
	-DCONFIG_$(call qstrip,$(BR2_ENDIAN))_ENDIAN \
	-DCONFIG_IOCTL_CFG80211 \
	-DRTW_USE_CFG80211_STA_EVENT \
	-Wno-error

# The driver Makefile has CONFIG_RTL8733B=y (-> MODULE_NAME=8733bu) but only sets
# CONFIG_RTL8733BU=m in its host-make branch (the "else" of ifneq KERNELRELEASE),
# which runs modules via a recursive -C $(KSRC) M=. that then sees the exported
# flag. Buildroot's kernel-module infra invokes Kbuild DIRECTLY, so that host
# branch never runs and CONFIG_RTL8733BU is empty in the Kbuild pass -> the tail
# "obj-$(CONFIG_RTL8733BU) := 8733bu.o" becomes "obj- :=" and NOTHING builds
# (empty Module.symvers, no .ko). So pass CONFIG_RTL8733BU=m into Kbuild ourselves.
RTL8733BU_MODULE_MAKE_OPTS = \
	CONFIG_RTL8733BU=m \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR) \
	USER_EXTRA_CFLAGS="$(RTL8733BU_USER_EXTRA_CFLAGS)"

define RTL8733BU_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB)
endef

$(eval $(kernel-module))
$(eval $(generic-package))
