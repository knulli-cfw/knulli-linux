################################################################################
#
# knulli-emulators-drop  --  standalone emulators and ports, built out of tree
#
# Installs the payload of the packages in emulators.set instead of compiling
# them.  They are ~24 minutes of a board build and change far less often than
# the rest of the image, so they do not belong in every build.
#
# This package has NO SOURCE.  The drop is produced by harvest-drop.py from a
# build made with BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS unset -- see
# "make <board>-emulators-drop" -- and lives in a cache outside output/ so it
# survives "make <board>-clean" and is shared by every board on the ABI.
#
# It carries no libraries.  SDL2, ffmpeg, python3 and the rest are core firmware
# on their own merits and keep being built per board; the few that existed only
# for the emulators are held in the image by the gate symbol's select list.
#
################################################################################

KNULLI_EMULATORS_DROP_VERSION = 1.0
KNULLI_EMULATORS_DROP_LICENSE = MIT
KNULLI_EMULATORS_DROP_SOURCE =

# The payload is prebuilt, but it lands next to libraries this image builds, so
# nothing may be installed before the image has them.
KNULLI_EMULATORS_DROP_DEPENDENCIES = toolchain

KNULLI_EMULATORS_DROP_PKGDIR = $(BR2_EXTERNAL_KNULLI_PATH)/package/emulators/knulli-emulators-drop

# Persistent, deliberately a sibling of output/ rather than inside it.
KNULLI_EMULATORS_DROP_CACHE = $(BR2_EXTERNAL_KNULLI_PATH)/emulators-cache

# The device -> profile map is libretro-super's devices/*.device, deliberately
# not a second copy: cores and emulators must not disagree about which ABI a
# board is.
KNULLI_EMULATORS_DROP_DEVICE = $(call qstrip,$(BR2_PACKAGE_KNULLI_EMULATORS_DROP_DEVICE))
KNULLI_EMULATORS_DROP_DEVICE_FILE = \
	$(BR2_EXTERNAL_KNULLI_PATH)/package/cores/libretro-super/overlay/devices/$(KNULLI_EMULATORS_DROP_DEVICE).device
KNULLI_EMULATORS_DROP_PROFILE = \
	$(shell awk '$$1=="PROFILE"{print $$2}' $(KNULLI_EMULATORS_DROP_DEVICE_FILE) 2>/dev/null)

# Keyed on the profile AND the GPU vendor, unlike the cores drop which is keyed
# on the profile alone.  Emulators link the vendor GL stack -- a Mali-harvested
# payload records NEEDED libmali.so.1, which a PowerVR or Adreno board does not
# ship.  Mali is the incumbent and keeps the unsuffixed directory so the
# existing drops stay valid.
KNULLI_EMULATORS_DROP_GPU = \
	$(shell awk '$$1=="GPU"{print $$2}' $(KNULLI_EMULATORS_DROP_DEVICE_FILE) 2>/dev/null)
KNULLI_EMULATORS_DROP_KEY = $(KNULLI_EMULATORS_DROP_PROFILE)$(if \
	$(filter-out mali,$(KNULLI_EMULATORS_DROP_GPU)),-$(KNULLI_EMULATORS_DROP_GPU))

KNULLI_EMULATORS_DROP_DROP = $(KNULLI_EMULATORS_DROP_CACHE)/drop/$(KNULLI_EMULATORS_DROP_KEY)

# EXCLUDE_EMULATOR lines in the .device file, naming BR2_PACKAGE_* symbols
# without the prefix.  The drop is keyed on the profile and the GPU, so it
# carries every emulator the reference board built -- which is how a board picks
# up emulators the "select BR2_PACKAGE_* if <target>" lines in
# knulli-system/Config.in never granted it.  Those selects are gated off by
# BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS, so the policy has to be reasserted
# here, against the fragment rather than against Kconfig.
KNULLI_EMULATORS_DROP_EXCLUDE = \
	$(shell awk '$$1=="EXCLUDE_EMULATOR"{print $$2}' $(KNULLI_EMULATORS_DROP_DEVICE_FILE) 2>/dev/null)

# A missing drop is a hard error, not a warning.  An image that silently builds
# without emulators looks fine until someone tries to launch one, and by then it
# has been flashed.
define KNULLI_EMULATORS_DROP_BUILD_CMDS
	$(Q)test -n "$(KNULLI_EMULATORS_DROP_DEVICE)" || { \
		echo "knulli-emulators-drop: BR2_PACKAGE_KNULLI_EMULATORS_DROP_DEVICE is not set for this board" >&2; \
		exit 1; }
	$(Q)test -n "$(KNULLI_EMULATORS_DROP_PROFILE)" || { \
		echo "knulli-emulators-drop: no PROFILE in $(KNULLI_EMULATORS_DROP_DEVICE_FILE)" >&2; \
		exit 1; }
	$(Q)test -d "$(KNULLI_EMULATORS_DROP_DROP)/payload" || { \
		echo "knulli-emulators-drop: no drop for $(KNULLI_EMULATORS_DROP_KEY)" >&2; \
		echo "  expected: $(KNULLI_EMULATORS_DROP_DROP)/payload" >&2; \
		echo "  refresh it with: make $(KNULLI_EMULATORS_DROP_DEVICE)-emulators-drop" >&2; \
		exit 1; }
	$(Q)cat $(KNULLI_EMULATORS_DROP_DROP)/drop.info
	$(Q)na=$(KNULLI_EMULATORS_DROP_DROP)/not-applicable.list; \
	test -f "$$na" || na=/dev/null; \
	missing=$$(sed -e 's/#.*//' -e 's/[[:space:]]*$$//' \
			$(KNULLI_EMULATORS_DROP_PKGDIR)/emulators.set \
		| grep -v '^$$' \
		| grep -vxF -f $(KNULLI_EMULATORS_DROP_DROP)/emulators.list \
		| grep -vxF -f "$$na" || true); \
	if [ -n "$$missing" ]; then \
		echo "" >&2; \
		echo "knulli-emulators-drop: the drop has no payload for:$$missing" >&2; \
		echo "" >&2; \
		echo "These are gated out of this build but absent from the drop, so the image" >&2; \
		echo "would ship without them.  The drop predates their addition to" >&2; \
		echo "emulators.set -- refresh it: make $(KNULLI_EMULATORS_DROP_DEVICE)-emulators-drop" >&2; \
		echo "" >&2; \
		exit 1; \
	fi
endef

# A plain recursive copy: harvest-drop.py already resolved every per-package
# decision, so nothing here knows about individual emulators, which is what
# stops this file rotting as emulators come and go.
#
# The soname check deliberately does NOT run here.  This package depends only on
# the toolchain, so buildroot is free to install it before the libraries the
# payload links against -- and it does, on a from-scratch build.  Checking here
# reported seven libraries as missing that were merely not installed yet.  The
# check belongs where the rootfs is complete: post-build-script.sh, which is also
# after the 32-bit layer is merged.
define KNULLI_EMULATORS_DROP_INSTALL_TARGET_CMDS
	cp -a $(KNULLI_EMULATORS_DROP_DROP)/payload/. $(TARGET_DIR)/
endef

# es_systems.yml gates standalone emulators on BR2_PACKAGE_* symbols that no
# longer exist once the gate removes the packages, exactly as it does for cores.
# knulli-es-system reads this fragment alongside .config; without it every
# system whose only emulator is in the drop disappears from EmulationStation,
# along with its roms/<system> folder.
KNULLI_EMULATORS_DROP_INSTALL_STAGING = YES
KNULLI_EMULATORS_DROP_ES_CONFIG = $(STAGING_DIR)/usr/share/knulli/emulators-drop.config

# sonames.list is staged for post-build-script.sh, which runs the check once the
# rootfs is complete.  Staging it rather than having post-build reach into the
# cache keeps the drop's location a detail of this file alone.
define KNULLI_EMULATORS_DROP_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(KNULLI_EMULATORS_DROP_DROP)/emulators.config \
		$(KNULLI_EMULATORS_DROP_ES_CONFIG)
	$(Q)for sym in "" $(KNULLI_EMULATORS_DROP_EXCLUDE); do \
		[ -n "$$sym" ] || continue; \
		sed -i "/^BR2_PACKAGE_$$sym=y\$$/d" $(KNULLI_EMULATORS_DROP_ES_CONFIG); \
		echo "knulli-emulators-drop: $$sym excluded for $(KNULLI_EMULATORS_DROP_DEVICE)"; \
	done
	$(INSTALL) -D -m 0644 $(KNULLI_EMULATORS_DROP_DROP)/sonames.list \
		$(STAGING_DIR)/usr/share/knulli/emulators-drop-sonames.list
endef

$(eval $(generic-package))
