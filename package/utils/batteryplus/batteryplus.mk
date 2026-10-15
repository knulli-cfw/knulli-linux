################################################################################
#
# batteryplus
#
################################################################################

BATTERYPLUS_VERSION = main
BATTERYPLUS_SITE = https://github.com/Mikhailzrick/knubat.components.git
BATTERYPLUS_SITE_METHOD = git
BATTERYPLUS_LICENSE = GPL-2.0

define BATTERYPLUS_BUILD_CMDS
	$(TARGET_CXX) \
		$(TARGET_CXXFLAGS) \
		-std=gnu++20 \
		-Wall \
		-Wextra \
		-Wpedantic \
		$(@D)/BatteryPlus/batteryplus.cpp \
		$(TARGET_LDFLAGS) \
		-o $(@D)/batteryplus
endef

define BATTERYPLUS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 \
		$(@D)/batteryplus \
		$(TARGET_DIR)/usr/bin/batteryplus
endef

$(eval $(generic-package))
