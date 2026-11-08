################################################################################
#
# uboot-rk3566  --  vendor U-Boot for Rockchip RK3566 / RK3568
#
################################################################################

UBOOT_RK3566_VERSION = f4d7c92086842531a1e3bf0491f46bb6dad02d09
UBOOT_RK3566_SITE = https://github.com/knulli-cfw/rk356x-uboot.git
UBOOT_RK3566_SITE_METHOD = git
UBOOT_RK3566_LICENSE = GPL-2.0+
UBOOT_RK3566_LICENSE_FILES = Licenses/gpl-2.0.txt

UBOOT_RK3566_PKGDIR = $(BR2_EXTERNAL_KNULLI_PATH)/package/boot/uboot-rk3566

# make.sh needs rkbin for the loader/trust ini files and its own mkimage, and
# rockchip-rkbin is the package that provides that checkout.
UBOOT_RK3566_DEPENDENCIES = rockchip-rkbin host-toolchain-optional-linaro-aarch64

# U-Boot 2017.09.  Buildroot's gcc 14 does not build a vendor tree of this
# vintage, so this package uses the pinned Linaro 6.3.1 the BSP was written
# against -- the same arrangement atm7039 uses for its 32-bit BSP.

# The board is selected by a make.sh config fragment, not a defconfig: the
# fragment names CONFIG_BASE_DEFCONFIG (rk3568_defconfig), the device tree,
# CONFIG_OF_LIST (the dtb mkimage packs into the FIT) and CONFIG_LOADER_INI
# (RK3566MINIALL.ini, resolved inside rkbin).
#
# One image for every RK3566 device: U-Boot adopts the per-device kernel dtb at
# runtime via init_kernel_dtb(), so the board is not fixed at build time.
UBOOT_RK3566_BOARD = rk3566-generic

# make.sh resolves both of these itself from paths relative to the source dir,
# and ignores CROSS_COMPILE from the environment -- select_toolchain() reads
# TOOLCHAIN_ARM64 and exits "ERROR: No toolchain" if it is absent.  So the two
# directories it expects are linked into place rather than passed in.
UBOOT_RK3566_LINARO_DIR = \
	$(@D)/../prebuilts/gcc/linux-x86/aarch64/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu

define UBOOT_RK3566_LINK_DEPS
	rm -rf $(@D)/../rkbin
	ln -sf $(ROCKCHIP_RKBIN_DIR) $(@D)/../rkbin
	mkdir -p $(dir $(UBOOT_RK3566_LINARO_DIR))
	rm -rf $(UBOOT_RK3566_LINARO_DIR)
	ln -sf $(HOST_DIR)/lib/gcc-linaro-aarch64-linux-gnu $(UBOOT_RK3566_LINARO_DIR)
endef

define UBOOT_RK3566_BUILD_CMDS
	$(UBOOT_RK3566_LINK_DEPS)
	cd $(@D) && $(TARGET_MAKE_ENV) ./make.sh $(UBOOT_RK3566_BOARD)
endef

# uboot.img is what make.sh emits; the image expects it under
# BINARIES_DIR/uboot-rk3566/ where genimage.cfg looks for it.
#
# idbloader.img is still a prebuilt blob: make.sh only builds one in a
# commented-out sd_boot path, so there is nothing to compile it from yet.
define UBOOT_RK3566_INSTALL_IMAGES_CMDS
	mkdir -p $(BINARIES_DIR)/uboot-rk3566
	$(INSTALL) -D -m 0644 $(@D)/uboot.img \
		$(BINARIES_DIR)/uboot-rk3566/u-boot-rk3566.bin
	$(INSTALL) -D -m 0644 $(UBOOT_RK3566_PKGDIR)/idbloader.img \
		$(BINARIES_DIR)/uboot-rk3566/idbloader.img
	$(INSTALL) -D -m 0644 $(UBOOT_RK3566_PKGDIR)/resource.img \
		$(BINARIES_DIR)/uboot-rk3566/resource.img
endef

# This package produces an image, not a target or staging payload.  INSTALL_IMAGES
# must be YES or pkg-generic.mk defaults it to NO and the step above is simply
# never run -- the build succeeds, leaves no u-boot-rk3566.bin, and the failure
# only surfaces at genimage time.  Same three lines as uboot-t618 and uboot-a133.
UBOOT_RK3566_INSTALL_TARGET = NO
UBOOT_RK3566_INSTALL_STAGING = NO
UBOOT_RK3566_INSTALL_IMAGES = YES

$(eval $(generic-package))
