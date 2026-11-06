#!/bin/bash

# HOST_DIR = host dir
# BOARD_DIR = board specific dir
# BUILD_DIR = base dir/build
# BINARIES_DIR = images dir
# TARGET_DIR = target dir
# KNULLI_BINARIES_DIR = knulli binaries sub directory

HOST_DIR=$1
BOARD_DIR=$2
BUILD_DIR=$3
BINARIES_DIR=$4
TARGET_DIR=$5
KNULLI_BINARIES_DIR=$6

PARTS="${KNULLI_BINARIES_DIR}/boot/partitions"

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot" "${PARTS}"     || exit 1

cp "${BINARIES_DIR}/rootfs.squashfs"	"${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"	|| exit 1
cp "${BOARD_DIR}/knulli-boot.conf"	"${KNULLI_BINARIES_DIR}/boot/knulli-boot.conf"	|| exit 1
SPLASH_DIR="${BOARD_DIR}/../../../../package/system/knulli-splash"
# 720x960 portrait panel in a landscape device
"${SPLASH_DIR}/make-logo.sh" "${SPLASH_DIR}/images/logo.png" \
	"${KNULLI_BINARIES_DIR}/boot/bootlogo.bmp" 720x960 90			|| exit 1
# U-Boot charge mode draws bat\battery_charge.bmp from this partition
cp -r "${BOARD_DIR}/boot/bat"		"${KNULLI_BINARIES_DIR}/boot/"			|| exit 1

# boot0 and the boot package are prebuilt; the eMMC SD-boot env reads the package's dtb at a fixed sector
cp "${BOARD_DIR}/partitions/boot0.img"		"${PARTS}/boot0.img"			|| exit 1
cp "${BOARD_DIR}/partitions/boot_package.fex"	"${PARTS}/boot_package.fex"		|| exit 1

"${HOST_DIR}/bin/mkenvimage" -p 0 -s 0x20000 -o "${PARTS}/env.img" "${BOARD_DIR}/env.txt" || exit 1

# Android boot image: knulli kernel (initramfs built in); DTB from the boot package, cmdline from env
MKBOOTIMG="${HOST_DIR}/usr/bin/mkbootimg.py"
chmod u+w "${MKBOOTIMG}" 2>/dev/null || true
sed -i 's/^from gki.generate_gki_certificate/#from gki.generate_gki_certificate/' "${MKBOOTIMG}"
"${HOST_DIR}/bin/python3" "${MKBOOTIMG}" \
	--kernel "${BINARIES_DIR}/Image" \
	--base 0x40000000 \
	--kernel_offset 0x00080000 \
	--ramdisk_offset 0x02000000 \
	--second_offset 0x00f00000 \
	--tags_offset 0x00000100 \
	--pagesize 2048 \
	--board sun55i_arm64 \
	--header_version 0 \
	--cmdline "" \
	-o "${PARTS}/boot.img"							|| exit 1

# the eMMC SD-boot env reads only 0xc500 sectors of it
if [ $(stat -c %s "${PARTS}/boot.img") -gt $((0xc500 * 512)) ]; then
	echo "boot.img is larger than the 0xc500 sectors the eMMC SD-boot env reads" >&2
	exit 1
fi

touch "${KNULLI_BINARIES_DIR}/boot/boot/autoresize"

exit 0
