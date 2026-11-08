################################################################################
#
# PowerVR GE8300_DRIVER GPU driver
#
################################################################################
# Version.: Commits on May 16, 2024
#POWERVR_GE8300_DRIVER_VERSION = 3334cfc9f363dae79c9107d43f8073e0c9db12e5
POWERVR_GE8300_DRIVER_VERSION = main
POWERVR_GE8300_DRIVER_SITE = https://github.com/knulli-cfw/ge8300-drivers.git
POWERVR_GE8300_DRIVER_SITE_METHOD = git

POWERVR_GE8300_DRIVER_LICENSE = Propietary

POWERVR_GE8300_DRIVER_INSTALL_STAGING = YES

# Same story for the blob's khronos headers: its vulkan/ set is 1.1.86 from
# 2018 and lands on top of vulkan-headers' 1.4.350.  Its vk_layer.h is not
# upstream's either -- it includes vk_layer_dispatch_table.h, which collides
# with the table vulkan-loader generates for itself, so the loader stops
# building the moment it is rebuilt after this package.  Everything else in
# there (EGL, GLES, KHR, CL) is what we actually want from the blob.
define POWERVR_GE8300_DRIVER_COPY_HEADERS
	cd $(@D)/3rdparty/include/khronos && \
	for d in *; do \
		case "$$d" in vulkan) continue ;; esac; \
		cp -rf "$$d" $(STAGING_DIR)/usr/include/; \
	done
endef

# The blob ships IMG's own libvulkan.so.1 -- a 24K stub that dlopens
# libVK_IMG.so directly.  vulkan-loader installs libvulkan.so.1 as a symlink to
# libvulkan.so.1.4.350, so a plain copy writes the stub through that link and
# replaces the real loader.  Everything still runs, because the stub forwards
# the core entry points, but there is no ICD enumeration and no layer support
# at all: implicit layers are silently ignored and VK_DRIVER_FILES does
# nothing.  Skip it and keep the loader; powervr_icd.json below is what points
# the loader at this driver.
define POWERVR_GE8300_DRIVER_COPY_LIBS
	cd $(@D)/fbdev/glibc/lib64 && \
	for f in *; do \
		case "$$f" in libvulkan.so*) continue ;; esac; \
		cp -a "$$f" $(1)/; \
	done
endef
POWERVR_GE8300_DRIVER_PROVIDES = libegl libgles libopencl

define POWERVR_GE8300_DRIVER_INSTALL_STAGING_CMDS
        mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig

	$(POWERVR_GE8300_DRIVER_COPY_HEADERS)

# The blob's khronos set omits GLES3/gl3ext.h, which Mali's ships and lightspark
# includes unconditionally.  Upstream's is an empty compatibility stub -- GLES3
# extension tokens live in gl2ext.h -- so shipping the stub is the whole fix.
	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/powervr-ge8300-driver/gl3ext.h \
		$(STAGING_DIR)/usr/include/GLES3/gl3ext.h

	$(call POWERVR_GE8300_DRIVER_COPY_LIBS,$(STAGING_DIR)/usr/lib)

        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/powervr-ge8300-driver/egl.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/egl.pc
        $(INSTALL) -D -m 0644  $(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/powervr-ge8300-driver/glesv2.pc \
                $(STAGING_DIR)/usr/lib/pkgconfig/glesv2.pc

endef

# Versioned sonames for the GL/EGL libraries.
#
# libretro cores are built once per CPU/ABI profile and shared by every board on
# that profile.  For aarch64-v8a that is h700, rk3326 and rk3576 -- all Mali,
# whose libraries carry versioned sonames -- plus a133, which is the only
# PowerVR board in the set.  A core linked against Mali records
# "NEEDED libGLESv2.so.2 / libEGL.so.1", and the loader resolves that BY
# FILENAME: if this driver only installs unversioned libGLESv2.so, the core
# cannot be dlopen'd here at all, and RetroArch reports it as a generic
# "failed to open core" with nothing about the missing library.
#
# Symlinks are the whole fix for that direction.  They deliberately do NOT
# change what a core built *against* this driver records -- that comes from the
# library's DT_SONAME, not from its filename -- but we never build cores
# against this sysroot, so that direction does not arise.
#
# libmali.so.1 is the same problem one step further out.  The standalone emulator
# drop is built once per ABI on the reference board, which is Mali, and on Mali
# libmali is the single blob behind EGL and GLES -- so six of those binaries
# (cannonball, flycast, lightspark, ppsspp, thextech and drastic's private SDL2)
# record "NEEDED libmali.so.1" and will not load here without that filename.
#
# Versioned .so.1, not .so.0: the reference board is rk3576, whose mali-libs
# ships libmali.so.1.  h700's mali-g31-fbdev declares .so.0 and links .so.1 to
# its own blob for the same reason.
#
# A link is sufficient, not a bodge: those binaries also record libEGL.so.1 and
# libGLESv2.so.2, and the loader resolves symbols across every loaded object, so
# the EGL and GLES entry points they call are served by this driver's own
# libraries either way.  libmali.so.0 only has to resolve as a filename.
#
# Written defensively: create a link only when the versioned name is absent and
# the unversioned one exists, so a future blob that already ships proper
# sonames is left untouched.  Order matters -- libmali.so.0 points at the
# libGLESv2.so.2 the earlier pair creates.
define POWERVR_GE8300_DRIVER_LINK_SONAMES
	cd $(TARGET_DIR)/usr/lib && \
	for pair in libEGL.so:libEGL.so.1 \
	            libGLESv2.so:libGLESv2.so.2 \
	            libGLESv1_CM.so:libGLESv1_CM.so.1 \
	            libGLESv2.so.2:libmali.so.1; do \
		plain=$${pair%%:*}; vers=$${pair##*:}; \
		if [ ! -e "$$vers" ] && [ -e "$$plain" ]; then \
			ln -sf "$$plain" "$$vers"; \
			echo "powervr-ge8300: linked $$vers -> $$plain"; \
		fi; \
	done
endef

define POWERVR_GE8300_DRIVER_INSTALL_TARGET_CMDS
        mkdir -p $(TARGET_DIR)/usr/lib

	$(call POWERVR_GE8300_DRIVER_COPY_LIBS,$(TARGET_DIR)/usr/lib)

	cp $(@D)/fbdev/glibc/bin/pvrsrvctl $(TARGET_DIR)/usr/bin/

	$(INSTALL) -D -m 0644 \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/gpu/powervr-ge8300-driver/powervr_icd.json \
		$(TARGET_DIR)/usr/share/vulkan/icd.d/powervr_icd.json

	$(POWERVR_GE8300_DRIVER_LINK_SONAMES)
endef

$(eval $(generic-package))

