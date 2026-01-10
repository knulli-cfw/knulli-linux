################################################################################
#
# knulli-es-web-ui
#
################################################################################
KNULLI_ES_WEB_UI_VERSION = 0.1
KNULLI_ES_WEB_UI_LICENSE = LGPL 
KNULLI_ES_WEB_UI_DEPENDENCIES = knulli-emulationstation
KNULLI_ES_WEB_UI_SOURCE =

define KNULLI_ES_WEB_UI_RESOURCES
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/emulationstation/resources/services
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/knulli/services
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 0644 -D $(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-web-ui/web/* \
	    $(TARGET_DIR)/usr/share/emulationstation/resources/services
	$(INSTALL) -m 0644 -D $(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-web-ui/services/* \
	    $(TARGET_DIR)/usr/share/knulli/services
endef

KNULLI_ES_WEB_UI_POST_INSTALL_TARGET_HOOKS += KNULLI_ES_WEB_UI_RESOURCES

$(eval $(generic-package))
