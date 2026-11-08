################################################################################
#
# rocknix-abl
#
################################################################################

ROCKNIX_ABL_VERSION = 1.1.9
ROCKNIX_ABL_SOURCE = rocknix-abl-v$(ROCKNIX_ABL_VERSION).tar.gz
ROCKNIX_ABL_SITE = https://github.com/ROCKNIX/abl/releases/download/v$(ROCKNIX_ABL_VERSION)

ROCKNIX_ABL_DEPENDENCIES = pv

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM4450),y)
ROCKNIX_ABL_MODEL = SM4450
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SM6115),y)
ROCKNIX_ABL_MODEL = SM6115
else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_SMGEN),y)
# one image for several SoCs: ship every ABL, updateabl picks by the DT compatible
ROCKNIX_ABL_MODEL = SM8250 SM8550 SM4450
endif

define ROCKNIX_ABL_INSTALL_TARGET_CMDS
	$(if $(ROCKNIX_ABL_MODEL), \
		mkdir -p $(TARGET_DIR)/usr/share/bootloader/rocknix_abl ; \
		$(foreach m,$(ROCKNIX_ABL_MODEL), \
			$(INSTALL) -m 0644 $(@D)/abl_signed-$(m).elf \
				$(TARGET_DIR)/usr/share/bootloader/rocknix_abl/ ; \
			$(INSTALL) -m 0644 $(@D)/abl_signed-$(m).elf.sha256 \
				$(TARGET_DIR)/usr/share/bootloader/rocknix_abl/ ; ) \
		echo v$(ROCKNIX_ABL_VERSION) > $(TARGET_DIR)/usr/share/bootloader/rocknix_abl/version ; \
		$(INSTALL) -D -m 0755 $(ROCKNIX_ABL_PKGDIR)/updateabl \
			$(TARGET_DIR)/usr/bin/updateabl
	)
endef

$(eval $(generic-package))
