################################################################################
#
# uboot-rk3326  --  vendor U-Boot for Rockchip RK3326 / PX30
#
################################################################################

# Pin a commit once the branch is pushed; a branch name builds but is not
# reproducible.
UBOOT_RK3326_VERSION = knulli-rk3326
UBOOT_RK3326_SITE = https://github.com/knulli-cfw/rk3326-u-boot.git
UBOOT_RK3326_SITE_METHOD = git
UBOOT_RK3326_LICENSE = GPL-2.0+
UBOOT_RK3326_LICENSE_FILES = Licenses/gpl-2.0.txt

UBOOT_RK3326_PKGDIR = $(BR2_EXTERNAL_KNULLI_PATH)/package/boot/uboot-rk3326

# U-Boot 2017.09.  Buildroot's gcc 14 does not build a vendor tree of this
# vintage, so this package uses the pinned Linaro 6.3.1 the BSP was written
# against -- the same arrangement uboot-rk3566 uses.
#
# rkbin is vendored in the tree under tools/rk_tools (make.sh switches
# RKBIN_TOOLS to it for the odroidgoa board), so unlike uboot-rk3566 this
# package does not depend on rockchip-rkbin.  It matters: make.sh hardcodes
# rk3326_ddr_333MHz_v1.10.bin and rk3326_miniloader_v1.12.bin, and the current
# rockchip-rkbin carries v2.11 and v1.40 instead.
UBOOT_RK3326_DEPENDENCIES = host-toolchain-optional-linaro-aarch64

# One image for every RK3326 device.  SARADC channel 0 selects the device in
# cmd/hwrev.c, which sets dtb_uboot (the DTB U-Boot uses for its own display
# init) and dtb_kernel (the DTB handed to Linux), so the board is not fixed at
# build time: ODROID-GO2 v1.0/v1.1, GO3, R36S/RGB20S, Retro Pixel Pocket,
# GKD Pixel2, XF40H, BatlExp G350 and RG351V.
UBOOT_RK3326_BOARD = odroidgoa

# make.sh resolves the toolchain itself from a path relative to the source dir
# and ignores CROSS_COMPILE from the environment -- select_toolchain() reads
# TOOLCHAIN_ARM64 and exits "Can't find toolchain" if it is absent.  So the
# directory it expects is linked into place rather than passed in.
UBOOT_RK3326_LINARO_DIR = \
	$(@D)/../prebuilts/gcc/linux-x86/aarch64/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu

define UBOOT_RK3326_LINK_TOOLCHAIN
	mkdir -p $(dir $(UBOOT_RK3326_LINARO_DIR))
	rm -rf $(UBOOT_RK3326_LINARO_DIR)
	ln -sf $(HOST_DIR)/lib/gcc-linaro-aarch64-linux-gnu $(UBOOT_RK3326_LINARO_DIR)
endef

define UBOOT_RK3326_BUILD_CMDS
	$(UBOOT_RK3326_LINK_TOOLCHAIN)
	cd $(@D) && $(TARGET_MAKE_ENV) ./make.sh $(UBOOT_RK3326_BOARD)
endef

# make.sh leaves all three images in sd_fuse/.  They go in a package subdir of
# BINARIES_DIR rather than its root, where the batocera uboot-odroid-goa package
# puts files of the same name: the two must not collide while both exist.
# Consuming genimage.cfg files therefore reference ../../uboot-rk3326/<file>.
define UBOOT_RK3326_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0644 $(@D)/sd_fuse/idbloader.img \
		$(BINARIES_DIR)/uboot-rk3326/idbloader.img
	$(INSTALL) -D -m 0644 $(@D)/sd_fuse/uboot.img \
		$(BINARIES_DIR)/uboot-rk3326/uboot.img
	$(INSTALL) -D -m 0644 $(@D)/sd_fuse/trust.img \
		$(BINARIES_DIR)/uboot-rk3326/trust.img
endef

# This package produces an image, not a target or staging payload.  INSTALL_IMAGES
# must be YES or pkg-generic.mk defaults it to NO and the step above is simply
# never run -- the build succeeds, leaves no uboot.img, and the failure only
# surfaces at genimage time.
UBOOT_RK3326_INSTALL_TARGET = NO
UBOOT_RK3326_INSTALL_STAGING = NO
UBOOT_RK3326_INSTALL_IMAGES = YES

$(eval $(generic-package))
