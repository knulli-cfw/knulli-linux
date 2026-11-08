################################################################################
#
# uboot-h700
#
################################################################################

# One U-Boot for every device: the orangepi BSP tree (v2018.05-h618),
# display-less, extlinux: the kernel drives the panels.  The sun50iw9 U-Boot
# is AArch32, so it is built with the bare-metal ARM toolchain.  The vendor
# per-device binaries stay in <device>/boot_package/u-boot.bin for reference
# (board/allwinner/h700/scripts/vendorseq.py reads them).
UBOOT_H700_VERSION = 66e2615a13f7e2b3ee269fd0ec027db117c493b7
UBOOT_H700_SITE = $(call github,orangepi-xunlong,u-boot-orangepi,$(UBOOT_H700_VERSION))
UBOOT_H700_SOURCE = u-boot-orangepi-$(UBOOT_H700_VERSION).tar.gz
UBOOT_H700_DL_SUBDIR = u-boot-orangepi
UBOOT_H700_LICENSE = GPL-2.0+
UBOOT_H700_DEPENDENCIES = host-arm-gnu-toolchain host-dtc host-allwinner-utils

# Devices on the 5.4 kernel take the DTB the kernel build produced
# (dts/sunxi/sun50i-h700-anbernic-<device>.dts); U-Boot and the kernel share it.
ifeq ($(BR2_LINUX_KERNEL),y)
UBOOT_H700_DEPENDENCIES += linux
endif
UBOOT_H700_KERNEL_DTB = $(BINARIES_DIR)/sun50i-h700-anbernic-$(1).dtb

# List of supported H700 devices
UBOOT_H700_DEVICES = rg-cubexx rg28xx rg34xx rg34xx-sp rg35xx-h rg35xx-plus rg35xx-pro rg35xx-sp rg40xx-h rg40xx-v

UBOOT_H700_MAKE = $(TARGET_MAKE_ENV) $(MAKE) -C $(@D) O=$(@D)/out ARCH=arm \
	CROSS_COMPILE=$(HOST_DIR)/bin/arm-none-eabi- HOSTCC="$(HOSTCC)"
# the tree predates gcc 13; keep its warnings as warnings
UBOOT_H700_KCFLAGS = -Wno-error -Wno-attributes -Wno-array-bounds \
	-Wno-address-of-packed-member -Wno-int-conversion \
	-Wno-incompatible-pointer-types -Wno-implicit-function-declaration

define UBOOT_H700_COPY_DEVICES
	mkdir -p $(@D)/devices
	$(foreach device,$(UBOOT_H700_DEVICES), \
		cp -r $(UBOOT_H700_PKGDIR)/$(device) $(@D)/devices/; )
endef
UBOOT_H700_POST_EXTRACT_HOOKS += UBOOT_H700_COPY_DEVICES

define UBOOT_H700_CONFIGURE_CMDS
	$(UBOOT_H700_MAKE) sun50iw9p1_defconfig
	$(@D)/scripts/kconfig/merge_config.sh -m -O $(@D)/out $(@D)/out/.config \
		$(UBOOT_H700_PKGDIR)/uboot-h700.config
	$(UBOOT_H700_MAKE) olddefconfig
	for opt in AXP2202_POWER SUNXI_BMU ENV_IS_NOWHERE CMD_PXE CMD_BOOTI USE_BOOTCOMMAND SUNXI_DISP_ON_DEMAND LCD_SUPPORT_ANBERNIC_H700; do \
		grep -q "^CONFIG_$$opt=y" $(@D)/out/.config || { \
			echo "uboot-h700: CONFIG_$$opt did not take" >&2; exit 1; }; \
	done
endef

define UBOOT_H700_BUILD_CMDS
	$(UBOOT_H700_MAKE) KCFLAGS="$(UBOOT_H700_KCFLAGS)" u-boot.bin
	# padded and checksummed like the vendor's
	python3 $(UBOOT_H700_PKGDIR)/uboot-head.py \
		$(@D)/out/u-boot.bin $(@D)/u-boot-h700.bin
	# Build DTB and boot_package.fex for each device
	$(foreach device,$(UBOOT_H700_DEVICES), \
		cp $(@D)/u-boot-h700.bin $(@D)/devices/$(device)/boot_package/u-boot.bin || exit 1; \
		if [ -f "$(call UBOOT_H700_KERNEL_DTB,$(device))" ]; then \
			echo "Using the kernel DTB for $(device)..."; \
			cp $(call UBOOT_H700_KERNEL_DTB,$(device)) \
				$(@D)/devices/$(device)/boot_package/dtb.bin || exit 1; \
		else \
			echo "Building DTB for $(device)..."; \
			$(HOST_DIR)/bin/dtc -I dts -O dtb \
				-o $(@D)/devices/$(device)/boot_package/dtb.bin \
				$(@D)/devices/$(device)/boot_package/$(device).dts || exit 1; \
		fi; \
		echo "Building boot_package.fex for $(device)..."; \
		cd $(@D)/devices/$(device)/boot_package/ && \
		$(HOST_DIR)/bin/dragonsecboot -pack boot_package.cfg || exit 1; \
	)
endef

# board/allwinner/h700/create-boot-script.sh repacks u-boot-h700.bin with the
# kernel's DTB on every image build
define UBOOT_H700_INSTALL_IMAGES_CMDS
	$(INSTALL) -m 0644 -D $(@D)/u-boot-h700.bin $(BINARIES_DIR)/u-boot-h700.bin
	mkdir -p $(BINARIES_DIR)/h700-boot-packages
	$(foreach device,$(UBOOT_H700_DEVICES), \
		cp $(@D)/devices/$(device)/boot_package/boot_package.fex \
			$(BINARIES_DIR)/h700-boot-packages/$(device)_boot_package.fex; )
endef

UBOOT_H700_INSTALL_TARGET = NO
UBOOT_H700_INSTALL_IMAGES = YES

$(eval $(generic-package))
