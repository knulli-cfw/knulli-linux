################################################################################
#
# mali-kbase-sunxi
#
################################################################################

MALI_KBASE_SUNXI_VERSION = 1.0
MALI_KBASE_SUNXI_SOURCE =
MALI_KBASE_SUNXI_LICENSE = GPL-2.0
MALI_KBASE_SUNXI_DEPENDENCIES = linux

# orangepi H618 tree (h700) by default.  The orangepi sun55iw3 tree (a527) keeps
# it in bsp/modules/gpu with its GPU Kconfig commented out, so the type is
# passed; there only "build" makes the .ko.  r42p0, as the stock module.
ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_T527),y)
MALI_KBASE_SUNXI_SRC = bsp/modules/gpu
MALI_KBASE_SUNXI_TARGET = build GPU_TYPE=mali-g57 KERNEL_SRC=$(LINUX_DIR)
MALI_KBASE_SUNXI_KO = mali-valhall/driver/drivers/gpu/arm/midgard/mali_kbase.ko
MALI_KBASE_SUNXI_DEST = lib/modules/$(LINUX_VERSION_PROBED)/mali_kbase.ko
else
MALI_KBASE_SUNXI_SRC = modules/gpu
MALI_KBASE_SUNXI_TARGET = modules_install
MALI_KBASE_SUNXI_KO = mali-bifrost/driver/drivers/gpu/arm/midgard/mali_kbase.ko
MALI_KBASE_SUNXI_DEST = lib/modules/mali_kbase.ko
endif

# The source ships inside the BSP kernel tree (modules/gpu), not as a download.
# Copy it out once linux is built, so the objects stay out of the kernel tree.
define MALI_KBASE_SUNXI_CONFIGURE_CMDS
	rm -rf $(@D)/gpu
	cp -a $(LINUX_DIR)/$(MALI_KBASE_SUNXI_SRC) $(@D)/gpu
endef

# Allwinner's modules/gpu/Makefile picks the driver from CONFIG_SUNXI_GPU_TYPE
# in the kernel .config ("mali-g31" -> mali-bifrost).  modules_install builds
# the .ko and, with no MODULE_INS_DIR, copies nothing.  MAKE1: each of its two
# .ko targets runs the same "make -j -C driver" recipe, and two of those at
# once race on the .tmp_*.ver files.  KCFLAGS demotes the gcc 14 errors every
# vendor tree here trips over.
MALI_KBASE_SUNXI_KCFLAGS = \
	-Wno-error=implicit-function-declaration -Wno-error=implicit-int \
	-Wno-error=int-conversion -Wno-error=incompatible-pointer-types \
	-Wno-error=return-mismatch -Wno-error=declaration-missing-parameter-type

define MALI_KBASE_SUNXI_BUILD_CMDS
	$(LINUX_MAKE_ENV) $(MAKE1) -C $(@D)/gpu $(MALI_KBASE_SUNXI_TARGET) \
		LICHEE_KDIR=$(LINUX_DIR) $(LINUX_MAKE_FLAGS) \
		KCFLAGS="$(MALI_KBASE_SUNXI_KCFLAGS)"
endef

# The paths rcS insmods.  h700: /lib/modules/mali_kbase.ko, outside depmod's
# reach on purpose, the prebuilt it replaces lived there too.
define MALI_KBASE_SUNXI_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 \
		$(@D)/gpu/$(MALI_KBASE_SUNXI_KO) \
		$(TARGET_DIR)/$(MALI_KBASE_SUNXI_DEST)
	$(TARGET_CROSS)strip --strip-debug $(TARGET_DIR)/$(MALI_KBASE_SUNXI_DEST)
endef

$(eval $(generic-package))
