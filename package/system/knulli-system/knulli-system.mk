################################################################################
#
# knulli.linux System
#
################################################################################

KNULLI_SYSTEM_SOURCE=

KNULLI_SYSTEM_VERSION = devel
KNULLI_SYSTEM_DATE_TIME = $(shell date "+%Y/%m/%d %H:%M")
KNULLI_SYSTEM_DATE = $(shell date "+%Y/%m/%d")
KNULLI_SYSTEM_DEPENDENCIES = tzdata

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2837),y)
	KNULLI_SYSTEM_ARCH=bcm2837
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3399),y)
	KNULLI_SYSTEM_ARCH=rk3399
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3288),y)
	KNULLI_SYSTEM_ARCH=rk3288
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3328),y)
	KNULLI_SYSTEM_ARCH=rk3328
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3568),y)
	KNULLI_SYSTEM_ARCH=rk3568
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H3),y)
	KNULLI_SYSTEM_ARCH=h3
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H5),y)
	KNULLI_SYSTEM_ARCH=h5
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H6),y)
	KNULLI_SYSTEM_ARCH=h6
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H616),y)
	KNULLI_SYSTEM_ARCH=h616
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H700),y)
	KNULLI_SYSTEM_ARCH=h700
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_A133),y)
	KNULLI_SYSTEM_ARCH=a133
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_ATM7039),y)
	KNULLI_SYSTEM_ARCH=atm7039
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S812),y)
	KNULLI_SYSTEM_ARCH=s812
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S922X),y)
	KNULLI_SYSTEM_ARCH=s922x
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3326),y)
	KNULLI_SYSTEM_ARCH=rk3326
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3128),y)
	KNULLI_SYSTEM_ARCH=rk3128
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_XU4),y)
	KNULLI_SYSTEM_ARCH=odroidxu4
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S905),y)
	KNULLI_SYSTEM_ARCH=s905
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S905GEN2),y)
	KNULLI_SYSTEM_ARCH=s905gen2
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S905GEN3),y)
	KNULLI_SYSTEM_ARCH=s905gen3
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_X86),y)
	KNULLI_SYSTEM_ARCH=x86
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_X86_64),y)
	KNULLI_SYSTEM_ARCH=x86_64
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_STEAMDECK),y)
	KNULLI_SYSTEM_ARCH=steamdeck
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_ZEN3),y)
	KNULLI_SYSTEM_ARCH=x86-64-v3
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2836),y)
	KNULLI_SYSTEM_ARCH=bcm2836
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2835),y)
	KNULLI_SYSTEM_ARCH=bcm2835
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2711),y)
	KNULLI_SYSTEM_ARCH=bcm2711
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2712),y)
	KNULLI_SYSTEM_ARCH=bcm2712
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_A3GEN2),y)
	KNULLI_SYSTEM_ARCH=a3gen2
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_ODIN),y)
	KNULLI_SYSTEM_ARCH=odin
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3588),y)
	KNULLI_SYSTEM_ARCH=rk3588
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RISCV),y)
	KNULLI_SYSTEM_ARCH=riscv
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM4450),y)
	KNULLI_SYSTEM_ARCH=sm4450
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM6115),y)
	KNULLI_SYSTEM_ARCH=sm6115
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM8250),y)
	KNULLI_SYSTEM_ARCH=sm8250
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM8550),y)
	KNULLI_SYSTEM_ARCH=sm8550
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SMGEN),y)
	KNULLI_SYSTEM_ARCH=smgen
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_T527),y)
	KNULLI_SYSTEM_ARCH=a527
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3576),y)
        KNULLI_SYSTEM_ARCH=rk3576
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_T618),y)
	KNULLI_SYSTEM_ARCH=t618
else
	KNULLI_SYSTEM_ARCH=unknown
endif

ifneq (,$(findstring dev,$(KNULLI_SYSTEM_VERSION)))
    KNULLI_SYSTEM_COMMIT = \
	    "-$(shell cd $(BR2_EXTERNAL_KNULLI_PATH) && git rev-parse --short HEAD)"
else
    KNULLI_SYSTEM_COMMIT =
endif

define KNULLI_SYSTEM_INSTALL_TARGET_CMDS

	# version/arch
	mkdir -p $(TARGET_DIR)/usr/share/knulli
	echo -n "$(KNULLI_SYSTEM_ARCH)" > $(TARGET_DIR)/usr/share/knulli/knulli.arch
	echo $(KNULLI_SYSTEM_VERSION)$(KNULLI_SYSTEM_COMMIT) \
	    $(KNULLI_SYSTEM_DATE_TIME) > \
		$(TARGET_DIR)/usr/share/knulli/knulli.version

	# datainit
	mkdir -p $(TARGET_DIR)/usr/share/knulli/datainit/system
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-system/knulli.conf \
	    $(TARGET_DIR)/usr/share/knulli/datainit/system

	# knulli-boot.conf
	$(INSTALL) -D -m 0644 \
	    $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-system/knulli-boot.conf \
		$(BINARIES_DIR)/knulli-boot.conf

	# sysconfigs (default knulli.conf for boards)
	mkdir -p $(TARGET_DIR)/usr/share/knulli/sysconfigs
    if test -d \
	    $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-system/sysconfigs/${KNULLI_SYSTEM_ARCH}; \
		then cp -pr \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-system/sysconfigs/${KNULLI_SYSTEM_ARCH}/* \
		$(TARGET_DIR)/usr/share/knulli/sysconfigs; fi

	# mounts
	mkdir -p $(TARGET_DIR)/boot $(TARGET_DIR)/overlay $(TARGET_DIR)/userdata

	# variables
	mkdir -p $(TARGET_DIR)/etc/profile.d
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-system/xdg.sh \
	    $(TARGET_DIR)/etc/profile.d/xdg.sh
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-system/dbus.sh \
	    $(TARGET_DIR)/etc/profile.d/dbus.sh

	# list of modules that doesnt like suspend
	mkdir -p $(TARGET_DIR)/etc/pm/config.d
	echo 'SUSPEND_MODULES="rtw88_8822ce snd_pci_acp5x"' > $(TARGET_DIR)/etc/pm/config.d/config
endef

$(eval $(generic-package))
