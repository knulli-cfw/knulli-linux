################################################################################
#
# uboot-a133
#
################################################################################

# One U-Boot for every device: the orangepi BSP tree (v2018.05-h618),
# display-less, extlinux.  The vendor BL31 enters it in AArch32, so it is
# built with the bare-metal ARM toolchain.
UBOOT_A133_VERSION = 66e2615a13f7e2b3ee269fd0ec027db117c493b7
UBOOT_A133_SITE = $(call github,orangepi-xunlong,u-boot-orangepi,$(UBOOT_A133_VERSION))
UBOOT_A133_SOURCE = u-boot-orangepi-$(UBOOT_A133_VERSION).tar.gz
UBOOT_A133_DL_SUBDIR = u-boot-orangepi
UBOOT_A133_LICENSE = GPL-2.0+
UBOOT_A133_DEPENDENCIES = host-arm-gnu-toolchain host-dtc host-allwinner-utils

# List of supported A133 devices (vendor boot packages, kept for reference)
UBOOT_A133_DEVICES = trimui-smart-pro trimui-brick trimui-brick-pro powkiddy-v20 powkiddy-v90s magicx-zero-28 magicx-zero-40 xu20-v32

UBOOT_A133_MAKE = $(TARGET_MAKE_ENV) $(MAKE) -C $(@D) O=$(@D)/out ARCH=arm \
	CROSS_COMPILE=$(HOST_DIR)/bin/arm-none-eabi- HOSTCC="$(HOSTCC)"
# the tree predates gcc 13; keep its warnings as warnings
UBOOT_A133_KCFLAGS = -Wno-error -Wno-attributes -Wno-array-bounds \
	-Wno-address-of-packed-member -Wno-int-conversion \
	-Wno-incompatible-pointer-types -Wno-implicit-function-declaration

define UBOOT_A133_COPY_DEVICES
	mkdir -p $(@D)/devices
	$(foreach device,$(UBOOT_A133_DEVICES), \
		cp -r $(UBOOT_A133_PKGDIR)/$(device) $(@D)/devices/; )
endef
UBOOT_A133_POST_EXTRACT_HOOKS += UBOOT_A133_COPY_DEVICES

define UBOOT_A133_CONFIGURE_CMDS
	$(UBOOT_A133_MAKE) sun50iw10p1_defconfig
	$(@D)/scripts/kconfig/merge_config.sh -m -O $(@D)/out $(@D)/out/.config \
		$(UBOOT_A133_PKGDIR)/uboot-a133.config
	$(UBOOT_A133_MAKE) olddefconfig
	for opt in AXP2202_POWER SUNXI_BMU ENV_IS_NOWHERE CMD_PXE CMD_BOOTI HUSH_PARSER SUPPORT_RAW_INITRD USE_BOOTCOMMAND; do \
		grep -q "^CONFIG_$$opt=y" $(@D)/out/.config || { \
			echo "uboot-a133: CONFIG_$$opt did not take" >&2; exit 1; }; \
	done
endef

define UBOOT_A133_BUILD_CMDS
	$(UBOOT_A133_MAKE) KCFLAGS="$(UBOOT_A133_KCFLAGS)" u-boot.bin
	# padded to the vendor's 0xc0000 with boot0's header
	python3 $(BR2_EXTERNAL_KNULLI_PATH)/package/boot/uboot-h700/uboot-head.py \
		$(@D)/out/u-boot.bin $(@D)/u-boot-a133.bin 0xc0000
	# Build DTB and boot_package.fex for each device
	$(foreach device,$(UBOOT_A133_DEVICES), \
		echo "Building boot_package.fex for $(device)..."; \
		$(HOST_DIR)/bin/dtc -I dts -O dtb \
			-o $(@D)/devices/$(device)/boot_package/dtb.bin \
			$(@D)/devices/$(device)/boot_package/$(device).dts || exit 1; \
		cd $(@D)/devices/$(device)/boot_package/ && \
		$(HOST_DIR)/bin/dragonsecboot -pack boot_package.cfg || exit 1; \
	)
endef

# board/allwinner/a133/create-boot-script.sh packs u-boot-a133.bin with the
# vendor monitor, scp and dtb
define UBOOT_A133_INSTALL_IMAGES_CMDS
	$(INSTALL) -m 0644 -D $(@D)/u-boot-a133.bin $(BINARIES_DIR)/u-boot-a133.bin
	mkdir -p $(BINARIES_DIR)/a133-boot-packages
	$(foreach device,$(UBOOT_A133_DEVICES), \
		cp $(@D)/devices/$(device)/boot_package/boot_package.fex \
			$(BINARIES_DIR)/a133-boot-packages/$(device)_boot_package.fex; )
endef

UBOOT_A133_INSTALL_TARGET = NO
UBOOT_A133_INSTALL_IMAGES = YES

$(eval $(generic-package))
