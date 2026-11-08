################################################################################
#
# libretro-super  --  every libretro core, built out of tree
#
# Replaces Buildroot's ~140 individual libretro-* packages.  Those are all
# switched off by BR2_PACKAGE_KNULLI_EXTERNAL_LIBRETRO_CORES, which guards every
# "select BR2_PACKAGE_LIBRETRO_*" in package/system/knulli-system/Config.in.
#
# This package has NO SOURCE and BUILDS NOTHING.  The drop is produced by
# "make <board>-cores-drop" -- which runs build-cores.sh against the profile's
# reference sysroot -- and lives in a cache outside output/ so it survives
# "make <board>-clean" and is shared by every board on the ABI.  All this
# package does is check the drop is there and install it.
#
# The drop is keyed ON THE ABI PROFILE, not the board.  One
# "make h700-cores-drop" serves h700, a133, rk3326 and rk3576; they then build
# images without compiling a core.
#
################################################################################

# The upstream rev the drop is built from.  Nothing here consumes it -- it is
# read out of this file by %-cores-drop, so the pin stays with the package it
# describes rather than becoming a second copy in the top-level Makefile.
#
# Full 40 characters, never abbreviated: build-cores.sh feeds this straight to
# "git checkout", so a wrong tail is not caught until the first drop is built on
# a machine whose cache has to be re-cloned.
LIBRETRO_SUPER_VERSION = 9912e8445401d877c55172e001e7651cb98ce4fb
LIBRETRO_SUPER_SITE = https://github.com/libretro/libretro-super.git
LIBRETRO_SUPER_LICENSE = MIT
LIBRETRO_SUPER_SOURCE =

# The payload is prebuilt, but it lands next to libraries this image builds, so
# nothing may be installed before the image has them.  Same reason
# knulli-emulators-drop depends on the toolchain.
LIBRETRO_SUPER_DEPENDENCIES = toolchain

LIBRETRO_SUPER_PKGDIR = $(BR2_EXTERNAL_KNULLI_PATH)/package/cores/libretro-super

# Persistent, deliberately a sibling of output/ rather than inside it.
LIBRETRO_SUPER_CACHE = $(BR2_EXTERNAL_KNULLI_PATH)/cores-cache

# Which device this board is, and hence which ABI profile it consumes.  The
# device -> profile map is the overlay's devices/*.device, so knulli and
# libretro-super cannot disagree about it: there is one file, and it lives with
# the profiles it names.
LIBRETRO_SUPER_DEVICE = $(call qstrip,$(BR2_PACKAGE_LIBRETRO_SUPER_DEVICE))
LIBRETRO_SUPER_DEVICE_FILE = $(LIBRETRO_SUPER_PKGDIR)/overlay/devices/$(LIBRETRO_SUPER_DEVICE).device
LIBRETRO_SUPER_PROFILE = $(shell awk '$$1=="PROFILE"{print $$2}' $(LIBRETRO_SUPER_DEVICE_FILE) 2>/dev/null)

LIBRETRO_SUPER_DROP = $(LIBRETRO_SUPER_CACHE)/drop/$(LIBRETRO_SUPER_PROFILE)

# EXCLUDE_CORE lines in the .device file: cores this device must not offer.  The
# drop is keyed on the ABI profile, so a board receives every core its profile
# builds -- this is where the per-board policy that used to live in the
# "select BR2_PACKAGE_LIBRETRO_* if <target>" lines comes back.  Excluded cores
# are left out of the symbol fragment and pruned from the cores squashfs.
LIBRETRO_SUPER_EXCLUDE = $(shell awk '$$1=="EXCLUDE_CORE"{print $$2}' $(LIBRETRO_SUPER_DEVICE_FILE) 2>/dev/null)

# The profile's reference sysroot is resolved by %-cores-drop, not here -- this
# package never compiles, so it has no use for it.

# A missing drop is a hard error, not a build step.  Compiling ~140 cores as a
# side effect of an image build is the coupling this package exists to remove:
# the drop is shared by every board on the ABI, so two image builds on the same
# profile would race on one cache, and an hour of core compilation would appear
# inside a build that was asked for an image.  Same rule as
# knulli-emulators-drop -- refreshing a drop is its own explicit target.
define LIBRETRO_SUPER_BUILD_CMDS
	$(Q)test -n "$(LIBRETRO_SUPER_DEVICE)" || { \
		echo "libretro-super: BR2_PACKAGE_LIBRETRO_SUPER_DEVICE is not set for this board" >&2; \
		exit 1; }
	$(Q)test -n "$(LIBRETRO_SUPER_PROFILE)" || { \
		echo "libretro-super: no PROFILE in $(LIBRETRO_SUPER_DEVICE_FILE)" >&2; \
		exit 1; }
	$(Q)test -d "$(LIBRETRO_SUPER_DROP)/cores" || { \
		echo "libretro-super: no drop for profile $(LIBRETRO_SUPER_PROFILE)" >&2; \
		echo "  expected: $(LIBRETRO_SUPER_DROP)/cores" >&2; \
		echo "  refresh it with: make $(LIBRETRO_SUPER_DEVICE)-cores-drop" >&2; \
		exit 1; }
	$(Q)if [ -f "$(LIBRETRO_SUPER_DROP)/PARTIAL" ]; then \
		echo "" >&2; \
		echo "libretro-super: WARNING -- this drop is PARTIAL.  The image will ship" >&2; \
		echo "without these cores, and the systems whose only core is one of them" >&2; \
		echo "will not appear in EmulationStation:" >&2; \
		sed 's/^/  /' $(LIBRETRO_SUPER_DROP)/PARTIAL >&2; \
		echo "" >&2; \
		echo "Rerun make $(LIBRETRO_SUPER_DEVICE)-cores-drop once they build; it" >&2; \
		echo "retries only the failures." >&2; \
		echo "" >&2; \
	fi
endef

# es_systems.yml gates every core on a BR2_PACKAGE_LIBRETRO_* symbol, and the
# gate that turns the individual packages off also removes those symbols from
# .config -- so without this, EmulationStation shows no libretro system and
# knulli-es-system creates none of the matching datainit/roms/<system> folders.
# The fragment puts the symbols back from what the drop really contains, which
# also makes the system list follow the cores instead of the Kconfig selects.
# knulli-es-system depends on this package for exactly this file.
LIBRETRO_SUPER_INSTALL_STAGING = YES
LIBRETRO_SUPER_ES_CONFIG = $(STAGING_DIR)/usr/share/knulli/libretro-cores.config
LIBRETRO_SUPER_ES_CORELIST = $(STAGING_DIR)/usr/share/knulli/libretro-cores.list

define LIBRETRO_SUPER_INSTALL_STAGING_CMDS
	$(Q)$(LIBRETRO_SUPER_PKGDIR)/gen-es-config.sh \
		$(LIBRETRO_SUPER_DROP) \
		$(LIBRETRO_SUPER_PKGDIR)/cores.symbols \
		$(LIBRETRO_SUPER_ES_CONFIG) \
		$(LIBRETRO_SUPER_ES_CORELIST) \
		"$(LIBRETRO_SUPER_EXCLUDE)"
endef

# The cores do NOT go into the rootfs.  They are staged here and turned into
# their own squashfs by post-image-script.sh, which the image mounts over
# /usr/lib/libretro at boot (board/fsoverlay/etc/init.d/S07mount-cores).  The
# squashfs root IS that directory, so the cores sit at the top level of it.
LIBRETRO_SUPER_CORES_ROOT = $(BINARIES_DIR)/cores-root
LIBRETRO_SUPER_MANIFEST = $(BINARIES_DIR)/cores.manifest

# The drop is laid out so this is a plain recursive copy.  Every per-core
# decision -- renames (mednafen_pce -> pce), exclude rules (fbneo's "light"
# DATs), which payload comes from which checkout -- was already resolved by
# make-drop.sh, where the core checkouts are.  Nothing here knows about
# individual cores, which is what stops this file rotting as cores come and go.
#
# assets/ and the knulli.list payload stay in the rootfs: they are datainit,
# .info files and evmapy keys, none of which the mount point covers.
define LIBRETRO_SUPER_INSTALL_TARGET_CMDS
	rm -rf $(LIBRETRO_SUPER_CORES_ROOT)
	mkdir -p $(LIBRETRO_SUPER_CORES_ROOT)
	cp -a $(LIBRETRO_SUPER_DROP)/cores/. $(LIBRETRO_SUPER_CORES_ROOT)/
	cd $(LIBRETRO_SUPER_CORES_ROOT) && for so in *_libretro.so; do \
		grep -qx "$$so" $(LIBRETRO_SUPER_ES_CORELIST) || rm -f "$$so"; \
	done
	$(LIBRETRO_SUPER_PKGDIR)/gen-cores-manifest.sh \
		$(LIBRETRO_SUPER_CORES_ROOT) \
		$(LIBRETRO_SUPER_PROFILE) \
		$(LIBRETRO_SUPER_VERSION) \
		$(LIBRETRO_SUPER_MANIFEST)
	$(INSTALL) -D -m 0644 $(LIBRETRO_SUPER_MANIFEST) \
		$(LIBRETRO_SUPER_CORES_ROOT)/cores.manifest
	mkdir -p $(TARGET_DIR)/usr/lib/libretro
	if [ -d $(LIBRETRO_SUPER_DROP)/assets ]; then \
		cp -a $(LIBRETRO_SUPER_DROP)/assets/. $(TARGET_DIR)/; \
	fi
	$(LIBRETRO_SUPER_INSTALL_KNULLI_PAYLOAD)
endef

# knulli.list is payload the drop deliberately does NOT carry: evmapy key maps
# and knulli's own flycast .info files, which live in the knulli tree.  Copying
# them into the drop would create a second copy that drifts from the one
# maintained here, so they are installed from source at this point instead.
# Fields: <core> <path relative to this checkout> <path under TARGET_DIR>.
# src may be a directory -- mame ships its lua plugins that way -- and dest is
# then that directory, as cores.assets specifies.
define LIBRETRO_SUPER_INSTALL_KNULLI_PAYLOAD
	if [ -f $(LIBRETRO_SUPER_DROP)/knulli.list ]; then \
		while read -r core src dest; do \
			[ -n "$$dest" ] || continue; \
			if [ -d "$(BR2_EXTERNAL_KNULLI_PATH)/$$src" ]; then \
				mkdir -p "$(TARGET_DIR)/$$dest"; \
				cp -a "$(BR2_EXTERNAL_KNULLI_PATH)/$$src/." \
					"$(TARGET_DIR)/$$dest/"; \
			elif [ -e "$(BR2_EXTERNAL_KNULLI_PATH)/$$src" ]; then \
				$(INSTALL) -D -m 0644 "$(BR2_EXTERNAL_KNULLI_PATH)/$$src" \
					"$(TARGET_DIR)/$$dest"; \
			else \
				echo "libretro-super: WARNING missing knulli payload for $$core: $$src" >&2; \
			fi; \
		done < $(LIBRETRO_SUPER_DROP)/knulli.list; \
	fi
endef

$(eval $(generic-package))
