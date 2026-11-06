################################################################################
#
# knulli-triggerhappy
#
################################################################################

KNULLI_TRIGGERHAPPY_VERSION = 1.2
KNULLI_TRIGGERHAPPY_LICENSE = GPL
KNULLI_TRIGGERHAPPY_DEPENDENCIES = triggerhappy
KNULLI_TRIGGERHAPPY_SOURCE=

KNULLI_TRIGGERHAPPY_SOURCE_PATH = \
    $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-triggerhappy

define KNULLI_TRIGGERHAPPY_INSTALL_CONFIG
	mkdir -p $(TARGET_DIR)/etc/triggerhappy/triggers.d
	mkdir -p $(BINARIES_DIR)/knulli-target/etc/init.d
	cp $(KNULLI_TRIGGERHAPPY_SOURCE_PATH)/conf/multimedia_keys.conf \
	    $(TARGET_DIR)/etc/triggerhappy/triggers.d
	cp $(KNULLI_TRIGGERHAPPY_SOURCE_PATH)/conf/multimedia_keys_disabled.conf \
	    $(TARGET_DIR)/etc/triggerhappy/triggers.d
	install -m 0755 $(KNULLI_TRIGGERHAPPY_SOURCE_PATH)/triggerhappy.service \
	    $(TARGET_DIR)/etc/init.d/S50triggerhappy
endef

define KNULLI_TRIGGERHAPPY_INSTALL_RK3326_CONFIG
    cp -v $(KNULLI_TRIGGERHAPPY_SOURCE_PATH)/conf/rk3326/*.conf \
	    $(TARGET_DIR)/etc/triggerhappy/triggers.d/
endef

define KNULLI_TRIGGERHAPPY_INSTALL_RK3399_CONFIG
	cp -v $(KNULLI_TRIGGERHAPPY_SOURCE_PATH)/conf/rk3399/*.conf \
	    $(TARGET_DIR)/etc/triggerhappy/triggers.d/
endef

define KNULLI_TRIGGERHAPPY_INSTALL_X86_64_CONFIG
	cp -v $(KNULLI_TRIGGERHAPPY_SOURCE_PATH)/conf/x86_64/*.conf \
	    $(TARGET_DIR)/etc/triggerhappy/triggers.d/
endef

define KNULLI_TRIGGERHAPPY_INSTALL_SM8250_CONFIG
	cp -v $(KNULLI_TRIGGERHAPPY_SOURCE_PATH)/conf/sm8250/*.conf \
	    $(TARGET_DIR)/etc/triggerhappy/triggers.d/
endef

KNULLI_TRIGGERHAPPY_POST_INSTALL_TARGET_HOOKS += KNULLI_TRIGGERHAPPY_INSTALL_CONFIG

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3326),y)
	KNULLI_TRIGGERHAPPY_POST_INSTALL_TARGET_HOOKS += KNULLI_TRIGGERHAPPY_INSTALL_RK3326_CONFIG
endif

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3399),y)
	KNULLI_TRIGGERHAPPY_POST_INSTALL_TARGET_HOOKS += KNULLI_TRIGGERHAPPY_INSTALL_RK3399_CONFIG
endif


ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_X86_64_ANY),y)
	KNULLI_TRIGGERHAPPY_POST_INSTALL_TARGET_HOOKS += KNULLI_TRIGGERHAPPY_INSTALL_X86_64_CONFIG
endif

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM8250),y)
	KNULLI_TRIGGERHAPPY_POST_INSTALL_TARGET_HOOKS += KNULLI_TRIGGERHAPPY_INSTALL_SM8250_CONFIG
endif

$(eval $(generic-package))
