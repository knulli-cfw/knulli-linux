################################################################################
#
# cargo-c
#
################################################################################

CARGO_C_VERSION = v0.10.19
CARGO_C_SITE = $(call github,lu-zero,cargo-c,$(CARGO_C_VERSION))
CARGO_C_LICENSE = MIT License
CARGO_C_LICENSE_FILES = LICENSE

HOST_CARGO_C_DEPENDENCIES = host-pkgconf host-rustc host-openssl

# kstring 2.0.4 in the vendored lock declares rust-version 1.96; buildroot ships
# 1.95.  cargo-c itself only needs 1.90, and the vendored tree has no older
# kstring to fall back to, so bypass the declared minimum.
# Both steps need it: pkg-cargo.mk runs "cargo build" and then a separate
# "cargo install", each with its own opts variable.
HOST_CARGO_C_CARGO_BUILD_OPTS += --ignore-rust-version
HOST_CARGO_C_CARGO_INSTALL_OPTS += --ignore-rust-version

$(eval $(host-cargo-package))
