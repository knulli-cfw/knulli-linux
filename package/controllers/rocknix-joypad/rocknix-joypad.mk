################################################################################
#
# rocknix-joypad - ROCKNIX Joypad Kernel Module
#
################################################################################
ROCKNIX_JOYPAD_VERSION = e205fe5489561d955dbf00a4e24e73410cdd30f2
ROCKNIX_JOYPAD_SITE = $(call github,ROCKNIX,rocknix-joypad,$(ROCKNIX_JOYPAD_VERSION))
ROCKNIX_JOYPAD_LICENSE = GPL-2.0-or-later
ROCKNIX_JOYPAD_LICENSE_FILES = LICENSE

ROCKNIX_JOYPAD_MODULE_MAKE_OPTS = \
        CONFIG_ROCKNIX_JOYPAD=m \
        $(if $(BR2_PACKAGE_BATOCERA_TARGET_H700),DEVICE=H700) \
        USER_EXTRA_CFLAGS="-DCONFIG_$(call qstrip,$(BR2_ENDIAN))_ENDIAN \
                -Wno-error"

define ROCKNIX_JOYPAD_MAKE_SUBDIR
        (cd $(@D); ln -s . rocknix-joypad)
endef

ROCKNIX_JOYPAD_PRE_CONFIGURE_HOOKS += ROCKNIX_JOYPAD_MAKE_SUBDIR

# Register the package as a kernel module
$(eval $(kernel-module))
$(eval $(generic-package))
