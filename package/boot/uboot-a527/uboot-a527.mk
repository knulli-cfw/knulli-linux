################################################################################
#
# uboot-a527
#
# Allwinner brandy-2.0 U-Boot 2018.07 for the A527/T527 (sun55iw3p1), 32-bit.
# Source: Allwinner Tina AIOT aiot-linux-v1.4.6 as mirrored by radxa, the tree
# the TrimUI SDK ships.  The board U-Boot dts is compiled into U-Boot, so it is
# built once per device.
#
################################################################################

UBOOT_A527_VERSION = 04a6e48aac8db8384ed8bd800cc813d03df1e48a
UBOOT_A527_SITE = $(call github,radxa,u-boot,$(UBOOT_A527_VERSION))
UBOOT_A527_SOURCE = u-boot-$(UBOOT_A527_VERSION).tar.gz
UBOOT_A527_LICENSE = GPL-2.0+
UBOOT_A527_DEPENDENCIES = host-arm-gnu-toolchain host-dtc host-allwinner-utils

UBOOT_A527_DEVICES = trimui-smart-pro-s

# in-tree: the sunxi_challenge.c rule does not work with O=.  DTS_PATH
# defaults to $(PWD)/arch/arm/dts, and make -C leaves PWD at the caller's.
UBOOT_A527_MAKE = $(TARGET_MAKE_ENV) $(MAKE) -C $(@D) ARCH=arm \
	CROSS_COMPILE=$(HOST_DIR)/bin/arm-none-eabi- HOSTCC="$(HOSTCC)" \
	DTS_PATH=$(@D)/arch/arm/dts

UBOOT_A527_KCFLAGS = -Wno-error -Wno-attributes -Wno-array-bounds \
	-Wno-address-of-packed-member -Wno-int-conversion \
	-Wno-incompatible-pointer-types -Wno-implicit-function-declaration

define UBOOT_A527_CONFIGURE_CMDS
	$(UBOOT_A527_MAKE) sun55iw3p1_defconfig
	$(@D)/scripts/kconfig/merge_config.sh -m -O $(@D) $(@D)/.config \
		$(UBOOT_A527_PKGDIR)/uboot-a527.config
	$(UBOOT_A527_MAKE) olddefconfig
endef

# LICHEE_BOARD_CONFIG_DIR/uboot-board.dts becomes arch/arm/dts/.board-uboot.dts
define UBOOT_A527_BUILD_CMDS
	$(foreach device,$(UBOOT_A527_DEVICES), \
		rm -f $(@D)/dts/dt.dtb $(@D)/u-boot*.bin; \
		$(UBOOT_A527_MAKE) KCFLAGS="$(UBOOT_A527_KCFLAGS)" \
			LICHEE_BOARD_CONFIG_DIR=$(UBOOT_A527_PKGDIR)/$(device) \
			u-boot.bin || exit 1; \
		rm -rf $(@D)/devices/$(device); \
		mkdir -p $(@D)/devices/$(device); \
		cp $(UBOOT_A527_PKGDIR)/$(device)/boot_package/boot_package.cfg \
			$(UBOOT_A527_PKGDIR)/$(device)/boot_package/monitor.bin \
			$(UBOOT_A527_PKGDIR)/$(device)/boot_package/scp.bin \
			$(@D)/devices/$(device)/ || exit 1; \
		cp $(@D)/u-boot.bin $(@D)/devices/$(device)/u-boot.bin || exit 1; \
		$(HOST_DIR)/bin/dtc -I dts -O dtb \
			-o $(@D)/devices/$(device)/dtb.bin \
			$(UBOOT_A527_PKGDIR)/$(device)/boot_package/$(device).dts || exit 1; \
		(cd $(@D)/devices/$(device) && \
			$(HOST_DIR)/bin/dragonsecboot -pack boot_package.cfg) || exit 1; \
	)
endef

define UBOOT_A527_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/a527-boot-packages
	$(foreach device,$(UBOOT_A527_DEVICES), \
		cp $(@D)/devices/$(device)/boot_package.fex \
			$(BINARIES_DIR)/a527-boot-packages/$(device)_boot_package.fex; )
endef

UBOOT_A527_INSTALL_TARGET = NO
UBOOT_A527_INSTALL_IMAGES = YES

$(eval $(generic-package))
