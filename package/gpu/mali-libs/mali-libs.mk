################################################################################
#
# mali-libs
#
################################################################################

MALI_LIBS_VERSION = 746bafbc5eb7d52b68a71d1bd673d51730c31aae
MALI_LIBS_SITE = https://github.com/knulli-cfw/libmali-next.git
MALI_LIBS_SITE_METHOD = git
MALI_LIBS_LICENSE = Proprietary
MALI_LIBS_LICENSE_FILES = END_USER_LICENCE_AGREEMENT.txt
MALI_LIBS_INSTALL_STAGING = YES

MALI_LIBS_PROVIDES =
MALI_LIBS_DEPENDENCIES = libdrm

ifeq ($(BR2_PACKAGE_MALI_LIBS_PROVIDES_EGL),y)
MALI_LIBS_PROVIDES += libegl
endif

ifeq ($(BR2_PACKAGE_MALI_LIBS_PROVIDES_GLES),y)
MALI_LIBS_PROVIDES += libgles
endif

ifeq ($(BR2_PACKAGE_MALI_LIBS_PROVIDES_GBM),y)
MALI_LIBS_PROVIDES += libgbm
endif

ifeq ($(BR2_PACKAGE_WAYLAND),y)
MALI_LIBS_DEPENDENCIES += wayland
endif

# Determine GPU and architecture
ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3588),y)
MALI_LIBS_GPU = valhall-g610
MALI_LIBS_VERSION_GPU = g29p1
else
# Default to G52 (covers RK3566/RK3568)
MALI_LIBS_GPU = bifrost-g52
MALI_LIBS_VERSION_GPU = g29p1
endif

ifeq ($(BR2_aarch64),y)
MALI_LIBS_ARCH = aarch64-linux-gnu
MALI_LIBS_WSI_ARCH = aarch64
else
MALI_LIBS_ARCH = arm-linux-gnueabihf
MALI_LIBS_WSI_ARCH = arm
endif

MALI_LIBS_SO_NAME = libmali-$(MALI_LIBS_GPU)-$(MALI_LIBS_VERSION_GPU).so

define MALI_LIBS_INSTALL_STAGING_CMDS
    # Install library
    $(INSTALL) -D -m 0755 $(@D)/lib/$(MALI_LIBS_ARCH)/$(MALI_LIBS_SO_NAME) \
        $(STAGING_DIR)/usr/lib/libmali.so.1
    ln -sf libmali.so.1 $(STAGING_DIR)/usr/lib/libmali.so
    
    # Create symlinks for EGL
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

    # Install headers - copy all subdirectories from include/
    cp -r $(@D)/include/* $(STAGING_DIR)/usr/include/
    
    # GBM header needs to be at the top level (gbm.h expects to be included as <gbm.h>)
    if [ -f $(STAGING_DIR)/usr/include/GBM/gbm.h ]; then \
        cp $(STAGING_DIR)/usr/include/GBM/gbm.h $(STAGING_DIR)/usr/include/; \
    fi
    
    # Create pkg-config files
    mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig
    
    # gbm.pc
    ( \
        echo 'prefix=/usr'; \
        echo 'exec_prefix=$${prefix}'; \
        echo 'libdir=$${exec_prefix}/lib'; \
        echo 'includedir=$${prefix}/include'; \
        echo ''; \
        echo 'Name: gbm'; \
        echo 'Description: Generic Buffer Management'; \
        echo 'Version: 21.0.0'; \
        echo 'Requires.private: libdrm'; \
        echo 'Libs: -L$${libdir} -lgbm'; \
        echo 'Cflags: -I$${includedir}'; \
    ) > $(STAGING_DIR)/usr/lib/pkgconfig/gbm.pc
    
    # egl.pc
    ( \
        echo 'prefix=/usr'; \
        echo 'exec_prefix=$${prefix}'; \
        echo 'libdir=$${exec_prefix}/lib'; \
        echo 'includedir=$${prefix}/include'; \
        echo ''; \
        echo 'Name: egl'; \
        echo 'Description: EGL library'; \
        echo 'Version: 1.5'; \
        echo 'Requires.private: libdrm'; \
        echo 'Libs: -L$${libdir} -lEGL'; \
        echo 'Cflags: -I$${includedir}'; \
    ) > $(STAGING_DIR)/usr/lib/pkgconfig/egl.pc
    
    # glesv2.pc
    ( \
        echo 'prefix=/usr'; \
        echo 'exec_prefix=$${prefix}'; \
        echo 'libdir=$${exec_prefix}/lib'; \
        echo 'includedir=$${prefix}/include'; \
        echo ''; \
        echo 'Name: glesv2'; \
        echo 'Description: OpenGL ES 2.0 library'; \
        echo 'Version: 2.0'; \
        echo 'Requires: egl'; \
        echo 'Libs: -L$${libdir} -lGLESv2'; \
        echo 'Cflags: -I$${includedir}'; \
    ) > $(STAGING_DIR)/usr/lib/pkgconfig/glesv2.pc

    # Install Vulkan ICD to staging
    mkdir -p $(STAGING_DIR)/etc/vulkan/icd.d
    sed 's|@LIB@|/usr/lib/libmali.so.1|g' \
        $(@D)/data/vulkan/mali.json.in > $(STAGING_DIR)/etc/vulkan/icd.d/mali.json

    # Install Vulkan implicit layer (WSI) to staging
    $(INSTALL) -D -m 0755 \
        $(@D)/data/vulkan/lib/$(MALI_LIBS_WSI_ARCH)/libVkLayer_window_system_integration.so \
        $(STAGING_DIR)/usr/lib/libVkLayer_window_system_integration.so
    mkdir -p $(STAGING_DIR)/etc/vulkan/implicit_layer.d
    sed 's|@LIB@|/usr/lib/libVkLayer_window_system_integration.so|g' \
        $(@D)/data/vulkan/VkLayer_window_system_integration.json.in \
        > $(STAGING_DIR)/etc/vulkan/implicit_layer.d/VkLayer_window_system_integration.json

endef

define MALI_LIBS_INSTALL_TARGET_CMDS
    # Install library
    $(INSTALL) -D -m 0755 $(@D)/lib/$(MALI_LIBS_ARCH)/$(MALI_LIBS_SO_NAME) \
        $(TARGET_DIR)/usr/lib/libmali.so.1
    ln -sf libmali.so.1 $(TARGET_DIR)/usr/lib/libmali.so
    
    # Create symlinks for EGL
    ln -sf libmali.so.1 $(TARGET_DIR)/usr/lib/libEGL.so.1
    ln -sf libEGL.so.1 $(TARGET_DIR)/usr/lib/libEGL.so
    
    # Create symlinks for GLES
    ln -sf libmali.so.1 $(TARGET_DIR)/usr/lib/libGLESv2.so.2
    ln -sf libGLESv2.so.2 $(TARGET_DIR)/usr/lib/libGLESv2.so
    ln -sf libmali.so.1 $(TARGET_DIR)/usr/lib/libGLESv1_CM.so.1
    ln -sf libGLESv1_CM.so.1 $(TARGET_DIR)/usr/lib/libGLESv1_CM.so
    
    # Create symlinks for GBM
    ln -sf libmali.so.1 $(TARGET_DIR)/usr/lib/libgbm.so.1
    ln -sf libgbm.so.1 $(TARGET_DIR)/usr/lib/libgbm.so

    # Install Vulkan ICD
    mkdir -p $(TARGET_DIR)/etc/vulkan/icd.d
    sed 's|@LIB@|/usr/lib/libmali.so.1|g' \
        $(@D)/data/vulkan/mali.json.in > $(TARGET_DIR)/etc/vulkan/icd.d/mali.json

    # Install Vulkan implicit layer (WSI)
    $(INSTALL) -D -m 0755 \
        $(@D)/data/vulkan/lib/$(MALI_LIBS_WSI_ARCH)/libVkLayer_window_system_integration.so \
        $(TARGET_DIR)/usr/lib/libVkLayer_window_system_integration.so
    mkdir -p $(TARGET_DIR)/etc/vulkan/implicit_layer.d
    sed 's|@LIB@|/usr/lib/libVkLayer_window_system_integration.so|g' \
        $(@D)/data/vulkan/VkLayer_window_system_integration.json.in \
        > $(TARGET_DIR)/etc/vulkan/implicit_layer.d/VkLayer_window_system_integration.json
endef

$(eval $(generic-package))
