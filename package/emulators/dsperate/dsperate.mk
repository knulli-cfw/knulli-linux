################################################################################
#
# dsperate
#
################################################################################

DSPERATE_VERSION = 18afb74fd0cfba9854a854b27304b2735d0f573a
#0c2baf65424103339952f48f1ab8bf8ef687fbb5
DSPERATE_SITE = $(call github,beebono,DSperate,$(DSPERATE_VERSION))
DSPERATE_LICENSE = GPL-3.0-or-later
DSPERATE_LICENSE_FILES = LICENSE
DSPERATE_SUPPORTS_IN_SOURCE_BUILD = NO

DSPERATE_DEPENDENCIES = sdl2

# The recompiler and the NEON kernels are aarch64 only; CMakeLists turns them
# off by itself on any other CMAKE_SYSTEM_PROCESSOR and falls back to the
# interpreter and the portable renderer.
DSPERATE_CONF_OPTS += -DDSPERATE_SDL=ON

# The CLI is the headless comparison harness and the tests need to run on the
# host, so neither ships.
DSPERATE_CONF_OPTS += -DDSPERATE_CLI=OFF
DSPERATE_CONF_OPTS += -DDSPERATE_TESTS=OFF

# Upstream has no install rules -- it is run out of the build tree.  ALSA and
# wayland are dlopen'd, so neither is a build dependency.
define DSPERATE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/buildroot-build/src/frontend/sdl/dsperate \
	    $(TARGET_DIR)/usr/bin/dsperate
endef

$(eval $(cmake-package))
