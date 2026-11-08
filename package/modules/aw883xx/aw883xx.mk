################################################################################
#
# aw883xx - Awinic AW883xx smart amplifier ASoC driver
#
# The Rockchip BSP carries an older copy that only knows chip id 2049; the RG
# DS Plus amps are 2066. Upstream ships no build files, so Kbuild comes from
# the package directory.
#
################################################################################

AW883XX_VERSION = 4f52a107e82b88512124a14cc69601cdefd40b9e
AW883XX_SITE = $(call github,awinic-driver,aw883xx,$(AW883XX_VERSION))
AW883XX_LICENSE = GPL-2.0
AW883XX_LICENSE_FILES = LICENSE
AW883XX_DEPENDENCIES = linux

define AW883XX_COPY_KBUILD
	$(INSTALL) -m 0644 $(AW883XX_PKGDIR)/Kbuild $(@D)/Kbuild
endef
AW883XX_PRE_BUILD_HOOKS += AW883XX_COPY_KBUILD

$(eval $(kernel-module))
$(eval $(generic-package))
