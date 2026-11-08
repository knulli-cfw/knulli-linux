################################################################################
#
# toolchain-optional-linaro-aarch64
#
################################################################################

# Overrides batocera's package of the same name, which pins 7.5-2019.12: the
# RK3566 U-Boot 2017.09 is written against 6.3.1 and does not build with a
# later one.  Its only batocera consumer is uboot-odroid-goa, not a knulli board.
#
# Served from our own mirror because releases.linaro.org retired these binaries
# -- every path under it now 301s to linaro.org/contact/, so a tarball fetch
# silently lands a 57K HTML page.  toolchain-optional-linaro-arm still points
# at that dead site.
TOOLCHAIN_OPTIONAL_LINARO_AARCH64_VERSION = 46d00ad5a58edae59b2bc16f4694510b93d51889
TOOLCHAIN_OPTIONAL_LINARO_AARCH64_SITE = https://github.com/knulli-cfw/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu.git
TOOLCHAIN_OPTIONAL_LINARO_AARCH64_SITE_METHOD = git

# Where packages that need it pick up CROSS_COMPILE.
TOOLCHAIN_OPTIONAL_LINARO_AARCH64_PREFIX = \
	$(HOST_DIR)/lib/gcc-linaro-aarch64-linux-gnu/bin/aarch64-linux-gnu-

define HOST_TOOLCHAIN_OPTIONAL_LINARO_AARCH64_INSTALL_CMDS
	mkdir -p $(HOST_DIR)/lib/gcc-linaro-aarch64-linux-gnu/
	cp -a $(@D)/* $(HOST_DIR)/lib/gcc-linaro-aarch64-linux-gnu
endef

$(eval $(host-generic-package))
