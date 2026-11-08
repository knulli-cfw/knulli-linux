################################################################################
#
# knulli-armhf-drop  --  32-bit (armhf) runtime for a 64-bit image
#
# Installs the userspace of a <board>_armhf_libs build into /lib32 and
# /usr/lib32 instead of reaching into a second output/ tree from a post-build
# script.  Same arrangement as knulli-emulators-drop: the payload is built by
# "make <board>-armhf-drop", cached outside output/ so it survives
# "make <board>-clean", and a missing drop is an error rather than a shrug.
#
# What it replaces: board/scripts/install-32bit-libs.sh, which rsync'd out of
# output/<board>_armhf_libs/target at post-build time.  That only worked if the
# armhf build happened to be in the same tree, and it was wired for exactly one
# board -- post-build-script.sh called it under "if KNULLI_TARGET = RK3326", and
# passed it TARGET_DIR where the script expected the board name, so it took its
# "not found" path and skipped every time.
#
# This package has NO SOURCE.
#
################################################################################

KNULLI_ARMHF_DROP_VERSION = 1.0
KNULLI_ARMHF_DROP_LICENSE = MIT
KNULLI_ARMHF_DROP_SOURCE =

# The 32-bit layer sits beside the 64-bit libraries and must not land before
# them; toolchain is enough to order it after the sysroot exists.
KNULLI_ARMHF_DROP_DEPENDENCIES = toolchain

# Persistent, deliberately a sibling of output/ rather than inside it.
KNULLI_ARMHF_DROP_CACHE = $(BR2_EXTERNAL_KNULLI_PATH)/armhf-cache

# Keyed on the BOARD, not on an ABI profile -- see harvest-armhf.sh: each
# <board>_armhf_libs config pins that board's kernel headers and its own Mali
# userspace, so the payloads are not interchangeable between SoCs.
KNULLI_ARMHF_DROP_DEVICE = $(call qstrip,$(BR2_PACKAGE_KNULLI_ARMHF_DROP_DEVICE))
KNULLI_ARMHF_DROP_DROP = $(KNULLI_ARMHF_DROP_CACHE)/drop/$(KNULLI_ARMHF_DROP_DEVICE)

KNULLI_ARMHF_DROP_LOADER = ld-linux-armhf.so.3

# Everything this package installs is ARM, so check-bin-arch would reject all of
# it against the board's AArch64.  Exclude by path -- it is a prefix match, so
# directories only; the loader is handled as a symlink below.
KNULLI_ARMHF_DROP_BIN_ARCH_EXCLUDE = /lib32 /usr/lib32

define KNULLI_ARMHF_DROP_BUILD_CMDS
	$(Q)test -n "$(KNULLI_ARMHF_DROP_DEVICE)" || { \
		echo "knulli-armhf-drop: BR2_PACKAGE_KNULLI_ARMHF_DROP_DEVICE is not set for this board" >&2; \
		exit 1; }
	$(Q)test -d "$(KNULLI_ARMHF_DROP_DROP)" || { \
		echo "knulli-armhf-drop: no 32-bit drop for $(KNULLI_ARMHF_DROP_DEVICE)" >&2; \
		echo "  expected: $(KNULLI_ARMHF_DROP_DROP)" >&2; \
		echo "  refresh it with: make $(KNULLI_ARMHF_DROP_DEVICE)-armhf-drop" >&2; \
		exit 1; }
	$(Q)test -e "$(KNULLI_ARMHF_DROP_DROP)/$(KNULLI_ARMHF_DROP_LOADER)" || { \
		echo "knulli-armhf-drop: drop has no $(KNULLI_ARMHF_DROP_LOADER)" >&2; \
		echo "  it is incomplete -- rebuild: make $(KNULLI_ARMHF_DROP_DEVICE)-armhf-drop FORCE=1" >&2; \
		exit 1; }
	$(Q)cat $(KNULLI_ARMHF_DROP_DROP)/drop.info
endef

# /lib/ld-linux-armhf.so.3 is baked into every 32-bit binary's PT_INTERP, so it
# has to exist under that exact name.  The real file lives in /lib32 (covered by
# BIN_ARCH_EXCLUDE) and /lib holds a symlink to it: check-bin-arch skips
# symlinks outright, and the kernel resolves PT_INTERP through one just as well.
#
# The destinations are cleared first: "cp -a" preserves modes, and the payload
# has a 0444 file (lib/udev/hwdb.bin) that a second install cannot reopen.  It
# also drops files left over from an older drop.  Nothing else installs here.
define KNULLI_ARMHF_DROP_INSTALL_TARGET_CMDS
	rm -rf $(TARGET_DIR)/lib32 $(TARGET_DIR)/usr/lib32
	mkdir -p $(TARGET_DIR)/lib32 $(TARGET_DIR)/usr/lib32
	cp -a $(KNULLI_ARMHF_DROP_DROP)/lib/.     $(TARGET_DIR)/lib32/
	cp -a $(KNULLI_ARMHF_DROP_DROP)/usr-lib/. $(TARGET_DIR)/usr/lib32/
	$(INSTALL) -D -m 0755 $(KNULLI_ARMHF_DROP_DROP)/$(KNULLI_ARMHF_DROP_LOADER) \
		$(TARGET_DIR)/lib32/$(KNULLI_ARMHF_DROP_LOADER)
	ln -sf /lib32/$(KNULLI_ARMHF_DROP_LOADER) \
		$(TARGET_DIR)/lib/$(KNULLI_ARMHF_DROP_LOADER)
	$(Q)for d in /lib32 /usr/lib32 /usr/local/lib32; do \
		grep -qx "$$d" $(TARGET_DIR)/etc/ld.so.conf 2>/dev/null \
			|| echo "$$d" >> $(TARGET_DIR)/etc/ld.so.conf; \
	done
	echo armhf > $(TARGET_DIR)/etc/multiarch
endef

$(eval $(generic-package))
