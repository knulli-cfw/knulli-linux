################################################################################
#
# ffrumble
#
################################################################################

FF_RUMBLE_VERSION = 1.0
FF_RUMBLE_SITE = $(FF_RUMBLE_PKGDIR)
FF_RUMBLE_SITE_METHOD = local
FF_RUMBLE_LICENSE = GPL-2.0

define FF_RUMBLE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(TARGET_CC) \
		$(TARGET_CFLAGS) \
		-std=gnu11 \
		-O3 \
		-pipe \
		-ffunction-sections \
		-fdata-sections \
		-Wall \
		-Wextra \
		-Wpedantic \
		$(@D)/ff-rumble.c \
		$(TARGET_LDFLAGS) \
		-Wl,--gc-sections \
		-o $(@D)/ff-rumble
endef

define FF_RUMBLE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 \
		$(@D)/ff-rumble \
		$(TARGET_DIR)/usr/bin/ff-rumble
endef

$(eval $(generic-package))
