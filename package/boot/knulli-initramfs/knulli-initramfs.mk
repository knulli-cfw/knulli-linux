################################################################################
#
# knulli-initramfs
#
################################################################################

KNULLI_INITRAMFS_VERSION = 1.36.1
KNULLI_INITRAMFS_SITE = http://www.busybox.net/downloads
KNULLI_INITRAMFS_SOURCE = busybox-$(KNULLI_INITRAMFS_VERSION).tar.bz2
KNULLI_INITRAMFS_LICENSE = GPLv2
KNULLI_INITRAMFS_LICENSE_FILES = LICENSE

KNULLI_INITRAMFS_DEPENDENCIES += host-uboot-tools libxcrypt
KNULLI_INITRAMFS_CFLAGS = $(TARGET_CFLAGS)
KNULLI_INITRAMFS_LDFLAGS = $(TARGET_LDFLAGS)

KNULLI_INITRAMFS_KCONFIG_FILE = \
    $(BR2_EXTERNAL_KNULLI_PATH)/package/boot/knulli-initramfs/busybox.config

INITRAMFS_DIR=$(BINARIES_DIR)/initramfs

# Allows the build system to tweak CFLAGS
KNULLI_INITRAMFS_MAKE_ENV = \
	$(TARGET_MAKE_ENV) \
	CFLAGS="$(KNULLI_INITRAMFS_CFLAGS)"
KNULLI_INITRAMFS_MAKE_OPTS = \
	CC="$(TARGET_CC)" \
	ARCH=$(KERNEL_ARCH) \
	PREFIX="$(INITRAMFS_DIR)" \
	EXTRA_LDFLAGS="$(KNULLI_INITRAMFS_LDFLAGS)" \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	CONFIG_PREFIX="$(INITRAMFS_DIR)" \
	SKIP_STRIP=n

KNULLI_INITRAMFS_KCONFIG_OPTS = $(KNULLI_INITRAMFS_MAKE_OPTS)

define KNULLI_INITRAMFS_BUILD_CMDS
	$(KNULLI_INITRAMFS_MAKE_ENV) $(MAKE) $(KNULLI_INITRAMFS_MAKE_OPTS) -C $(@D)
endef

ifeq ($(BR2_aarch64)$(BR2_TOOLCHAIN_OPTIONAL_LINARO_AARCH64),y)
KNULLI_INITRAMFS_INITRDA=arm64
else
KNULLI_INITRAMFS_INITRDA=arm
endif

# allwinner t527 u-boot workaround
ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_T527),y)
BATOCERA_INITRAMFS_INITRDA=arm
endif

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM4450),y)
KNULLI_INITRAMFS_DEPENDENCIES += alllinuxfirmwares
define KNULLI_INITRAMFS_SM4450_EARLY_FIRMWARE
	mkdir -p $(INITRAMFS_DIR)/lib/firmware/qcom/sm4450
	cp $(ALLLINUXFIRMWARES_DIR)/qcom/a630_sqe.fw \
		$(INITRAMFS_DIR)/lib/firmware/qcom/
	cp $(BR2_EXTERNAL_KNULLI_PATH)/board/qualcomm/sm4450/fsoverlay/lib/firmware/qcom/sm4450/a613_zap.mbn \
		$(INITRAMFS_DIR)/lib/firmware/qcom/sm4450/
endef
KNULLI_INITRAMFS_PRE_INSTALL_TARGET_HOOKS += KNULLI_INITRAMFS_SM4450_EARLY_FIRMWARE
endif

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM6115),y)
KNULLI_INITRAMFS_DEPENDENCIES += alllinuxfirmwares
define KNULLI_INITRAMFS_SM6115_EARLY_FIRMWARE
	mkdir -p $(INITRAMFS_DIR)/lib/firmware/qcom/qrb4210
	cp $(ALLLINUXFIRMWARES_DIR)/qcom/a630_sqe.fw \
		$(INITRAMFS_DIR)/lib/firmware/qcom/
	cp -R $(ALLLINUXFIRMWARES_DIR)/qcom/qrb4210/* \
		$(INITRAMFS_DIR)/lib/firmware/qcom/qrb4210/
endef
KNULLI_INITRAMFS_PRE_INSTALL_TARGET_HOOKS += KNULLI_INITRAMFS_SM6115_EARLY_FIRMWARE
endif

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM8250),y)
KNULLI_INITRAMFS_DEPENDENCIES += alllinuxfirmwares
define KNULLI_INITRAMFS_SM8250_EARLY_FIRMWARE
	mkdir -p $(INITRAMFS_DIR)/lib/firmware/qcom/sm8250/
	cp -R $(ALLLINUXFIRMWARES_DIR)/qcom/sm8250/* \
		$(INITRAMFS_DIR)/lib/firmware/qcom/sm8250/
	mv $(INITRAMFS_DIR)/lib/firmware/qcom/sm8250/Thundercomm/RB5/* \
		$(INITRAMFS_DIR)/lib/firmware/qcom/sm8250/
	rm -rf $(INITRAMFS_DIR)/lib/firmware/qcom/sm8250/Thundercomm
	cp $(ALLLINUXFIRMWARES_DIR)/qcom/a650_sqe.fw \
		$(INITRAMFS_DIR)/lib/firmware/qcom/
endef
KNULLI_INITRAMFS_PRE_INSTALL_TARGET_HOOKS += KNULLI_INITRAMFS_SM8250_EARLY_FIRMWARE
endif

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM8550),y)
KNULLI_INITRAMFS_DEPENDENCIES += firmware-armbian
define KNULLI_INITRAMFS_SM8550_EARLY_FIRMWARE
    mkdir -p $(INITRAMFS_DIR)/lib/firmware/qcom/sm8550/
    cp -R $(FIRMWARE_ARMBIAN_DIR)/qcom/sm8550/* \
        $(INITRAMFS_DIR)/lib/firmware/qcom/sm8550/
endef
KNULLI_INITRAMFS_PRE_INSTALL_TARGET_HOOKS += KNULLI_INITRAMFS_SM8550_EARLY_FIRMWARE
endif

# SMGEN: one initrd for every SM board, so only what the built-in GPU driver
# needs before the rootfs is up (SQE/GMU microcode and the zap shader); the
# rest of the firmware comes from the rootfs.
ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SMGEN),y)
KNULLI_INITRAMFS_DEPENDENCIES += alllinuxfirmwares
define KNULLI_INITRAMFS_SMGEN_EARLY_FIRMWARE
	mkdir -p $(INITRAMFS_DIR)/lib/firmware/qcom/sm8250 \
		$(INITRAMFS_DIR)/lib/firmware/qcom/sm8550 \
		$(INITRAMFS_DIR)/lib/firmware/qcom/sm4450
	cp $(ALLLINUXFIRMWARES_DIR)/qcom/a650_sqe.fw $(ALLLINUXFIRMWARES_DIR)/qcom/a650_gmu.bin \
		$(ALLLINUXFIRMWARES_DIR)/qcom/a740_sqe.fw $(ALLLINUXFIRMWARES_DIR)/qcom/gmu_gen70200.bin \
		$(ALLLINUXFIRMWARES_DIR)/qcom/a630_sqe.fw $(ALLLINUXFIRMWARES_DIR)/qcom/a630_gmu.bin \
		$(INITRAMFS_DIR)/lib/firmware/qcom/
	cp $(ALLLINUXFIRMWARES_DIR)/qcom/sm8250/a650_zap.mbn $(INITRAMFS_DIR)/lib/firmware/qcom/sm8250/
	cp $(ALLLINUXFIRMWARES_DIR)/qcom/sm8550/a740_zap.mbn $(INITRAMFS_DIR)/lib/firmware/qcom/sm8550/
	cp $(BR2_EXTERNAL_KNULLI_PATH)/board/qualcomm/smgen/fsoverlay/lib/firmware/qcom/sm4450/a613_zap.mbn \
		$(INITRAMFS_DIR)/lib/firmware/qcom/sm4450/
	cp $(BR2_EXTERNAL_KNULLI_PATH)/board/qualcomm/smgen/fsoverlay/lib/firmware/qcom/a710_sqe.fw \
		$(BR2_EXTERNAL_KNULLI_PATH)/board/qualcomm/smgen/fsoverlay/lib/firmware/qcom/sm6450/TG4070/a710_zap.mbn \
		$(BR2_EXTERNAL_KNULLI_PATH)/board/qualcomm/smgen/fsoverlay/lib/firmware/qcom/gmu_gen70000.bin \
		$(INITRAMFS_DIR)/lib/firmware/qcom/
endef
KNULLI_INITRAMFS_PRE_INSTALL_TARGET_HOOKS += KNULLI_INITRAMFS_SMGEN_EARLY_FIRMWARE
endif

define KNULLI_INITRAMFS_INSTALL_TARGET_CMDS
	mkdir -p $(INITRAMFS_DIR)
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/boot/knulli-initramfs/init \
	    $(INITRAMFS_DIR)/init
	$(KNULLI_INITRAMFS_MAKE_ENV) $(MAKE) $(KNULLI_INITRAMFS_MAKE_OPTS) -C $(@D) install
	(cd $(INITRAMFS_DIR) && find . | cpio -H newc -o > $(BINARIES_DIR)/initrd)
	(cd $(BINARIES_DIR) && mkimage -A $(KNULLI_INITRAMFS_INITRDA) \
	    -O linux -T ramdisk -C none -a 0 -e 0 -n initrd -d ./initrd ./uInitrd)
	$(COMPRESSION_TYPE_COMMAND)
endef

$(eval $(kconfig-package))
