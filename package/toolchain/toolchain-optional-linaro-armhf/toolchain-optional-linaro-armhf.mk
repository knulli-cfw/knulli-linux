################################################################################
#
# toolchain-optional-linaro-armhf
#
################################################################################

# The rk3128 U-Boot 2017.09 hangs at display init when built with gcc 14;
# Rockchip's make.sh pins this compiler.  releases.linaro.org retired the
# tarball, so it comes from Rockchip's toybrick copy.
TOOLCHAIN_OPTIONAL_LINARO_ARMHF_VERSION = 353c55a8a41b0adf3f0dd64fc33c545777cf1075
TOOLCHAIN_OPTIONAL_LINARO_ARMHF_SITE = https://github.com/rockchip-toybrick/gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf.git
TOOLCHAIN_OPTIONAL_LINARO_ARMHF_SITE_METHOD = git

# Where packages that need it pick up CROSS_COMPILE.
TOOLCHAIN_OPTIONAL_LINARO_ARMHF_PREFIX = \
	$(HOST_DIR)/lib/gcc-linaro-arm-linux-gnueabihf/bin/arm-linux-gnueabihf-

define HOST_TOOLCHAIN_OPTIONAL_LINARO_ARMHF_INSTALL_CMDS
	mkdir -p $(HOST_DIR)/lib/gcc-linaro-arm-linux-gnueabihf/
	cp -a $(@D)/* $(HOST_DIR)/lib/gcc-linaro-arm-linux-gnueabihf
endef

$(eval $(host-generic-package))
