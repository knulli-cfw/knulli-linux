################################################################################
#
# KNULLI-ES-SYSTEM
#
################################################################################

KNULLI_ES_SYSTEM_DEPENDENCIES = host-python3 host-python-pyyaml knulli-configgen host-gettext
KNULLI_ES_SYSTEM_SOURCE=
KNULLI_ES_SYSTEM_VERSION=1.03

# es_systems.yml gates cores on BR2_PACKAGE_LIBRETRO_* symbols that no longer
# exist when the cores come from a prebuilt drop.  libretro-super stages a
# fragment listing the ones it actually installed; without it every libretro
# system, and every roms/<system> folder, disappears.
ifeq ($(BR2_PACKAGE_LIBRETRO_SUPER),y)
KNULLI_ES_SYSTEM_DEPENDENCIES += libretro-super
KNULLI_ES_SYSTEM_EXTRA_CONFIG = \
	--extra-config $(STAGING_DIR)/usr/share/knulli/libretro-cores.config \
	--libretro-cores $(STAGING_DIR)/usr/share/knulli/libretro-cores.list
endif

# The same problem for the standalone emulators and ports: es_systems.yml gates
# them on BR2_PACKAGE_<EMULATOR>, and the gate that stops building them removes
# those symbols too.
ifeq ($(BR2_PACKAGE_KNULLI_EMULATORS_DROP),y)
KNULLI_ES_SYSTEM_DEPENDENCIES += knulli-emulators-drop
KNULLI_ES_SYSTEM_EXTRA_CONFIG += \
	--extra-config $(STAGING_DIR)/usr/share/knulli/emulators-drop.config
endif

define KNULLI_ES_SYSTEM_BUILD_CMDS
	$(HOST_DIR)/bin/python \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/knulli-es-system.py \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/es_systems.yml        \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/es_features.yml       \
		$(@D)/es_external_translations.h \
		$(@D)/es_keys_translations.h \
                $(BR2_EXTERNAL_KNULLI_PATH)/package/knulli \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/locales/blacklisted-words.txt \
		$(CONFIG_DIR)/.config \
		$(@D)/es_systems.cfg \
		$(@D)/es_features.cfg \
		$(STAGING_DIR)/usr/share/knulli/configgen/configgen-defaults.yml \
		$(STAGING_DIR)/usr/share/knulli/configgen/configgen-defaults-arch.yml \
		$(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/roms \
		$(@D)/roms $(KNULLI_SYSTEM_ARCH) \
		$(KNULLI_ES_SYSTEM_EXTRA_CONFIG)
		# translations
		mkdir -p $(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/locales
		(echo "$(@D)/es_external_translations.h"; echo "$(@D)/es_keys_translations.h") | xgettext --language=C --add-comments=TRANSLATION -f - -o $(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/locales/knulli-es-system.pot --no-location --keyword=_
		# remove the pot creation date always changing
		sed -i '/^"POT-Creation-Date: /d' $(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/locales/knulli-es-system.pot

		for PO in $(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/locales/*/knulli-es-system.po; do (LANG=C msgmerge -s -U --no-fuzzy-matching $${PO} $(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/locales/knulli-es-system.pot && printf "%s " $$(basename $$(dirname $${PO})) && LANG=C msgfmt -o /dev/null $${PO} --statistics) || exit 1; done

		# install staging
		mkdir -p $(STAGING_DIR)/usr/share/knulli-es-system/locales
		cp $(@D)/es_external_translations.h      $(STAGING_DIR)/usr/share/knulli-es-system/
		cp $(@D)/es_keys_translations.h          $(STAGING_DIR)/usr/share/knulli-es-system/
		cp -pr $(BR2_EXTERNAL_KNULLI_PATH)/package/emulationstation/knulli-es-system/locales $(STAGING_DIR)/usr/share/knulli-es-system
endef

define KNULLI_ES_SYSTEM_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/knulli/datainit
	$(INSTALL) -m 0644 -D $(@D)/es_systems.cfg $(TARGET_DIR)/usr/share/emulationstation/es_systems.cfg
	$(INSTALL) -m 0644 -D $(@D)/es_features.cfg $(TARGET_DIR)/usr/share/emulationstation/es_features.cfg
	mkdir -p $(@D)/roms # in case there is no rom
	cp -pr $(@D)/roms $(TARGET_DIR)/usr/share/knulli/datainit/
endef

$(eval $(generic-package))
