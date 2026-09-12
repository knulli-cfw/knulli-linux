#!/bin/bash -e

# PWD = source dir
# BASE_DIR = build dir
# BUILD_DIR = base dir/build
# HOST_DIR = base dir/host
# BINARIES_DIR = images dir
# TARGET_DIR = target dir
echo "PWD = $PWD"
echo "BASE_DIR = $BASE_DIR"
echo "BUILD_DIR = $BUILD_DIR"
echo "HOST_DIR = $HOST_DIR"
echo "BINARIES_DIR = $BINARIES_DIR"
echo "TARGET_DIR = $TARGET_DIR"

KNULLI_TARGET=$(grep -E "^BR2_PACKAGE_BATOCERA_TARGET_[A-Z_0-9]*=y$" "${BR2_CONFIG}" | grep -vE "_(GLES|GLES2|GLES3|VULKAN|OPENGL)=y$" | sed -e s+'^BR2_PACKAGE_BATOCERA_TARGET_\([A-Z_0-9]*\)=y$'+'\1'+)
echo "KNULLI_TARGET = $KNULLI_TARGET"

# For the root user:
# 1. Use Bash instead of Dash for interactive use.
# 2. Set home directory to /userdata/system instead of /root.
sed -i "s|^root:x:.*$|root:x:0:0:root:/userdata/system:/bin/bash|g" "${TARGET_DIR}/etc/passwd" || exit 1

rm -rf "${TARGET_DIR}/etc/dropbear" || exit 1
ln -sf "/userdata/system/.ssh" "${TARGET_DIR}/etc/dropbear" || exit 1

mkdir -p ${TARGET_DIR}/etc/emulationstation || exit 1
ln -sf "/usr/share/emulationstation/es_systems.cfg" "${TARGET_DIR}/etc/emulationstation/es_systems.cfg" || exit 1
ln -sf "/usr/share/emulationstation/themes"         "${TARGET_DIR}/etc/emulationstation/themes"         || exit 1
mkdir -p "${TARGET_DIR}/usr/share/knulli/datainit/cheats" || exit 1
ln -sf "/userdata/cheats" "${TARGET_DIR}/usr/share/knulli/datainit/cheats/custom" || exit 1

# Needed for the mame 2010 (0.139) since it was removed from batocera.
LIBRETRO_INFO_DIR="${TARGET_DIR}/usr/share/libretro/info"

if [ -f "${LIBRETRO_INFO_DIR}/mame2010_libretro.info" ]; then
    ln -sf "mame2010_libretro.info" "${LIBRETRO_INFO_DIR}/mame0139_libretro.info" || exit 1
fi

## === REMOVE ===
# Temp stuff that changes during consecutive builds. Meant to be cleaned/updated as-needed
rm -f "${TARGET_DIR}/etc/batteryplus/state.d/00batterysaver-chargingbypass" || exit 1
rm -f "${TARGET_DIR}/etc/init.d/S21batteryplus-state" || exit 1
rm -f "${TARGET_DIR}/etc/udev/rules.d/90-batteryplus-state.rules" || exit 1
rm -f "${TARGET_DIR}/usr/bin/batteryplus-state" || exit 1
rm -f "${TARGET_DIR}/usr/README.md" || exit 1 # why am I here?
rm -f "${TARGET_DIR}/usr/yabasanshiro" || exit 1 # why am I here?
rm -f "${TARGET_DIR}/etc/init.d/S25silky-rgb" || exit 1
rm -f "${TARGET_DIR}/etc/pm/sleep.d/99-postresume-jsled" || exit 1
rm -f "${TARGET_DIR}/usr/bin/knulli-settings-set-queue" || exit 1
rm -f "${TARGET_DIR}/usr/share/emulationstation/scripts/powermanagement-changed/refresh-battery-state.sh" || exit 1

# Remove base batocera init scripts we don't need
rm -f "${TARGET_DIR}/etc/init.d/S50kodi" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S13irqbalance" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S15virtualevents" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S25lircd" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S30rpcbind" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S35iptables" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S90hotkeygen" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S91smb" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S93wsdd" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S20urandom" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S51led-handheld" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S30splashscreencontrol" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S28splash" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S47fake-hwclock" || exit 1

rm -f "${TARGET_DIR}/etc/init.d/S50dropbear" || exit 1

# Remove base batocera udev rules we don't need
rm -f "${TARGET_DIR}/etc/udev/rules.d/99-wol.rules" || exit 1

rm -f "${TARGET_DIR}/etc/udev/rules.d/99-wheels.rules" || exit 1

rm -f "${TARGET_DIR}/etc/udev/rules.d/99-umtool.rules" || exit 1

rm -f "${TARGET_DIR}/etc/udev/rules.d/99-steam-controller.rules" || exit 1

rm -f "${TARGET_DIR}/etc/udev/rules.d/99-stadia-controller.rules" || exit 1

rm -f "${TARGET_DIR}/etc/udev/rules.d/99-pedals.rules" || exit 1

rm -f "${TARGET_DIR}/etc/udev/rules.d/99-legiongo.rules" || exit 1

rm -f "${TARGET_DIR}/etc/udev/rules.d/99-ledspicer.rules" || exit 1

rm -f "${TARGET_DIR}/etc/udev/rules.d/99-anbernic-gpio-pad.rules" || exit 1

# Remove services we don't need
rm -f "${TARGET_DIR}/usr/share/knulli/services/ledspicer" || exit 1

rm -f "${TARGET_DIR}/usr/share/knulli/services/pigpio" || exit 1

# Remove misc stuff we don't need
rm -f "${TARGET_DIR}/usr/share/knulli/configgen/scripts/mali_g52_gpu_launch_hooks.sh" || exit 1

## === REMOVE END ===

# use /userdata/system/iptables.conf for S35iptables
rm -f "${TARGET_DIR}/etc/iptables.conf" || exit 1
ln -sf "/userdata/system/iptables.conf" "${TARGET_DIR}/etc/iptables.conf" || exit 1

# acpid requires /var/run, so, requires S03populate
if test -e "${TARGET_DIR}/etc/init.d/S02acpid"
then
    mv "${TARGET_DIR}/etc/init.d/S02acpid" "${TARGET_DIR}/etc/init.d/S05acpid" || exit 1
fi

# we don't want default xorg files
rm -f "${TARGET_DIR}/etc/X11/xorg.conf"  || exit 1
rm -f "${TARGET_DIR}/etc/init.d/S40xorg" || exit 1

# remove the S10triggerhappy
rm -f "${TARGET_DIR}/etc/init.d/S10triggerhappy" || exit 1

# remove the S40bluetoothd
rm -f "${TARGET_DIR}/etc/init.d/S40bluetoothd" || exit 1

# we want an empty boot directory (grub installation copy some files in the target boot directory)
rm -rf "${TARGET_DIR}/boot/grub" || exit 1

# reorder the boot scripts for the network boot
if test -e "${TARGET_DIR}/etc/init.d/S10udev"
then
    mv "${TARGET_DIR}/etc/init.d/S10udev"    "${TARGET_DIR}/etc/init.d/S05udev"    || exit 1 # move to make number spaces
fi
# buildroot 2026.05 renamed S30dbus to S30dbus-daemon; accept either name
for DBUS_INIT in S30dbus S30dbus-daemon
do
    if test -e "${TARGET_DIR}/etc/init.d/${DBUS_INIT}"
    then
        mv "${TARGET_DIR}/etc/init.d/${DBUS_INIT}" "${TARGET_DIR}/etc/init.d/S01dbus" || exit 1 # move really before for network (connman prerequisite) and pipewire
    fi
done
if test -e "${TARGET_DIR}/etc/init.d/S40network"
then
    mv "${TARGET_DIR}/etc/init.d/S40network" "${TARGET_DIR}/etc/init.d/S07network" || exit 1 # move to make ifaces up sooner, mainly mountable/unmountable before/after share
fi
if test -e "${TARGET_DIR}/etc/init.d/S45connman"
then
    if test -e "${TARGET_DIR}/etc/init.d/S08connman"
    then
	rm -f "${TARGET_DIR}/etc/init.d/S45connman" || exit 1
    else
	mv "${TARGET_DIR}/etc/init.d/S45connman" "${TARGET_DIR}/etc/init.d/S08connman" || exit 1 # move to make before share
    fi
fi
if test -e "${TARGET_DIR}/etc/init.d/S21rngd"
then
    mv "${TARGET_DIR}/etc/init.d/S21rngd"    "${TARGET_DIR}/etc/init.d/S33rngd"    || exit 1 # move because it takes several seconds (on odroidgoa for example)
    sed -i "s/start-stop-daemon -S -q /start-stop-daemon -S -q -N 10 /g" "${TARGET_DIR}/etc/init.d/S33rngd"  || exit 1 # set rngd niceness to 10 (to decrease slowdown of other processes)
fi

echo "###########################"
echo "###########################"
echo "###########################"
echo "###########################"

# The 32-bit (armhf) runtime is installed by the knulli-armhf-drop package from
# armhf-cache/, not from here.  What used to be in this spot reached into
# output/<board>_armhf_libs/target, only ran for RK3326, and passed TARGET_DIR
# where install-32bit-libs.sh expected a board name -- so it always took its
# "not found" path and skipped.  See package/system/knulli-armhf-drop.

# Check that the rootfs provides what the emulator drop's binaries link against.
# Here rather than in the package: knulli-emulators-drop depends only on the
# toolchain, so it can be installed before those libraries are, and the 32-bit
# layer above lands later still.  This is the first point where the rootfs is
# what the image will actually ship.
#
# Gated on the config symbol, not on the file existing: staging/ is not cleaned
# between builds, so a build made with the gate off still finds the list a
# previous gate-on build left behind and would check a drop it never installed.
EMULATORS_SONAMES="${STAGING_DIR}/usr/share/knulli/emulators-drop-sonames.list"
if grep -q "^BR2_PACKAGE_KNULLI_EMULATORS_DROP=y$" "${BR2_CONFIG}" && \
   [ -f "${EMULATORS_SONAMES}" ]; then
    CHECK_SONAMES="${BR2_EXTERNAL_KNULLI_PATH}/package/emulators/knulli-emulators-drop/check-sonames.sh"
    bash "${CHECK_SONAMES}" "${EMULATORS_SONAMES}" "${TARGET_DIR}" || exit 1
fi

# remove kodi default joystick configuration files
# while as a minimum, the file joystick.Sony.PLAYSTATION(R)3.Controller.xml makes references to PS4 controllers with axes which doesn't exist (making kodi crashing)
# i prefer to put it here than in packages/kodi while there are already a lot a lot of things
rm -rf "${TARGET_DIR}/usr/share/kodi/system/keymaps/joystick."*.xml || exit 1

# tmpfs or sysfs is mounted over theses directories
# clear these directories is required for the upgrade (otherwise, tar xf fails)
rm -rf "${TARGET_DIR}/"{var,run,sys,tmp} || exit 1
mkdir "${TARGET_DIR}/"{var,run,sys,tmp}  || exit 1

# make /etc/shadow a file generated from /boot/knulli-boot.conf for security
rm -f "${TARGET_DIR}/etc/shadow" || exit 1
touch "${TARGET_DIR}/run/knulli.shadow"
(cd "${TARGET_DIR}/etc" && ln -sf "../run/knulli.shadow" "shadow") || exit 1
# ln -sf "/run/knulli.shadow" "${TARGET_DIR}/etc/shadow" || exit 1

# fix pixbuf : Unable to load image-loading module: /lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-png.so
# this fix is to be removed once fixed. i've not found the exact source in buildroot. it prevents to display icons in filemanager and some others
if test "${KNULLI_TARGET}" = "X86" -o "${KNULLI_TARGET}" = X86_64
then
    ln -sf "/usr/lib/gdk-pixbuf-2.0" "${TARGET_DIR}/lib/gdk-pixbuf-2.0" || exit 1
fi

# timezone
# file generated from the output directory and compared to https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
# because i don't know how to list correctly them
(cd "${TARGET_DIR}/usr/share/zoneinfo" && find -L . -type f | grep -vE '/right/|/posix/|\.tab|Factory' | sed -e s+'^\./'++ | sort) > "${TARGET_DIR}/usr/share/knulli/tz"

# alsa lib
# on x86_64, pcsx2 has no sound because getgrnam_r returns successfully but the result parameter is not filled for an unknown reason (in alsa-lib)
AUDIOGROUP=$(grep -E "^audio:" "${TARGET_DIR}/etc/group" | cut -d : -f 3)
sed -i -e s+'defaults.pcm.ipc_gid .*$'+'defaults.pcm.ipc_gid '"${AUDIOGROUP}"+ "${TARGET_DIR}/usr/share/alsa/alsa.conf" || exit 1

# bios file
mkdir -p "${TARGET_DIR}/usr/share/knulli/datainit/bios" || exit 1
python "${BR2_EXTERNAL_KNULLI_PATH}/package/system/knulli-scripts/scripts/knulli-systems" --createReadme > "${TARGET_DIR}/usr/share/knulli/datainit/bios/readme.txt" || exit 1

# enable serial console
SYSTEM_GETTY_PORT=$(grep "BR2_TARGET_GENERIC_GETTY_PORT" "${BR2_CONFIG}" | sed 's/.*\"\(.*\)\"/\1/')
if ! [[ -z "${SYSTEM_GETTY_PORT}" ]]; then
    SYSTEM_GETTY_BAUDRATE=$(grep -E "^BR2_TARGET_GENERIC_GETTY_BAUDRATE_[0-9]*=y$" "${BR2_CONFIG}" | sed -e s+'^BR2_TARGET_GENERIC_GETTY_BAUDRATE_\([0-9]*\)=y$'+'\1'+)
    sed -i -e '/# GENERIC_SERIAL$/s~^.*#~S0::respawn:/sbin/getty -n -L -l /usr/bin/knulli-autologin '${SYSTEM_GETTY_PORT}' '${SYSTEM_GETTY_BAUDRATE}' vt100 #~' \
        ${TARGET_DIR}/etc/inittab
fi

# Knulli
# Add OS name
OS_RELEASE_PATH="${TARGET_DIR}/etc/os-release"
if ! grep -q "^OS_NAME=" "$OS_RELEASE_PATH"; then
    # If OS_NAME is not found, append it
    echo "OS_NAME=\"knulli\"" >> "$OS_RELEASE_PATH"
fi
SUFFIXVERSION=$(cat "${TARGET_DIR}/usr/share/knulli/knulli.version" | sed -e s+'^\([0-9\.]*\).*$'+'\1'+) # xx.yy version
SUFFIXDATE=$(date +%Y%m%d)

# Update or add OS_VERSION
if grep -q "^OS_VERSION=" "$OS_RELEASE_PATH"; then
    # Update the existing OS_VERSION
    sed -i "s/^OS_VERSION=.*/OS_VERSION=$SUFFIXVERSION/" "$OS_RELEASE_PATH"
else
    # Add OS_VERSION if it does not exist
    echo "OS_VERSION=$SUFFIXVERSION" >> "$OS_RELEASE_PATH"
fi

# Update or add OS_DATE
if grep -q "^OS_DATE=" "$OS_RELEASE_PATH"; then
    # Update the existing OS_DATE
    sed -i "s/^OS_DATE=.*/OS_DATE=$SUFFIXDATE/" "$OS_RELEASE_PATH"
else
    # Add OS_DATE if it does not exist
    echo "OS_DATE=$SUFFIXDATE" >> "$OS_RELEASE_PATH"
fi

# Move Batocera share resources to Knulli
echo "========================================"
echo "Moving Batocera resources to Knulli..."
echo "========================================"

if [ -d "${TARGET_DIR}/usr/share/batocera" ]; then
    # Create knulli directory if it doesn't exist
    mkdir -p "${TARGET_DIR}/usr/share/knulli" || exit 1
    
    # Move all content from batocera to knulli
    if [ "$(ls -A ${TARGET_DIR}/usr/share/batocera)" ]; then
        cp -af "${TARGET_DIR}/usr/share/batocera/"* "${TARGET_DIR}/usr/share/knulli/" || exit 1
        echo "Moved batocera resources to knulli"
    else
        echo "Batocera directory is empty, nothing to move"
    fi
    
    # Remove the batocera directory
    rm -rf "${TARGET_DIR}/usr/share/batocera" || exit 1
    echo "Removed batocera directory"
else
    echo "No batocera directory found, skipping..."
fi

# Guard: the real Vulkan loader must survive
#
# A vendor GPU blob that ships its own libvulkan.so.1 can overwrite
# vulkan-loader's file, because the loader installs libvulkan.so.1 as a symlink
# to libvulkan.so.1.4.x and a plain copy writes through it.  The replacement
# still resolves every core entry point, so nothing fails to build or run --
# but ICD manifests and Vulkan layers are silently ignored from then on.
# The real loader is ~600K; a vendor stub is a few tens of K.
LOADER=$(ls "${TARGET_DIR}"/usr/lib/libvulkan.so.1.* 2>/dev/null | head -1)
if [ -n "$LOADER" ]; then
    LOADER_SIZE=$(stat -c %s "$LOADER")
    if [ "$LOADER_SIZE" -lt 262144 ]; then
        echo "post-build: $LOADER is ${LOADER_SIZE} bytes -- too small to be the"
        echo "            Khronos loader.  A GPU blob has overwritten it, so ICD"
        echo "            manifests and Vulkan layers will be ignored at runtime."
        echo "            On an incremental tree the loader is not reinstalled on"
        echo "            its own -- force it:  make <board>-shell BATCH_MODE=1 \\"
        echo "              CMD=\"make O=/<board> BR2_EXTERNAL=/build -C /build/buildroot \\"
        echo "                   vulkan-loader-reinstall\""
        exit 1
    fi
    echo "Vulkan loader intact (${LOADER_SIZE} bytes)"
fi
