################################################################################
#
# EmulationStation theme "Knulli"
#
################################################################################
# Version: Commits on Oct 24, 2026
ES_THEME_KNULLI_VERSION = aad750f1b3dd4f3dce0472e849528765cdb7b9e8
ES_THEME_KNULLI_SITE = $(call github,symbuzzer,es-theme-knulli,$(ES_THEME_KNULLI_VERSION))

define ES_THEME_KNULLI_INSTALL_TARGET_CMDS
    mkdir -p $(TARGET_DIR)/usr/share/emulationstation/themes/es-theme-knulli
    cp -r $(@D)/* $(TARGET_DIR)/usr/share/emulationstation/themes/es-theme-knulli
endef

$(eval $(generic-package))
