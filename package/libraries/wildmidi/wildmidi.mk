################################################################################
#
# wildmidi
#
################################################################################

WILDMIDI_VERSION = 9ee0f9bc6db93521abd0192b226d2cf8089eb369
WILDMIDI_SITE =  $(call github,Mindwerks,wildmidi,$(WILDMIDI_VERSION))
WILDMIDI_LICENSE = LGPLv3
WILDMIDI_INSTALL_STAGING = YES
WILDMIDI_CONF_OPTS += -DBUILD_TESTING=OFF -DWANT_STATIC=ON -DWANT_PLAYER=OFF

# WildMidi's exported target records the FULL path of the libm.so it found at
# configure time, and what lands in the sysroot has had the build root stripped
# out of it:
#
#   INTERFACE_LINK_LIBRARIES "-Wl,--no-undefined;/h700/host/.../sysroot/usr/lib/libm.so"
#
# ("/build/output" is gone from the front.)  Any cmake consumer then inherits a
# path that does not exist and fails at link with "No rule to make target".  The
# libretro easyrpg core is the one that hits it; a board build only escapes it
# because nothing there consumes WildMidiConfig.cmake.
#
# libm is part of libc, so the dependency only ever needed to be "m".
define WILDMIDI_FIX_STAGED_CMAKE_LIBM
	$(Q)if [ -f $(STAGING_DIR)/usr/lib/cmake/WildMidi/WildMidiTargets.cmake ]; then \
		$(SED) 's|;[^;"]*/libm\.so|;m|g' \
			$(STAGING_DIR)/usr/lib/cmake/WildMidi/WildMidiTargets.cmake; \
	fi
endef
WILDMIDI_POST_INSTALL_STAGING_HOOKS += WILDMIDI_FIX_STAGED_CMAKE_LIBM

$(eval $(cmake-package))
