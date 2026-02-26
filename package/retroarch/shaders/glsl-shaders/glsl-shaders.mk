################################################################################
#
# glsl-shaders
#
################################################################################
# Version: Commits on Apr 4, 2025
GLSL_SHADERS_VERSION = ad982c951e70a5a9609b173a2c5fa50afb5f58ad
GLSL_SHADERS_SITE = $(call github,libretro,glsl-shaders,$(GLSL_SHADERS_VERSION))
GLSL_SHADERS_LICENSE = GPL

define GLSL_SHADERS_BUILD_CMDS
	CFLAGS="$(TARGET_CFLAGS)" \
	CXXFLAGS="$(TARGET_CXXFLAGS)" \
	$(MAKE) CXX="$(TARGET_CXX)" CC="$(TARGET_CC)" -C $(@D)/ -f Makefile
endef

define GLSL_SHADERS_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/knulli/shaders
	$(MAKE) CXX="$(TARGET_CXX)" -C $(@D) \
	    INSTALLDIR=$(TARGET_DIR)/usr/share/knulli/shaders install
	sed -e "s:^//#define CURVATURE:#define CURVATURE:" \
	    $(TARGET_DIR)/usr/share/knulli/shaders/crt/shaders/crt-pi.glsl > \
		    $(TARGET_DIR)/usr/share/knulli/shaders/crt/shaders/crt-pi-curvature.glsl
	sed -e 's:^shader0 = "shaders/crt-pi.glsl":shader0 = "shaders/crt-pi-curvature.glsl":' \
	    $(TARGET_DIR)/usr/share/knulli/shaders/crt/crt-pi.glslp > \
		    $(TARGET_DIR)/usr/share/knulli/shaders/crt/crt-pi-curvature.glslp
	sed -i "s/PT_SHADOW_BLUR_MODE \"== Shadow blur (impacts performance) == (0=OFF,1=Lite,2=Full)\" 1\.0 0\.0 2\.0 1\.0/PT_SHADOW_BLUR_MODE \"== Shadow blur (impacts performance) == (0=OFF,1=Lite,2=Full)\" 0\.0 0\.0 2\.0 1\.0/" \
	    $(TARGET_DIR)/usr/share/knulli/shaders/handheld/shaders/pixel_transparency.glsl
endef

$(eval $(generic-package))
