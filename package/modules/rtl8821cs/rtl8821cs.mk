################################################################################
#
# rtl8821cs - Realtek RTL8821CS SDIO WiFi vendor driver
#
# The Anbernic H700 devices carry an RTL8821CS on SMHC1.  The orangepi 5.4
# tree has no driver for it (rtw88 gained 8821cs SDIO only in 6.4), so this is
# the v5.12.0 vendor driver from the rockchip 5.10 BSP, with the sunxi
# platform glue rewritten for the 5.4 sunxi-rf API (sunxi_wlan_set_power +
# sunxi_mmc_rescan_card).  The BT half goes through uart1 and rtk_hciattach.
#
################################################################################

RTL8821CS_VERSION = 865b035230554f9009fc9733f2019e69004ba1c5
RTL8821CS_SITE = $(call github,knulli-cfw,rtl8821cs,$(RTL8821CS_VERSION))
RTL8821CS_LICENSE = GPL-2.0
RTL8821CS_DEPENDENCIES = linux

RTL8821CS_USER_EXTRA_CFLAGS = \
	-Wno-error \
	-Wno-error=implicit-function-declaration -Wno-error=implicit-int \
	-Wno-error=int-conversion -Wno-error=incompatible-pointer-types \
	-Wno-error=return-mismatch -Wno-error=declaration-missing-parameter-type

# The driver Makefile picks the platform block from CONFIG_PLATFORM_* variables
# it sets itself (RK3188 on by default) and only exports CONFIG_RTL8821CS=m
# from its host-make branch, which buildroot's direct Kbuild call skips, so all
# of them go in on the command line.
RTL8821CS_MODULE_MAKE_OPTS = \
	CONFIG_RTL8821CS=m \
	CONFIG_PLATFORM_ARM_RK3188=n \
	CONFIG_PLATFORM_ARM_SUNxI=y \
	MODULE_NAME=8821cs \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR) \
	USER_EXTRA_CFLAGS="$(RTL8821CS_USER_EXTRA_CFLAGS)"

define RTL8821CS_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211)
	$(call KCONFIG_ENABLE_OPT,CONFIG_SUNXI_RFKILL)
endef

$(eval $(kernel-module))
$(eval $(generic-package))
