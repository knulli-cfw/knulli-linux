################################################################################
#
# qualcomm firmware
#
################################################################################
# Version.: Commits on Aug 17, 2026
QUALCOMM_FIRMWARE_VERSION = 4eb96440b80328bf129331b8ee44ac87de7d737f
QUALCOMM_FIRMWARE_SITE = $(call github,knulli-cfw,qualcomm_firmware,$(QUALCOMM_FIRMWARE_VERSION))

QUALCOMM_FIRMWARE_LICENSE = Proprietary

# Ordering, not just a build dependency: the WCN7850 blobs here are vendor
# variants of files linux-firmware also ships, and ours have to win.
QUALCOMM_FIRMWARE_DEPENDENCIES = alllinuxfirmwares

QUALCOMM_FIRMWARE_TARGET_DIR = $(TARGET_DIR)/lib/firmware/

define QUALCOMM_FIRMWARE_INSTALL_TARGET_CMDS
	mkdir -p $(QUALCOMM_FIRMWARE_TARGET_DIR)
	cp -a $(@D)/* $(QUALCOMM_FIRMWARE_TARGET_DIR)/
endef

$(eval $(generic-package))
