################################################################################
#
# knulli splash
#
################################################################################
KNULLI_SPLASH_VERSION = 5.5
KNULLI_SPLASH_SOURCE=

KNULLI_SPLASH_TGVERSION=$(KNULLI_SYSTEM_VERSION) $(KNULLI_SYSTEM_DATE)

# video or image
ifeq ($(BR2_PACKAGE_KNULLI_SPLASH_MPV),y)
    KNULLI_SPLASH_SCRIPT=Ssplash-mpv
    KNULLI_SPLASH_MEDIA=video
else
    KNULLI_SPLASH_SCRIPT=Ssplash-image
    KNULLI_SPLASH_MEDIA=image
endif

# MPV options
ifeq ($(BR2_PACKAGE_KNULLI_SPLASH_MPV),y)
    ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_X86_64_ANY),y)
        # drm doesn't work on my nvidia card. sdl run smoothly.
        KNULLI_SPLASH_PLAYER_OPTIONS=--vo=drm,sdl --hwdec=yes
    else ifeq ($(BR2_PACKAGE_ROCKCHIP_RGA),y)
        KNULLI_SPLASH_PLAYER_OPTIONS=--hwdec=auto
    else ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_AMLOGIC_ANY)$(BR2_PACKAGE_KNULLI_RPI_ANY)$(BR2_PACKAGE_BATOCERA_TARGET_RK3399)$(BR2_PACKAGE_BATOCERA_TARGET_H6)$(BR2_PACKAGE_BATOCERA_TARGET_H616),y)
        # hwdec=yes doesnt work for n2
        KNULLI_SPLASH_PLAYER_OPTIONS=
    else
        KNULLI_SPLASH_PLAYER_OPTIONS=--hwdec=yes
    endif
endif

KNULLI_SPLASH_POST_INSTALL_TARGET_HOOKS += KNULLI_SPLASH_INSTALL_SCRIPT

ifeq ($(KNULLI_SPLASH_MEDIA),image)
    # the version-stamped images are drawn on the generated logos
    KNULLI_SPLASH_POST_INSTALL_TARGET_HOOKS += KNULLI_SPLASH_INSTALL_BOOT_LOGO
    KNULLI_SPLASH_POST_INSTALL_TARGET_HOOKS += KNULLI_SPLASH_INSTALL_IMAGE
endif

ifeq ($(KNULLI_SPLASH_MEDIA),video)
    KNULLI_SPLASH_POST_INSTALL_TARGET_HOOKS += KNULLI_SPLASH_INSTALL_VIDEO
    KNULLI_SPLASH_POST_INSTALL_TARGET_HOOKS += KNULLI_SPLASH_INSTALL_BOOT_LOGO

    # Capcom video only for H3 build (for CHA)
    ifeq ($(BR2_PACKAGE_BATOCERA_TARGET_H3),y)
        KNULLI_SPLASH_POST_INSTALL_TARGET_HOOKS += KNULLI_SPLASH_INSTALL_VIDEO_CAPCOM
    endif

    # alternative video
    ifeq ($(BR2_PACKAGE_KNULLI_RPI_ANY)$(BR2_PACKAGE_BATOCERA_TARGET_RK3326)$(BR2_PACKAGE_BATOCERA_TARGET_RK3128)$(BR2_PACKAGE_BATOCERA_TARGET_H3),y)
        BATO_SPLASH=$(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/videos/splash720p.mp4
    else
        BATO_SPLASH=$(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/videos/splash.mp4
    endif
endif

define KNULLI_SPLASH_INSTALL_SCRIPT
    mkdir -p $(TARGET_DIR)/etc/init.d
    install -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/scripts/Ssystem-splash            $(TARGET_DIR)/etc/init.d/S03system-splash
    install -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/scripts/Ssplashscreencontrol      $(TARGET_DIR)/etc/init.d/S30splashscreencontrol
    install -m 0755 $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/scripts/$(KNULLI_SPLASH_SCRIPT) $(TARGET_DIR)/etc/init.d/S28splash
    sed -i -e s+"%PLAYER_OPTIONS%"+"$(KNULLI_SPLASH_PLAYER_OPTIONS)"+g $(TARGET_DIR)/etc/init.d/S28splash
endef

# Every logo is generated from the one 1920x1080 images/logo.png by
# make-logo.sh: boot-logo-<entry>.png, entry = <W>x<H>[-left][,rotate[,fit%]]
# (see make-logo.sh).  The rotate angles are what the devices were
# tested with, not a convention.
KNULLI_SPLASH_LOGO = $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/images/logo.png
KNULLI_SPLASH_MAKE_LOGO = $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/make-logo.sh
KNULLI_SPLASH_LOGOS = \
	320x240 640x480 1024x768 1280x720 720x720 \
	480x640,-90 480x640-left,90 320x480,-90 480x854,-90 720x1280,-90 \
	1080x1920,90 1080x1920-left,-90 \
	480x800,0,60

define KNULLI_SPLASH_INSTALL_BOOT_LOGO
    mkdir -p $(TARGET_DIR)/usr/share/knulli/splash
    cp "$(KNULLI_SPLASH_LOGO)" "${TARGET_DIR}/usr/share/knulli/splash/boot-logo.png"
    for e in $(KNULLI_SPLASH_LOGOS); do \
        set -- $$(echo "$$e" | tr , ' '); \
        $(KNULLI_SPLASH_MAKE_LOGO) "$(KNULLI_SPLASH_LOGO)" "$(TARGET_DIR)/usr/share/knulli/splash/boot-logo-$$1.png" \
            "$${1%-left}" "$$2" "$$3" || exit 1; \
    done
endef

define KNULLI_SPLASH_INSTALL_VIDEO
    mkdir -p $(TARGET_DIR)/usr/share/knulli/splash
    cp $(BATO_SPLASH) $(TARGET_DIR)/usr/share/knulli/splash/splash.mp4
    echo -e "1\n00:00:00,000 --> 00:00:02,000\n$(KNULLI_SPLASH_TGVERSION)" > "${TARGET_DIR}/usr/share/knulli/splash/splash.srt"
endef

# Hack for CHA, custom Capcom splash video
define KNULLI_SPLASH_INSTALL_VIDEO_CAPCOM
    mkdir -p $(TARGET_DIR)/usr/share/knulli/splash
    cp $(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/videos/Capcom.mp4 $(TARGET_DIR)/usr/share/knulli/splash/Capcom.mp4
    echo -e "1\n00:00:00,000 --> 00:00:02,000\n$(KNULLI_SPLASH_TGVERSION)" > "${TARGET_DIR}/usr/share/knulli/splash/splash.srt"
endef

define KNULLI_SPLASH_INSTALL_IMAGE
    mkdir -p $(TARGET_DIR)/usr/share/knulli/splash
    convert "$(KNULLI_SPLASH_LOGO)" -fill white -pointsize 30 -annotate +50+1020 "$(KNULLI_SPLASH_TGVERSION)" "${TARGET_DIR}/usr/share/knulli/splash/logo-version.png"
    convert "$(TARGET_DIR)/usr/share/knulli/splash/boot-logo-320x480.png" -fill white -pointsize 15 -annotate 270x270+300+440 "$(KNULLI_SPLASH_TGVERSION)" "${TARGET_DIR}/usr/share/knulli/splash/logo-version-320x480.png"
    convert "$(TARGET_DIR)/usr/share/knulli/splash/boot-logo-480x854.png" -fill white -pointsize 20 -annotate 270x270+440+814 "$(KNULLI_SPLASH_TGVERSION)" "${TARGET_DIR}/usr/share/knulli/splash/logo-version-480x854.png"
    convert "$(TARGET_DIR)/usr/share/knulli/splash/boot-logo-640x480.png" -fill white -pointsize 20 -annotate +40+440 "$(KNULLI_SPLASH_TGVERSION)" "${TARGET_DIR}/usr/share/knulli/splash/logo-version-640x480.png"
    convert "$(TARGET_DIR)/usr/share/knulli/splash/boot-logo-320x240.png" -fill white -pointsize 15 -annotate +20+220 "$(KNULLI_SPLASH_TGVERSION)" "${TARGET_DIR}/usr/share/knulli/splash/logo-version-320x240.png"
#     convert "$(BR2_EXTERNAL_KNULLI_PATH)/package/system/knulli-splash/images/logo-480-dmg.png" -fill white -pointsize 20 -annotate +40+440 "$(KNULLI_SPLASH_TGVERSION)" "${TARGET_DIR}/usr/share/knulli/splash/logo-version-640x480-dmg.png"
endef

$(eval $(generic-package))
