PROJECT_DIR    := $(shell pwd)
DL_DIR         ?= $(PROJECT_DIR)/dl
OUTPUT_DIR     ?= $(PROJECT_DIR)/output
CCACHE_DIR     ?= $(PROJECT_DIR)/buildroot-ccache
LOCAL_MK       ?= $(PROJECT_DIR)/knulli.mk
EXTRA_OPTS     ?=
DOCKER_OPTS    ?=
MAKE_JLEVEL    ?= $(shell nproc)
BATCH_MODE     ?=
PARALLEL_BUILD ?=
DIRECT_BUILD   ?=

-include $(LOCAL_MK)

ifdef PARALLEL_BUILD
	EXTRA_OPTS +=  BR2_PER_PACKAGE_DIRECTORIES=y
	MAKE_OPTS  += -j$(MAKE_JLEVEL)
endif

TARGETS := $(sort $(shell find $(PROJECT_DIR)/configs/ -name 'k*.board' | sed -n 's/.*\/knulli-\(.*\).board/\1/p'))
UID  := $(shell id -u)
GID  := $(shell id -g)
OS := $(shell uname)

ifeq ($(OS),Darwin)
$(if $(shell which gfind 2>/dev/null),,$(error "gfind not found! Please install findutils from Homebrew."))
FIND ?= gfind
else
FIND ?= find
endif

UC = $(shell echo '$1' | tr '[:lower:]' '[:upper:]')

# define build command based on whether we are building direct or inside a docker build container
ifdef DIRECT_BUILD
	# let buildroot know about our overrides
	BR2_DL_DIR     := $(DL_DIR)
	BR2_CCACHE_DIR := $(CCACHE_DIR)

define MAKE_BUILDROOT
	make $(MAKE_OPTS) O=$(OUTPUT_DIR)/$* \
		BR2_EXTERNAL=$(PROJECT_DIR) \
		-C $(PROJECT_DIR)/buildroot
endef

# Where PROJECT_DIR appears to a command running in the build environment.  Used
# by the drop targets, which run a script rather than buildroot and so have to
# spell the path themselves.
BUILD_ENV_DIR := $(PROJECT_DIR)

else # DIRECT_BUILD
	DOCKER         ?= docker

	ifndef BATCH_MODE
		DOCKER_OPTS += -i
	endif

	DOCKER_REPO    ?= knulli
	IMAGE_NAME     ?= knulli-build

define RUN_DOCKER
	$(DOCKER) run -t --init --rm \
		-e HOME \
		-v $(PROJECT_DIR):/build \
		-v $(DL_DIR):/build/buildroot/dl \
		-v $(OUTPUT_DIR)/$*:/$* \
		-v $(CCACHE_DIR):$(HOME)/.buildroot-ccache \
		-w /$* \
		-v /etc/passwd:/etc/passwd:ro \
		-v /etc/group:/etc/group:ro \
		-u $(UID):$(GID) \
		$(DOCKER_OPTS) \
		$(DOCKER_REPO)/$(IMAGE_NAME)
endef

define MAKE_BUILDROOT
	$(RUN_DOCKER) make $(MAKE_OPTS) O=/$* \
			BR2_EXTERNAL=/build -C \
			/build/buildroot
endef

BUILD_ENV_DIR := /build

endif # DIRECT_BUILD

# Prefix that puts a plain command in the same environment buildroot builds in:
# the container, or nothing at all when building direct.
RUN_IN_BUILD_ENV = $(if $(DIRECT_BUILD),,$(RUN_DOCKER))

vars:
	@echo "Supported targets:  $(TARGETS)"
	@echo "Project directory:  $(PROJECT_DIR)"
	@echo "Download directory: $(DL_DIR)"
	@echo "Build directory:    $(OUTPUT_DIR)"
	@echo "ccache directory:   $(CCACHE_DIR)"
	@echo "Extra options:      $(EXTRA_OPTS)"
ifndef DIRECT_BUILD
	@echo "Docker repo/image:  $(DOCKER_REPO)/$(IMAGE_NAME)"
	@echo "Docker options:     $(DOCKER_OPTS)"
endif
	@echo "Make options:       $(MAKE_OPTS)"

_check_docker:
	$(if $(shell which $(DOCKER) 2>/dev/null),, $(error "$(DOCKER) not found!"))
	$(if $(DIRECT_BUILD),$(error "Not a docker environment!"))

build-docker-image: _check_docker
	$(DOCKER) build . -t $(DOCKER_REPO)/$(IMAGE_NAME)
	@touch .ba-docker-image-available

.ba-docker-image-available: _check_docker
	@$(DOCKER) pull $(DOCKER_REPO)/$(IMAGE_NAME)
	@touch .ba-docker-image-available

knulli-docker-image: $(if $(DIRECT_BUILD),,$(.ba-docker-image-available))

update-docker-image: _check_docker
	-@rm .ba-docker-image-available > /dev/null
	@$(MAKE) knulli-docker-image

publish-docker-image: _check_docker
	@$(DOCKER) push $(DOCKER_REPO)/$(IMAGE_NAME):latest

output-dir-%: %-supported
	@mkdir -p $(OUTPUT_DIR)/$*

ccache-dir:
	@mkdir -p $(CCACHE_DIR)

dl-dir:
	@mkdir -p $(DL_DIR)

%-supported:
	$(if $(findstring $*, $(TARGETS)),,$(error "$* not supported!"))

%-clean: knulli-docker-image output-dir-%
	@$(MAKE_BUILDROOT) clean

# DEFCONFIG_SED edits the generated defconfig before buildroot reads it.  Used by
# %-emulators-drop to build with the emulators back in, from the same board
# config the images use -- so the drop cannot drift from the board it serves.
%-config: knulli-docker-image output-dir-%
	@$(PROJECT_DIR)/configs/createDefconfig.sh $(PROJECT_DIR)/configs/knulli-$*
	$(if $(DEFCONFIG_SED),@sed -i '$(DEFCONFIG_SED)' $(PROJECT_DIR)/configs/knulli-$*_defconfig)
	@for opt in $(EXTRA_OPTS); do \
		echo $$opt >> $(PROJECT_DIR)/configs/knulli-$*_defconfig ; \
	done
	@$(MAKE_BUILDROOT) knulli-$*_defconfig

%-build: knulli-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) $(CMD)

%-source: knulli-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) source

%-show-build-order: knulli-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) show-build-order

%-kernel: knulli-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) linux-menuconfig

# force -j1 or graph-depends python script will bail
%-graph-depends: knulli-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) -j1 BR2_GRAPH_OUT=svg graph-depends

%-shell: knulli-docker-image output-dir-% _check_docker
	$(if $(BATCH_MODE),$(if $(CMD),,$(error "not supported in BATCH_MODE if CMD not specified!")),)
	@$(RUN_DOCKER) $(CMD)

%-ccache-stats: knulli-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) ccache-stats

%-build-cmd:
	@echo $(MAKE_BUILDROOT)

# Cores, emulators and the armhf runtime come from prebuilt drops rather than
# from the image build.  See docs/build-drops.md.
CORES_DROP_PKGDIR  = $(PROJECT_DIR)/package/cores/libretro-super
CORES_DROP_OVERLAY = $(CORES_DROP_PKGDIR)/overlay

# In docker only PROJECT_DIR is mounted whole, so another board's output is
# reachable only at its default place under it -- the same assumption
# libretro-super.mk already documents for LIBRETRO_SUPER_SYSROOT_BIN.
CORES_DROP_OUTPUT = $(if $(DIRECT_BUILD),$(OUTPUT_DIR),$(BUILD_ENV_DIR)/output)

# Build far enough to have a sysroot, then stop: no rootfs, no images.  Breaks
# the deadlock where %-cores-drop needs a sysroot but the image needs the drop.
SYSROOT_EXTRA_OPTS = \
	BR2_PACKAGE_LIBRETRO_SUPER=n \
	BR2_PACKAGE_KNULLI_EMULATORS_DROP=n \
	BR2_PACKAGE_KNULLI_ARMHF_DROP=n

%-sysroot: %-supported knulli-docker-image ccache-dir dl-dir
	@$(MAKE) $*-config EXTRA_OPTS="$(EXTRA_OPTS) $(SYSROOT_EXTRA_OPTS)"
	@$(MAKE_BUILDROOT) target-finalize staging-finalize

# Which board's sysroot the cores link against.  From the profile, not $*.
define cores_sysroot_board
profile=$$(awk '$$1=="PROFILE"{print $$2}' \
		$(CORES_DROP_OVERLAY)/devices/$*.device 2>/dev/null); \
test -n "$$profile" || { echo "no PROFILE for $* in devices/$*.device" >&2; exit 1; }; \
sysroot_board=$$(awk '$$1=="SYSROOT_BOARD"{print $$2}' \
		$(CORES_DROP_OVERLAY)/profiles/$$profile.profile 2>/dev/null); \
test -n "$$sysroot_board" || { echo "no SYSROOT_BOARD in $$profile.profile" >&2; exit 1; }
endef

# Everything a board needs, in order, from nothing.  For CI or a full build.
# Every step is a no-op when already satisfied, so a rerun resumes.
%-bootstrap: %-supported
	@$(cores_sysroot_board); \
	echo "bootstrap: $* -> sysroot from $$sysroot_board"; \
	$(MAKE) $$sysroot_board-sysroot
	@$(MAKE) $*-cores-drop
	@$(MAKE) $*-emulators-drop
	@if test -f $(PROJECT_DIR)/configs/knulli-$*_armhf_libs.board; then \
		$(MAKE) $*-armhf-drop; \
	else \
		echo "bootstrap: $* has no 32-bit companion config -- skipping armhf-drop"; \
	fi
	@$(MAKE) $*-build

# Refresh the libretro core drop for this board's profile.  Runs build-cores.sh
# directly, not buildroot.  FORCE=1 / UPDATE=1 / REQUIRE_ALL=1, see docs.
%-cores-drop: %-supported knulli-docker-image output-dir-%
	@device_file=$(CORES_DROP_OVERLAY)/devices/$*.device; \
	profile=$$(awk '$$1=="PROFILE"{print $$2}' $$device_file 2>/dev/null); \
	test -n "$$profile" || { \
		echo "cores-drop: no PROFILE for $* in $$device_file" >&2; \
		exit 1; }; \
	profile_file=$(CORES_DROP_OVERLAY)/profiles/$$profile.profile; \
	sysroot_board=$$(awk '$$1=="SYSROOT_BOARD"{print $$2}' $$profile_file 2>/dev/null); \
	test -n "$$sysroot_board" || { \
		echo "cores-drop: no SYSROOT_BOARD in $$profile_file" >&2; \
		exit 1; }; \
	test -d $(OUTPUT_DIR)/$$sysroot_board/host/bin || { \
		echo "cores-drop: profile $$profile builds against $$sysroot_board's sysroot," >&2; \
		echo "  which has not been built: $(OUTPUT_DIR)/$$sysroot_board/host/bin" >&2; \
		echo "" >&2; \
		echo "  The reference board is named in the profile so the drop is the same" >&2; \
		echo "  whichever board triggers it.  Run: make $$sysroot_board-sysroot" >&2; \
		exit 1; }; \
	rev=$$(sed -n 's/^LIBRETRO_SUPER_VERSION *= *//p' \
		$(CORES_DROP_PKGDIR)/libretro-super.mk); \
	echo "cores-drop: $* -> profile $$profile (sysroot from $$sysroot_board)"; \
	$(RUN_IN_BUILD_ENV) env LIBRETRO_SUPER_FORCE=$(FORCE) \
		LIBRETRO_SUPER_UPDATE=$(UPDATE) \
		LIBRETRO_SUPER_REQUIRE_ALL=$(REQUIRE_ALL) \
		$(BUILD_ENV_DIR)/package/cores/libretro-super/build-cores.sh \
		$$profile \
		$(BUILD_ENV_DIR)/cores-cache \
		$(CORES_DROP_OUTPUT)/$$sysroot_board/host/bin \
		$(BUILD_ENV_DIR)/package/cores/libretro-super/overlay \
		$(BUILD_ENV_DIR)/package/cores/libretro-super/super-patches \
		$$rev

# Refresh the emulator drop for this board's (profile, GPU).
#
# A separate output dir, and never an image build's: harvest-drop.py credits
# files to packages by diffing target/, so a tree with a drop installed harvests
# an incomplete payload.  It refuses such a tree.
EMULATORS_DROP_OUTPUT ?= $(OUTPUT_DIR)/emulators-drop
EMULATORS_DROP_DIR    ?= $(EMULATORS_DROP_OUTPUT)/$*

EMULATORS_DROP_HARVEST = $(PROJECT_DIR)/package/emulators/knulli-emulators-drop/harvest-drop.py
EMULATORS_DROP_SET     = $(PROJECT_DIR)/package/emulators/knulli-emulators-drop/emulators.set
EMULATORS_DROP_PKGDIRS = \
	--pkgdirs $(PROJECT_DIR)/batocera/package/batocera/emulators \
	--pkgdirs $(PROJECT_DIR)/batocera/package/batocera/ports \
	--pkgdirs $(PROJECT_DIR)/batocera/package/batocera/libraries \
	--pkgdirs $(PROJECT_DIR)/package/emulators \
	--pkgdirs $(PROJECT_DIR)/package/emulators/ports

EMULATORS_DROP_GATE_OFF = DEFCONFIG_SED='/BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS/d'

EMULATORS_DROP_REFERENCE = \
	$(PROJECT_DIR)/package/emulators/knulli-emulators-drop/reference-board.sh \
	$(PROJECT_DIR)/package/cores/libretro-super/overlay

# Asking from a consumer board is fine -- redirect to the reference board rather
# than refuse, and decide before building rather than at harvest time.
%-emulators-drop: %-supported
	@ref=$$($(EMULATORS_DROP_REFERENCE) $*) || exit 1; \
	if [ "$$ref" != "$*" ]; then \
		echo "emulators-drop: $* consumes the drop built on $$ref -- refreshing it there."; \
	fi; \
	$(MAKE) $$ref-emulators-drop-run

# Gate-off config, then the emulators.set packages this board enables, by name.
# Not one $(MAKE) call: the config must exist before the list can be computed.
%-emulators-drop-run: %-supported %-emulators-reference
	@$(MAKE) $*-config OUTPUT_DIR=$(EMULATORS_DROP_OUTPUT) $(EMULATORS_DROP_GATE_OFF)
	@targets=$$(python3 $(EMULATORS_DROP_HARVEST) --print-targets \
		--config $(EMULATORS_DROP_DIR)/.config \
		--set $(EMULATORS_DROP_SET) $(EMULATORS_DROP_PKGDIRS)); \
	test -n "$$targets" || { echo "emulators-drop: no packages to build" >&2; exit 1; }; \
	echo "emulators-drop: building $$(echo $$targets | wc -w) packages and their dependencies"; \
	$(MAKE) $*-build OUTPUT_DIR=$(EMULATORS_DROP_OUTPUT) \
		$(EMULATORS_DROP_GATE_OFF) CMD="$$targets"
	@$(MAKE) $*-emulators-harvest

# The drop must be harvested on the profile's reference board: the sysroot and
# GPU stack leak into the payload via the sonames it records.
%-emulators-reference: %-supported
	@ref=$$($(EMULATORS_DROP_REFERENCE) $*) || exit 1; \
	if [ "$$ref" != "$*" ]; then \
		echo "emulators-drop: $* is not the reference board ($$ref is)." >&2; \
		echo "  Harvesting here would tie the drop to $*'s sysroot and GPU stack." >&2; \
		echo "  Run: make $$ref-emulators-drop" >&2; \
		exit 1; \
	fi

%-emulators-harvest: %-supported %-emulators-reference
	@python3 $(EMULATORS_DROP_HARVEST) \
		--output-dir $(EMULATORS_DROP_DIR) \
		--profile $$(awk '$$1=="PROFILE"{p=$$2} $$1=="GPU"{g=$$2} \
			END{if (g=="" || g=="mali") print p; else print p "-" g}' \
			$(PROJECT_DIR)/package/cores/libretro-super/overlay/devices/$*.device) \
		--cache $(PROJECT_DIR)/emulators-cache \
		--set $(EMULATORS_DROP_SET) $(EMULATORS_DROP_PKGDIRS) \
		--readelf $(EMULATORS_DROP_DIR)/host/bin/$$(ls $(EMULATORS_DROP_DIR)/host/bin | grep -m1 -- '-readelf$$')

# Refresh the 32-bit (armhf) runtime drop.  Keyed on the BOARD, not the ABI
# profile: each _armhf_libs config pins its own kernel headers and Mali stack.
ARMHF_DROP_PKGDIR  = $(PROJECT_DIR)/package/system/knulli-armhf-drop
ARMHF_DROP_HARVEST = $(ARMHF_DROP_PKGDIR)/harvest-armhf.sh
ARMHF_DROP_CACHE   = $(PROJECT_DIR)/armhf-cache

%-armhf-drop: %-supported
	@test -f $(PROJECT_DIR)/configs/knulli-$*_armhf_libs.board || { \
		echo "armhf-drop: $* has no 32-bit companion config" >&2; \
		echo "  expected: configs/knulli-$*_armhf_libs.board" >&2; \
		exit 1; }
	@$(MAKE) $*_armhf_libs-build
	@$(ARMHF_DROP_HARVEST) $* $(OUTPUT_DIR)/$*_armhf_libs/target $(ARMHF_DROP_CACHE)

%-cleanbuild: %-clean %-build
	@echo

%-pkg:
	$(if $(PKG),,$(error "PKG not specified!"))

	@$(MAKE) $*-build CMD=$(PKG)

%-webserver: output-dir-%
	$(if $(wildcard $(OUTPUT_DIR)/$*/images/knulli/*),,$(error "$* not built!"))
	$(if $(shell which python 2>/dev/null),,$(error "python not found!"))
ifeq ($(strip $(BOARD)),)
	$(if $(wildcard $(OUTPUT_DIR)/$*/images/knulli/images/$*/.*),,$(error "Directory not found: $(OUTPUT_DIR)/$*/images/knulli/images/$*"))
	python3 -m http.server --directory $(OUTPUT_DIR)/$*/images/knulli/images/$*/
else
	$(if $(wildcard $(OUTPUT_DIR)/$*/images/knulli/images/$(BOARD)/.*),,$(error "Directory not found: $(OUTPUT_DIR)/$*/images/knulli/images/$(BOARD)"))
	python3 -m http.server --directory $(OUTPUT_DIR)/$*/images/knulli/images/$(BOARD)/
endif

%-rsync: output-dir-%
	$(eval TMP := $(call UC, $*)_IP)
	$(if $(shell which rsync 2>/dev/null),, $(error "rsync not found!"))
	$(if $($(TMP)),,$(error "$(TMP) not set!"))
	rsync -e "ssh -o 'UserKnownHostsFile /dev/null' -o StrictHostKeyChecking=no" -av $(OUTPUT_DIR)/$*/target/ root@$($(TMP)):/

%-tail: output-dir-%
	@tail -F $(OUTPUT_DIR)/$*/build/build-time.log

%-snapshot: %-supported
	$(if $(shell which btrfs 2>/dev/null),, $(error "btrfs not found!"))
	@mkdir -p $(OUTPUT_DIR)/snapshots
	-@sudo btrfs sub del $(OUTPUT_DIR)/snapshots/$*-toolchain
	@btrfs subvolume snapshot -r $(OUTPUT_DIR)/$* $(OUTPUT_DIR)/snapshots/$*-toolchain

%-rollback: %-supported
	$(if $(shell which btrfs 2>/dev/null),, $(error "btrfs not found!"))
	-@sudo btrfs sub del $(OUTPUT_DIR)/$*
	@btrfs subvolume snapshot $(OUTPUT_DIR)/snapshots/$*-toolchain $(OUTPUT_DIR)/$*

%-flash: %-supported
	$(if $(DEV),,$(error "DEV not specified!"))
	@gzip -dc $(OUTPUT_DIR)/$*/images/knulli/images/$*/knulli-*.img.gz | sudo dd of=$(DEV) bs=5M status=progress
	@sync

%-upgrade: %-supported
	$(if $(DEV),,$(error "DEV not specified!"))
	-@sudo umount /tmp/mount
	-@mkdir -p /tmp/mount
	@sudo mount $(DEV)1 /tmp/mount
	@lsblk
	@ls /tmp/mount
	@echo "continue KNULLI upgrade $(DEV)1 with $* build? [y/N]"
	@read line; if [ "$$line" != "y" ]; then echo aborting; exit 1 ; fi
	-@sudo rm /tmp/mount/boot/knulli
	@sudo tar xvf $(OUTPUT_DIR)/$*/images/knulli/images/$*/boot.tar.xz -C /tmp/mount --no-same-owner --exclude=knulli-boot.conf --exclude=config.txt
	@sudo umount /tmp/mount
	-@rmdir /tmp/mount
	@sudo fatlabel $(DEV)1 KNULLI

%-toolchain: %-supported
	$(if $(shell which btrfs 2>/dev/null),, $(error "btrfs not found!"))
	-@sudo btrfs sub del $(OUTPUT_DIR)/$*
	@btrfs subvolume create $(OUTPUT_DIR)/$*
	@$(MAKE) $*-config
	@$(MAKE) $*-build CMD=toolchain
	@$(MAKE) $*-build CMD=llvm
	@$(MAKE) $*-snapshot

%-find-build-dups: %-supported
	@$(FIND) $(OUTPUT_DIR)/$*/build -maxdepth 1 -type d -printf '%T@ %p %f\n' | sed -r 's:\-[0-9a-f\.]+$$::' | sort -k3 -k1 | uniq -f 2 -d | cut -d' ' -f2

%-remove-build-dups: %-supported
	@while [ -n "`$(FIND) $(OUTPUT_DIR)/$*/build -maxdepth 1 -type d -printf '%T@ %p %f\n' | sed -r 's:\-[0-9a-f\.]+$$::' | sort -k3 -k1 | uniq -f 2 -d | cut -d' ' -f2 | grep .`" ]; do \
		$(FIND) $(OUTPUT_DIR)/$*/build -maxdepth 1 -type d -printf '%T@ %p %f\n' | sed -r 's:\-[0-9a-f\.]+$$::' | sort -k3 -k1 | uniq -f 2 -d | cut -d' ' -f2 | xargs rm -rf ; \
	done

find-dl-dups:
	@$(FIND) $(DL_DIR)/ -maxdepth 2 -type f -name "*.zip" -o -name "*.tar.*" -print0 -printf '%T@ %p %f\n' | sed -r 's:\-[0-9a-f\.]+(\.zip|\.tar\.[2a-z]+)$$::' | sort -k3 -k1 | uniq -f 2 -d | cut -d' ' -f2

remove-dl-dups:
	@while [ -n "`$(FIND) $(DL_DIR)/ -maxdepth 2 -type f -name "*.zip" -o -name "*.tar.*" -print0 -printf '%T@ %p %f\n' | sed -r 's:\-[0-9a-f\.]+(\.zip|\.tar\.[2a-z]+)$$::' | sort -k3 -k1 | uniq -f 2 -d | cut -d' ' -f2 | grep .`" ] ; do \
		$(FIND) $(DL_DIR) -maxdepth 2 -type f -name "*.zip" -o -name "*.tar.*" -print0 -printf '%T@ %p %f\n' | sed -r 's:\-[0-9a-f\.]+(\.zip|\.tar\.[2a-z]+)$$::' | sort -k3 -k1 | uniq -f 2 -d | cut -d' ' -f2 | xargs rm -rf ; \
	done

uart:
	$(if $(shell which picocom 2>/dev/null),, $(error "picocom not found!"))
	$(if $(SERIAL_DEV),,$(error "SERIAL_DEV not specified!"))
	$(if $(SERIAL_BAUDRATE),,$(error "SERIAL_BAUDRATE not specified!"))
	$(if $(wildcard $(SERIAL_DEV)),,$(error "$(SERIAL_DEV) not available!"))
	@picocom $(SERIAL_DEV) -b $(SERIAL_BAUDRATE)
