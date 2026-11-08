################################################################################
#
# uboot-t618  --  vendor U-Boot for Unisoc UMS512 / T618
#
################################################################################

UBOOT_T618_VERSION = 34afab15d051a89ebfc4d2dd1c8cda8e1ce56ea9
UBOOT_T618_SITE = https://github.com/beebono/u-boot-ums512.git
UBOOT_T618_SITE_METHOD = git
UBOOT_T618_LICENSE = GPL-2.0+
UBOOT_T618_LICENSE_FILES = Licenses/gpl-2.0.txt
UBOOT_T618_DEPENDENCIES = host-python3

UBOOT_T618_PKGDIR = $(BR2_EXTERNAL_KNULLI_PATH)/package/boot/uboot-t618

UBOOT_T618_DEFCONFIG = ums512_rg_rotate_defconfig
UBOOT_T618_DEVICE_TREE = ums512_rg_rotate

# U-Boot 2015.07 against gcc 14 requires some additional error checks to be disabled 
UBOOT_T618_KCFLAGS = \
	-Wno-error=implicit-function-declaration \
	-Wno-error=implicit-int \
	-Wno-error=int-conversion \
	-Wno-error=incompatible-pointer-types \
	-Wno-error=return-mismatch \
	-Wno-error=declaration-missing-parameter-type

# ARCH=arm, not arm64: the vendor BSP predates the rename and its Makefile keys
# off the 32-bit name even for this aarch64 SoC.
UBOOT_T618_MAKE_OPTS = \
	ARCH=arm \
	DEVICE_TREE=$(UBOOT_T618_DEVICE_TREE) \
	CROSS_COMPILE=$(TARGET_CROSS) \
	KCFLAGS="$(UBOOT_T618_KCFLAGS)" \
	O=$(@D)/build

define UBOOT_T618_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(UBOOT_T618_MAKE_OPTS) $(UBOOT_T618_DEFCONFIG)
	$(TARGET_MAKE_ENV) $(MAKE) -j$(PARALLEL_JOBS) -C $(@D) $(UBOOT_T618_MAKE_OPTS) u-boot-dtb.bin
endef

# The SoC boots a DHTB/SIMGHDR-wrapped image, and the wrapper is signed.  The
# payload area of a known-good stock image is replaced with ours and the hashes
# refreshed, which is what pack_unisoc_uboot.py does -- building a bootable
# wrapper from scratch is not possible without the vendor keys.
define UBOOT_T618_INSTALL_IMAGES_CMDS
	$(HOST_DIR)/bin/python3 $(UBOOT_T618_PKGDIR)/pack_unisoc_uboot.py \
		$(UBOOT_T618_PKGDIR)/uboot_stock.img \
		$(@D)/build/u-boot-dtb.bin \
		$(BINARIES_DIR)/u-boot.img
endef

# This package produces an image, not a target or staging payload.
UBOOT_T618_INSTALL_TARGET = NO
UBOOT_T618_INSTALL_STAGING = NO
UBOOT_T618_INSTALL_IMAGES = YES

$(eval $(generic-package))
