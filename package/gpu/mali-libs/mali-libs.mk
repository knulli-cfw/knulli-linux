################################################################################
#
# mali-libs
#
################################################################################

# g29p1-5 for G31/G52: the first blob that stops exporting its embedded
# libwayland functions.  Earlier ones interpose on the system libwayland and
# crash GLES Wayland clients (ES under a compositor) in their first roundtrip.
MALI_LIBS_VERSION = bf621d15f009509557d6b28f81427651695cac20
MALI_LIBS_SITE = https://github.com/knulli-cfw/libmali-next.git
MALI_LIBS_SITE_METHOD = git
MALI_LIBS_LICENSE = Proprietary
MALI_LIBS_LICENSE_FILES = END_USER_LICENCE_AGREEMENT.txt
MALI_LIBS_INSTALL_STAGING = YES

MALI_LIBS_PROVIDES =
MALI_LIBS_DEPENDENCIES = libdrm host-patchelf

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

# Upstream's hook library and wrappers, which the meson build would provide.
# The blob only takes a wl_display through eglGetPlatformDisplay; the hook's
# eglGetDisplay falls back to that (and to X11/GBM), so apps that hand
# eglGetDisplay a native display -- SDL2's Wayland backend -- keep working.
# The wrappers carry the libEGL/libGLESv2/libgbm sonames and depend on the hook
# before the blob, so both dlopen() users and linked binaries see it first.
MALI_LIBS_HOOK_FUNCS = \
	gbm_bo_get_modifier \
	gbm_bo_create_with_modifiers \
	gbm_bo_create_with_modifiers2 \
	gbm_surface_create_with_modifiers \
	gbm_surface_create_with_modifiers2
MALI_LIBS_WRAPPERS = libEGL.so.1 libGLESv2.so.2 libGLESv1_CM.so.1 libgbm.so.1

# gbm.pc's Version is what consumers version-check against, so it has to match
# the gbm.h actually installed -- upstream ships several, and the .pc used to
# claim 21.0.0 regardless.  weston 14 requires >= 21.1.1 and failed configure on
# that stale string.  Verified against the blob's exports: 21.1.0 and 23.1.3 are
# fully implemented, 17.1.0 and older are not (gbm_surface_needs_lock_front_buffer
# is missing), so picking the newest header is also picking a supported API.
#
# Used only if upstream ever flattens include/GBM/<version>/ to include/GBM/,
# where the version stops being discoverable.  Re-check it against the blob then.
MALI_LIBS_GBM_VERSION_FLAT = 23.1.3

define MALI_LIBS_BUILD_CMDS
    # gbm.h has to be includable as <gbm.h>.  Upstream has shipped it two ways:
    # include/GBM/gbm.h, and include/GBM/<mesa-version>/gbm.h with several
    # versions side by side.  Handle both, newest version when they are nested.
    #
    # Loud on failure on purpose.  As a silent "if the file exists" this cost an
    # rk3576 build: no header was installed, and it surfaced much later as sdl2
    # failing to compile its KMSDRM backend on "gbm.h: No such file or
    # directory", with nothing pointing back to the GPU package.
    if [ -f $(@D)/include/GBM/gbm.h ]; then \
        echo "$(@D)/include/GBM" > $(@D)/.gbm-dir; \
        echo "$(MALI_LIBS_GBM_VERSION_FLAT)" > $(@D)/.gbm-version; \
    else \
        gbmdir=$$(ls -1d $(@D)/include/GBM/*/ 2>/dev/null | sort -V | tail -1); \
        if [ -z "$$gbmdir" ] || [ ! -f "$$gbmdir/gbm.h" ]; then \
            echo "mali-libs: no gbm.h under include/GBM -- this package provides" >&2; \
            echo "  libgbm, so every KMSDRM consumer will fail to build" >&2; \
            exit 1; \
        fi; \
        echo "mali-libs: gbm.h from $$(basename $$gbmdir)"; \
        echo "$${gbmdir%/}" > $(@D)/.gbm-dir; \
        basename "$$gbmdir" > $(@D)/.gbm-version; \
    fi

    # The blob ships as libmali-blob.so.1 (soname patched to match) and
    # libmali.so.1 becomes a wrapper over hook + blob, so that libmali.so.1 --
    # the one name every Mali board on the ABI provides -- is also the one that
    # brings the hook in at run time.  The hook and the wrappers link against
    # the renamed copy so they record the blob's file name, not libmali.so.1.
    mkdir -p $(@D)/build-hook
    cp $(@D)/lib/$(MALI_LIBS_ARCH)/$(MALI_LIBS_SO_NAME) $(@D)/build-hook/libmali-blob.so.1
    $(HOST_DIR)/bin/patchelf --set-soname libmali-blob.so.1 $(@D)/build-hook/libmali-blob.so.1

    # Hook library, against the blob it wraps.
    defs=""; \
    for f in $(MALI_LIBS_HOOK_FUNCS); do \
        $(TARGET_NM) -D --defined-only $(@D)/build-hook/libmali-blob.so.1 | grep -qw $$f && \
            defs="$$defs -DHAS_$$f"; \
    done; \
    $(TARGET_CC) $(TARGET_CFLAGS) -shared -fPIC -o $(@D)/build-hook/libmali-hook.so.1 \
        -Wl,-soname,libmali-hook.so.1 -DHAS_EGL -DHAS_GBM $$defs \
        '-DLIBMALI_SO="libmali-blob.so.1"' -I$(@D)/include -I$$(cat $(@D)/.gbm-dir) \
        -I$(STAGING_DIR)/usr/include/libdrm $(@D)/hook/hook.c \
        -L$(@D)/build-hook -l:libmali-blob.so.1 -ldrm -ldl -lpthread

    # Wrappers: empty libraries that pull in the hook, then the blob.
    echo 'void mali_wrapper(void) {}' > $(@D)/build-hook/wrapper.c
    for w in libmali.so.1 $(MALI_LIBS_WRAPPERS); do \
        $(TARGET_CC) $(TARGET_CFLAGS) -shared -fPIC -o $(@D)/build-hook/$$w \
            -Wl,-soname,$$w $(@D)/build-hook/wrapper.c -Wl,--no-as-needed \
            -L$(@D)/build-hook -l:libmali-hook.so.1 -l:libmali-blob.so.1 || exit 1; \
    done
endef

define MALI_LIBS_INSTALL_LIBS
    # dev names belong to staging only (see MALI_LIBS_INSTALL_DEV)
    rm -f $(1)/usr/lib/libmali.so $(1)/usr/lib/libmali-hook.so
    for w in $(MALI_LIBS_WRAPPERS); do rm -f $(1)/usr/lib/$${w%.so.*}.so; done
    $(INSTALL) -D -m 0755 $(@D)/build-hook/libmali-blob.so.1 $(1)/usr/lib/libmali-blob.so.1
    $(INSTALL) -D -m 0755 $(@D)/build-hook/libmali-hook.so.1 $(1)/usr/lib/libmali-hook.so.1
    for w in libmali.so.1 $(MALI_LIBS_WRAPPERS); do \
        rm -f $(1)/usr/lib/$$w; \
        $(INSTALL) -D -m 0755 $(@D)/build-hook/$$w $(1)/usr/lib/$$w || exit 1; \
    done
endef

# Link-time view, staging only.  A wrapper defines nothing, so the dev names
# are linker scripts naming a library with the real symbols.  That library is
# an UNPATCHED copy of the blob, soname libmali.so.1: whatever links -lEGL or
# -lmali records NEEDED libmali.so.1 and nothing else -- the name every Mali
# board on the ABI provides, so emulators built here run from the shared drop
# on h700/rk3326 too.  At run time libmali.so.1 is the wrapper, which brings
# the hook in ahead of the blob.  (Linking the renamed blob or the hook here
# would record libmali-blob.so.1 / libmali-hook.so.1 instead: rk3576-only
# names that broke the aarch64-v8a drop on h700.)
define MALI_LIBS_INSTALL_DEV
    $(INSTALL) -D -m 0755 $(@D)/lib/$(MALI_LIBS_ARCH)/$(MALI_LIBS_SO_NAME) \
        $(STAGING_DIR)/usr/lib/libmali-link.so.1
    for w in libmali.so.1 $(MALI_LIBS_WRAPPERS); do \
        dev=$${w%.so.*}.so; rm -f $(STAGING_DIR)/usr/lib/$$dev; \
        echo "INPUT(-l:libmali-link.so.1)" > $(STAGING_DIR)/usr/lib/$$dev; \
    done
    rm -f $(STAGING_DIR)/usr/lib/libmali-hook.so
endef

# The blob's own Vulkan WSI layer presents only through Weston's
# mali_buffer_sharing; vulkan-wsi-layer, built from source, replaces it.
ifneq ($(BR2_PACKAGE_VULKAN_WSI_LAYER),y)
define MALI_LIBS_INSTALL_WSI
    $(INSTALL) -D -m 0755 \
        $(@D)/data/vulkan/lib/$(MALI_LIBS_WSI_ARCH)/libVkLayer_window_system_integration.so \
        $(1)/usr/lib/libVkLayer_window_system_integration.so
    mkdir -p $(1)/etc/vulkan/implicit_layer.d
    sed 's|@LIB@|/usr/lib/libVkLayer_window_system_integration.so|g' \
        $(@D)/data/vulkan/VkLayer_window_system_integration.json.in \
        > $(1)/etc/vulkan/implicit_layer.d/VkLayer_window_system_integration.json
endef
MALI_LIBS_INSTALL_WSI_STAGING = $(call MALI_LIBS_INSTALL_WSI,$(STAGING_DIR))
MALI_LIBS_INSTALL_WSI_TARGET = $(call MALI_LIBS_INSTALL_WSI,$(TARGET_DIR))
endif

define MALI_LIBS_INSTALL_STAGING_CMDS
    $(call MALI_LIBS_INSTALL_LIBS,$(STAGING_DIR))
    $(MALI_LIBS_INSTALL_DEV)

    # Install headers - copy all subdirectories from include/
    cp -r $(@D)/include/* $(STAGING_DIR)/usr/include/
    $(INSTALL) -D -m 0644 $$(cat $(@D)/.gbm-dir)/gbm.h $(STAGING_DIR)/usr/include/gbm.h
    
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
        echo "Version: $$(cat $(@D)/.gbm-version)"; \
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

    $(MALI_LIBS_INSTALL_WSI_STAGING)

endef

define MALI_LIBS_INSTALL_TARGET_CMDS
    $(call MALI_LIBS_INSTALL_LIBS,$(TARGET_DIR))
    # The aarch64-v8.2a emulator drop is built on a527, whose blob declares
    # soname libmali.so.0, so its binaries need that filename to load here.
    ln -sf libmali.so.1 $(TARGET_DIR)/usr/lib/libmali.so.0

    # Install Vulkan ICD
    mkdir -p $(TARGET_DIR)/etc/vulkan/icd.d
    sed 's|@LIB@|/usr/lib/libmali.so.1|g' \
        $(@D)/data/vulkan/mali.json.in > $(TARGET_DIR)/etc/vulkan/icd.d/mali.json

    $(MALI_LIBS_INSTALL_WSI_TARGET)
endef

$(eval $(generic-package))
