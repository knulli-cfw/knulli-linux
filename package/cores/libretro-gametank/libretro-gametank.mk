################################################################################
#
# libretro-gametank
#
################################################################################

LIBRETRO_GAMETANK_VERSION = 5fc954d56e9b28fbcacc6a8c56442881ffe9c671
LIBRETRO_GAMETANK_SITE = https://github.com/dwbrite/gametank_libretro.git
LIBRETRO_GAMETANK_SITE_METHOD = git
LIBRETRO_GAMETANK_LICENSE = MIT
LIBRETRO_GAMETANK_LICENSE_FILES = LICENSE

LIBRETRO_GAMETANK_DEPENDENCIES = host-rustc host-clang

LIBRETRO_GAMETANK_CARGO_ENV = CARGO_HOME=$(HOST_DIR)/share/cargo

# Determine the Rust target triple based on architecture
ifeq ($(BR2_aarch64),y)
    LIBRETRO_GAMETANK_CARGO_TARGET = aarch64-unknown-linux-gnu
else ifeq ($(BR2_arm),y)
    LIBRETRO_GAMETANK_CARGO_TARGET = armv7-unknown-linux-gnueabihf
else ifeq ($(BR2_x86_64),y)
    LIBRETRO_GAMETANK_CARGO_TARGET = x86_64-unknown-linux-gnu
else
    LIBRETRO_GAMETANK_CARGO_TARGET = $(RUSTC_TARGET_NAME)
endif

LIBRETRO_GAMETANK_CARGO_OPTS = \
    $(if $(BR2_ENABLE_DEBUG),,--release) \
    --target=$(LIBRETRO_GAMETANK_CARGO_TARGET) \
    --manifest-path=$(@D)/Cargo.toml

# Set up Rust environment for cross-compilation
LIBRETRO_GAMETANK_CARGO_ENV += RUSTFLAGS="-C linker=$(TARGET_CC) -C link-arg=-Wl,-rpath-link=$(STAGING_DIR)/lib"
LIBRETRO_GAMETANK_CARGO_ENV += CC=$(TARGET_CC)
LIBRETRO_GAMETANK_CARGO_ENV += LD=$(TARGET_LD)
LIBRETRO_GAMETANK_CARGO_ENV += AR=$(TARGET_AR)

define LIBRETRO_GAMETANK_BUILD_CMDS
    $(TARGET_MAKE_ENV) $(LIBRETRO_GAMETANK_CARGO_ENV) \
        $(HOST_DIR)/bin/cargo build $(LIBRETRO_GAMETANK_CARGO_OPTS)
endef

define LIBRETRO_GAMETANK_INSTALL_TARGET_CMDS
    $(INSTALL) -D $(@D)/target/$(LIBRETRO_GAMETANK_CARGO_TARGET)/$(if $(BR2_ENABLE_DEBUG),debug,release)/libgametank_libretro.so \
        $(TARGET_DIR)/usr/lib/libretro/gametank_libretro.so
endef

$(eval $(generic-package))