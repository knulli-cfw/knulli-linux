################################################################################
#
# MALI G57 SUNXI GPU driver
#
################################################################################
# Version.: Commits on Dec 8, 2025
MALI_G57_SUNXI_VERSION = main
MALI_G57_SUNXI_SITE = https://github.com/knulli-cfw/mali-g57-sunxi-drivers.git
MALI_G57_SUNXI_SITE_METHOD = git

MALI_G57_SUNXI_LICENSE = Propietary

MALI_G57_SUNXI_INSTALL_STAGING = YES
MALI_G57_SUNXI_PROVIDES = libegl libgles libopencl libmali libgbm
MALI_G57_SUNXI_DEPENDENCIES = libdrm

define MALI_G57_SUNXI_INSTALL_STAGING_CMDS
        mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig

        # Install headers
        cp -rf $(@D)/include/* $(STAGING_DIR)/usr/include/

        # Install patched eglplatform.h that doesn't require X11 headers
        $(INSTALL) -D -m 0644 $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-g57-sunxi/include/EGL/eglplatform.h \
                $(STAGING_DIR)/usr/include/EGL/eglplatform.h

        # Install main mali library
        $(INSTALL) -D -m 0755 $(@D)/fbdev/arm64/libmali.so.0.32.0 $(STAGING_DIR)/usr/lib/libmali.so.1
        ln -sf libmali.so.1 $(STAGING_DIR)/usr/lib/libmali.so

        # Create symlinks for EGL (point directly to libmali to avoid DSO issues)
        ln -sf libmali.so.1 $(STAGING_DIR)/usr/lib/libEGL.so.1
        ln -sf libEGL.so.1 $(STAGING_DIR)/usr/lib/libEGL.so

        # Create symlinks for GLES
        ln -sf libmali.so.1 $(STAGING_DIR)/usr/lib/libGLESv2.so.2
        ln -sf libGLESv2.so.2 $(STAGING_DIR)/usr/lib/libGLESv2.so
        ln -sf libmali.so.1 $(STAGING_DIR)/usr/lib/libGLESv1_CM.so.1
        ln -sf libGLESv1_CM.so.1 $(STAGING_DIR)/usr/lib/libGLESv1_CM.so

        # Create symlinks for GBM
        ln -sf libmali.so.1 $(STAGING_DIR)/usr/lib/libgbm.so.1
        ln -sf libgbm.so.1 $(STAGING_DIR)/usr/lib/libgbm.so

        # Create symlinks for OpenCL
        ln -sf libmali.so.1 $(STAGING_DIR)/usr/lib/libOpenCL.so.1
        ln -sf libOpenCL.so.1 $(STAGING_DIR)/usr/lib/libOpenCL.so

        # Install pkg-config files
        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-g57-sunxi/egl.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/egl.pc
        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-g57-sunxi/glesv2.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/glesv2.pc
        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-g57-sunxi/gbm.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/gbm.pc
        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-g57-sunxi/mali.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/mali.pc
        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/mali-g57-sunxi/wayland-egl.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/wayland-egl.pc
endef

define MALI_G57_SUNXI_INSTALL_TARGET_CMDS
        mkdir -p $(TARGET_DIR)/usr/lib

        # Install original fbdev libraries (contain runtime initialization code)
        cp -rf $(@D)/fbdev/arm64/* $(TARGET_DIR)/usr/lib/
endef

$(eval $(generic-package))

