################################################################################
#
# knulli-audio
#
################################################################################

KNULLI_AUDIO_VERSION = 6.8
KNULLI_AUDIO_LICENSE = GPL
KNULLI_AUDIO_SOURCE=

# this one is important because the package erase the default pipewire config files, so it must be built after it
KNULLI_AUDIO_DEPENDENCIES = pipewire wireplumber

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_RK3326),y)
ALSA_SUFFIX = "-rk3326"
else
ALSA_SUFFIX =
endif

define KNULLI_AUDIO_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/lib/python$(PYTHON3_VERSION_MAJOR) \
		$(TARGET_DIR)/usr/bin \
		$(TARGET_DIR)/usr/share/sounds \
		$(TARGET_DIR)/usr/share/knulli/alsa \
		$(TARGET_DIR)/etc/init.d \
		$(TARGET_DIR)/etc/udev/rules.d \
		$(TARGET_DIR)/etc/dbus-1/system.d \
		$(TARGET_DIR)/etc/alsa/conf.d \
		$(TARGET_DIR)/usr/share/pipewire/media-session.d

	# default alsa configurations
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/alsa/asoundrc-* \
		$(TARGET_DIR)/usr/share/knulli/alsa/

	# sample audio files
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/*.wav \
	    $(TARGET_DIR)/usr/share/sounds

	# init script
	install -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/Saudio \
		$(TARGET_DIR)/etc/init.d/S06audio

	install -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/S27audioconfig \
		$(TARGET_DIR)/etc/init.d/S27audioconfig
	# udev script to unmute audio devices
	install -m 0644 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/90-alsa-setup.rules \
		$(TARGET_DIR)/etc/udev/rules.d/90-alsa-setup.rules
	install -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/soundconfig \
		$(TARGET_DIR)/usr/bin/soundconfig
	install -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/alsa/knulli-audio$(ALSA_SUFFIX) \
		$(TARGET_DIR)/usr/bin/knulli-audio
	install -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/alsa/knulli-mixer \
		$(TARGET_DIR)/usr/bin/knulli-mixer

	# pipewire-pulse policy
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/pulseaudio-system.conf \
		$(TARGET_DIR)/etc/dbus-1/system.d

	# pipewire-alsa
	ln -sft $(TARGET_DIR)/etc/alsa/conf.d \
		/usr/share/alsa/alsa.conf.d/{50-pipewire,99-pipewire-default}.conf

	# pipewire-media-session config: disable dbus device reservation
    mkdir -p $(TARGET_DIR)/usr/share/wireplumber/wireplumber.conf.d
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/80-disable-alsa-reserve.conf \
		$(TARGET_DIR)/usr/share/wireplumber/wireplumber.conf.d/80-disable-alsa-reserve.conf

	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/pipewire.conf \
		$(TARGET_DIR)/usr/share/pipewire/pipewire.conf
endef

define KNULLI_AUDIO_X86_INTEL_DSP
	mkdir -p $(TARGET_DIR)/etc/modprobe.d
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/intel-dsp.conf \
	    $(TARGET_DIR)/etc/modprobe.d/intel-dsp.conf
endef

# Steam Deck OLED SOF files are not in the sound-open-firmware package yet
define KNULLI_AUDIO_STEAM_DECK_OLED
	mkdir -p $(TARGET_DIR)/lib/firmware/amd/sof
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/sof-vangogh-*.bin \
	    $(TARGET_DIR)/lib/firmware/amd/sof/
	mkdir -p $(TARGET_DIR)/lib/firmware/amd/sof-tplg
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/sof-vangogh-nau8821-max.tplg \
	    $(TARGET_DIR)/lib/firmware/amd/sof-tplg/sof-vangogh-nau8821-max.tplg
	# extra ucm files
	mkdir -p $(TARGET_DIR)/usr/share/alsa/ucm2
	cp -pr $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/ucm2/* \
	    $(TARGET_DIR)/usr/share/alsa/ucm2/
endef

# T618 / UMS512: the SC2730 codec hangs off the AGDSP-mediated VBC path, so the
# card comes up with every mixer control at zero and no routing -- the BootSequence
# in the UCM is what makes it audible at all.  Only the two files this card needs
# are installed, rather than the whole ucm2 tree, so nothing leaks onto other
# targets.
define KNULLI_AUDIO_T618_UCM
	mkdir -p $(TARGET_DIR)/usr/share/alsa/ucm2/Unisoc/sprdphone-sc2730 \
		$(TARGET_DIR)/usr/share/alsa/ucm2/conf.d/sprdphone-sc273
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/ucm2/Unisoc/sprdphone-sc2730/HiFi.conf \
		$(TARGET_DIR)/usr/share/alsa/ucm2/Unisoc/sprdphone-sc2730/HiFi.conf
	cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-audio/ucm2/conf.d/sprdphone-sc273/sprdphone-sc2730.conf \
		$(TARGET_DIR)/usr/share/alsa/ucm2/conf.d/sprdphone-sc273/sprdphone-sc2730.conf
endef

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_X86_ANY),y)
    KNULLI_AUDIO_POST_INSTALL_TARGET_HOOKS += KNULLI_AUDIO_X86_INTEL_DSP
    KNULLI_AUDIO_POST_INSTALL_TARGET_HOOKS += KNULLI_AUDIO_STEAM_DECK_OLED
endif

ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_T618),y)
    KNULLI_AUDIO_POST_INSTALL_TARGET_HOOKS += KNULLI_AUDIO_T618_UCM
endif

$(eval $(generic-package))
