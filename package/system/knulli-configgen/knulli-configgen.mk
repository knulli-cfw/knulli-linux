################################################################################
#
# knulli-configgen
#
################################################################################

KNULLI_CONFIGGEN_VERSION = 1.4
KNULLI_CONFIGGEN_LICENSE = GPL
KNULLI_CONFIGGEN_SOURCE=
KNULLI_CONFIGGEN_SETUP_TYPE = pep517
KNULLI_CONFIGGEN_DEPENDENCIES = \
	host-python-hatchling \
	python-pyyaml \
	python-toml \
	python-evdev \
	python-pyudev \
	python3-configobj \
	python-httplib2 \
	ffmpeg-python \
	python-pillow \
	python-ruamel-yaml
KNULLI_CONFIGGEN_INSTALL_STAGING = YES

KNULLI_CONFIGGEN_DIR = $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen

define KNULLI_CONFIGGEN_EXTRACT_CMDS
    @echo "=== DEBUG EXTRACT ==="
    @echo "KNULLI_CONFIGGEN_DIR = $(KNULLI_CONFIGGEN_DIR)"
    @echo "BR2_EXTERNAL_KNULLI_PATH = $(BR2_EXTERNAL_KNULLI_PATH)"
    @echo "Build directory: $(@D)"
    @echo "Expected source: $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen"
    @ls -la $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/configgen/ || echo "Source directory not found!"
    @echo "====================="
    cp -avf $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/configgen/* $(@D)
    echo "__version__ = '$(KNULLI_CONFIGGEN_VERSION)'" > $(@D)/configgen/__version__.py
endef

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2835),y)
	KNULLI_CONFIGGEN_SYSTEM=bcm2835
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2836),y)
	KNULLI_CONFIGGEN_SYSTEM=bcm2836
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2837),y)
	KNULLI_CONFIGGEN_SYSTEM=bcm2837
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2711),y)
	KNULLI_CONFIGGEN_SYSTEM=bcm2711
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_BCM2712),y)
	KNULLI_CONFIGGEN_SYSTEM=bcm2712
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_XU4),y)
	KNULLI_CONFIGGEN_SYSTEM=odroidxu4
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3288),y)
	KNULLI_CONFIGGEN_SYSTEM=rk3288
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S905),y)
	KNULLI_CONFIGGEN_SYSTEM=s905
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S905GEN2),y)
	KNULLI_CONFIGGEN_SYSTEM=s905gen2
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S905GEN3),y)
	KNULLI_CONFIGGEN_SYSTEM=s905gen3
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S9GEN4),y)
	KNULLI_CONFIGGEN_SYSTEM=s9gen4
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_X86),y)
	KNULLI_CONFIGGEN_SYSTEM=x86
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_X86_64_ANY),y)
	KNULLI_CONFIGGEN_SYSTEM=x86_64
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3399),y)
	KNULLI_CONFIGGEN_SYSTEM=rk3399
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S922X),y)
	KNULLI_CONFIGGEN_SYSTEM=s922x
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_A3GEN2),y)
	KNULLI_CONFIGGEN_SYSTEM=a3gen2
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3328),y)
	KNULLI_CONFIGGEN_SYSTEM=rk3328
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3568),y)
	KNULLI_CONFIGGEN_SYSTEM=rk3566
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3326),y)
	KNULLI_CONFIGGEN_SYSTEM=rk3326
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H3),y)
	KNULLI_CONFIGGEN_SYSTEM=h3
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H5),y)
	KNULLI_CONFIGGEN_SYSTEM=h5
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H616),y)
	KNULLI_CONFIGGEN_SYSTEM=h616
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H700),y)
	KNULLI_CONFIGGEN_SYSTEM=h700
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_A133),y)
	KNULLI_CONFIGGEN_SYSTEM=a133
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_T527),y)
	KNULLI_CONFIGGEN_SYSTEM=t527
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SUNXI_R16),y)
	KNULLI_CONFIGGEN_SYSTEM=r16
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_ATM7039),y)
	KNULLI_CONFIGGEN_SYSTEM=atm7039
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_S812),y)
	KNULLI_CONFIGGEN_SYSTEM=s812
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3128),y)
	KNULLI_CONFIGGEN_SYSTEM=rk3128
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_ODIN),y)
	KNULLI_CONFIGGEN_SYSTEM=odin
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H6),y)
	KNULLI_CONFIGGEN_SYSTEM=h6
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3588),y)
	KNULLI_CONFIGGEN_SYSTEM=rk3588
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RISCV),y)
	KNULLI_CONFIGGEN_SYSTEM=riscv
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM8250),y)
	KNULLI_CONFIGGEN_SYSTEM=sm8250
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM8550),y)
	KNULLI_CONFIGGEN_SYSTEM=sm8550
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3576),y)
	KNULLI_CONFIGGEN_SYSTEM=rk3576
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_T618),y)
	KNULLI_CONFIGGEN_SYSTEM=t618
endif

define KNULLI_CONFIGGEN_INSTALL_STAGING_CMDS
    @echo "=== DEBUG STAGING ==="
    @echo "KNULLI_CONFIGGEN_DIR = $(KNULLI_CONFIGGEN_DIR)"
    @echo "BR2_EXTERNAL_KNULLI_PATH = $(BR2_EXTERNAL_KNULLI_PATH)"
    @echo "Direct path: $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen"
    @echo "System: $(KNULLI_CONFIGGEN_SYSTEM)"
    @echo "====================="
    mkdir -p $(STAGING_DIR)/usr/share/knulli/configgen
    cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/configs/configgen-defaults.yml \
        $(STAGING_DIR)/usr/share/knulli/configgen/configgen-defaults.yml
    cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/configs/configgen-defaults-$(KNULLI_CONFIGGEN_SYSTEM).yml \
        $(STAGING_DIR)/usr/share/knulli/configgen/configgen-defaults-arch.yml
endef

define KNULLI_CONFIGGEN_CONFIGS
    mkdir -p $(TARGET_DIR)/usr/share/knulli/configgen
    cp -pr $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/data \
        $(TARGET_DIR)/usr/share/knulli/configgen/
    cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/configs/configgen-defaults.yml \
        $(TARGET_DIR)/usr/share/knulli/configgen/configgen-defaults.yml
    cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/configs/configgen-defaults-$(KNULLI_CONFIGGEN_SYSTEM).yml \
        $(TARGET_DIR)/usr/share/knulli/configgen/configgen-defaults-arch.yml
    cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/scripts/call_achievements_hooks.sh \
        $(TARGET_DIR)/usr/share/knulli/configgen/
    # pad combos for standalone emulators the drop does not carry a mapping for
    mkdir -p $(TARGET_DIR)/usr/share/evmapy
    cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/evmapy/*.keys \
        $(TARGET_DIR)/usr/share/evmapy/
endef

define KNULLI_CONFIGGEN_ES_HOOKS
    install -D -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/scripts/powermode_launch_hooks.sh \
        $(TARGET_DIR)/usr/share/knulli/configgen/scripts/powermode_launch_hooks.sh

    install -D -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/scripts/adhoc_hooks.sh \
        $(TARGET_DIR)/usr/share/knulli/configgen/scripts/adhoc_hooks.sh
endef

define KNULLI_CONFIGGEN_X86_HOOKS
    install -D -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/scripts/tdp_hooks.sh \
        $(TARGET_DIR)/usr/share/knulli/configgen/scripts/tdp_hooks.sh

    install -D -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-configgen/scripts/nvidia-workaround.sh \
        $(TARGET_DIR)/usr/share/knulli/configgen/scripts/nvidia-workaround.sh
endef

KNULLI_CONFIGGEN_POST_INSTALL_TARGET_HOOKS = KNULLI_CONFIGGEN_CONFIGS
KNULLI_CONFIGGEN_POST_INSTALL_TARGET_HOOKS += KNULLI_CONFIGGEN_ES_HOOKS

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_X86_64_ANY),y)
    KNULLI_CONFIGGEN_POST_INSTALL_TARGET_HOOKS += KNULLI_CONFIGGEN_X86_HOOKS
endif

$(eval $(python-package))
