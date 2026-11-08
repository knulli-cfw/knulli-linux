################################################################################
#
# knulli scripts
#
################################################################################

KNULLI_SCRIPTS_VERSION = 3
KNULLI_SCRIPTS_LICENSE = GPL
KNULLI_SCRIPTS_DEPENDENCIES = pciutils
KNULLI_SCRIPTS_SOURCE=

KNULLI_SCRIPTS_PATH = $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-scripts

# mouse type #
ifeq ($(BR2_PACKAGE_XSERVER_XORG_SERVER),y)
  KNULLI_SCRIPTS_MOUSE_TYPE=xorg
  KNULLI_SCRIPTS_POST_INSTALL_TARGET_HOOKS += KNULLI_SCRIPTS_INSTALL_MOUSE
endif

ifeq ($(BR2_PACKAGE_BATOCERA_WAYLAND_SWAY),y)
  KNULLI_SCRIPTS_MOUSE_TYPE=wayland-sway
  KNULLI_SCRIPTS_POST_INSTALL_TARGET_HOOKS += KNULLI_SCRIPTS_INSTALL_MOUSE
endif

ifeq ($(BR2_PACKAGE_BATOCERA_WAYLAND_LABWC),y)
  KNULLI_SCRIPTS_MOUSE_TYPE=wayland-labwc
  KNULLI_SCRIPTS_DEPENDENCIES+= wtype
  KNULLI_SCRIPTS_POST_INSTALL_TARGET_HOOKS += KNULLI_SCRIPTS_INSTALL_MOUSE
endif
###

# Every Qualcomm target: their fsoverlays ship etc/init.d/S06qcom-fan, which
# runs this binary.
ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_QUALCOMM_SMXXXX_PLATFORM),y)
  KNULLI_SCRIPTS_POST_INSTALL_TARGET_HOOKS += KNULLI_SCRIPTS_INSTALL_QCOM
endif

define KNULLI_SCRIPTS_INSTALL_TARGET_CMDS
    mkdir -p $(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR)
    mkdir -p $(TARGET_DIR)/usr/bin
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/bluetooth/bluezutils.py            $(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR)/ # any variable ?
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/bluetooth/knulli-bluetooth       $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/bluetooth/knulli-bluetooth-agent $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-save-overlay              $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-kodi                      $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-kodilauncher              $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-usbmount                  $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-encode                    $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-padsinfo                  $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-info                      $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-install                   $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-format                    $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-mount                     $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-overclock                 $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-part                      $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-support                   $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-version                   $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-sync                      $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-upgrade                   $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-systems                   $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-config                    $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-es-thebezelproject        $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-cores                     $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-wifi                      $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-brightness                $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-es-swissknife             $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-store                     $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-autologin                 $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-timezone                  $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-gameforce                 $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-shutdown                  $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-services                  $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-planemode                 $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-switch-screen-checker     $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-switch-screen-checker-delayed     $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-ikemen                    $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-streaming                 $(TARGET_DIR)/usr/bin/
    install -m 0644 $(KNULLI_SCRIPTS_PATH)/rules/80-switch-screen.rules               $(TARGET_DIR)/etc/udev/rules.d
    mkdir -p $(TARGET_DIR)/etc/udev/rules.d
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-amd-tdp                   $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-get-nvidia-list           $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-spinner-calibrator        $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-vulkan                    $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-power-mode                $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-es-web-notifier           $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/getLocalXDisplay                   $(TARGET_DIR)/usr/bin/
endef

define KNULLI_SCRIPTS_INSTALL_MOUSE
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-mouse.${KNULLI_SCRIPTS_MOUSE_TYPE} $(TARGET_DIR)/usr/bin/knulli-mouse
endef

define KNULLI_SCRIPTS_INSTALL_QCOM
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/qcom-fan                           $(TARGET_DIR)/usr/bin/
endef

define KNULLI_SCRIPTS_INSTALL_ROCKCHIP
    mkdir -p $(TARGET_DIR)/usr/bin/
    install -m 0755 $(KNULLI_SCRIPTS_PATH)/scripts/knulli-rockchip-suspend $(TARGET_DIR)/usr/bin/
endef

$(eval $(generic-package))
