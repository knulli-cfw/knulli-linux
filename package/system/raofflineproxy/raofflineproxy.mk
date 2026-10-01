################################################################################
#
# raofflineproxy
#
################################################################################

RAOFFLINEPROXY_VERSION = 1.0
RAOFFLINEPROXY_LICENSE = GPL-3.0
RAOFFLINEPROXY_SOURCE =

define RAOFFLINEPROXY_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/raofflineproxy/services/raofflineproxy \
	    $(TARGET_DIR)/usr/share/knulli/services/raofflineproxy
endef

$(eval $(generic-package))
