################################################################################
#
# mali-kbase
#
################################################################################

# The ums512 branch, not bifrost_port: the latter is plain rocknix upstream and
# is missing the UMS512 clock-window and runtime-PM fixes, so the GPU probes and
# then stalls.
MALI_KBASE_VERSION = 3248d9d67ca16376e094bb73a0e1e54b153fc8a7
MALI_KBASE_SITE = https://github.com/beebono/mali_kbase.git
MALI_KBASE_SITE_METHOD = git
MALI_KBASE_LICENSE = GPL-2.0

MALI_KBASE_MODULE_SUBDIRS = product/kernel/drivers/gpu/arm/midgard

MALI_KBASE_MODULE_MAKE_OPTS = \
	CONFIG_MALI_MIDGARD=m \
	CONFIG_MALI_PLATFORM_NAME=devicetree \
	CONFIG_MALI_REAL_HW=y \
	CONFIG_MALI_DEVFREQ=y \
	CONFIG_MALI_GATOR_SUPPORT=y

$(eval $(kernel-module))
$(eval $(generic-package))
