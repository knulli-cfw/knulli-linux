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

DEVICE=$(basename "${BOARD_DIR}")
PARTS="${KNULLI_BINARIES_DIR}/boot/partitions"

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot" "${PARTS}"     || exit 1

cp "${BINARIES_DIR}/rootfs.squashfs"	"${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"	|| exit 1
cp "${BOARD_DIR}/knulli-boot.conf"	"${KNULLI_BINARIES_DIR}/boot/knulli-boot.conf"	|| exit 1
# U-Boot logo, drawn unrotated: portrait panel, turned for landscape use
SPLASH_DIR="${BOARD_DIR}/../../../../package/system/knulli-splash"
"${SPLASH_DIR}/make-logo.sh" "${SPLASH_DIR}/images/logo.png" \
	"${KNULLI_BINARIES_DIR}/boot/bootlogo.bmp" 720x1280 -90			|| exit 1
# U-Boot charge mode draws bat\battery_charge.bmp from this partition
cp -r "${BOARD_DIR}/boot/bat"		"${KNULLI_BINARIES_DIR}/boot/"			|| exit 1

# boot0 (DRAM init) stays the vendor's; the boot package comes from uboot-a527
cp "${BOARD_DIR}/partitions/boot0.img"	"${PARTS}/boot0.img"				|| exit 1
cp "${BINARIES_DIR}/a527-boot-packages/${DEVICE}_boot_package.fex" \
					"${PARTS}/boot_package.fex"			|| exit 1

# U-Boot environment, read from the env partition
"${HOST_DIR}/bin/mkenvimage" -p 0 -s 0x20000 -o "${PARTS}/env.img" "${BOARD_DIR}/env.txt" || exit 1

# Android boot image for "sunxi_flash read 44000000 boot; bootm 44000000":
# knulli kernel + initrd, the same load addresses as the stock one.  The kernel
# gets its DTB from U-Boot (the boot package's dtb.bin), the cmdline from env.
MKBOOTIMG="${HOST_DIR}/usr/bin/mkbootimg.py"
chmod u+w "${MKBOOTIMG}" 2>/dev/null || true
sed -i 's/^from gki.generate_gki_certificate/#from gki.generate_gki_certificate/' "${MKBOOTIMG}"
"${HOST_DIR}/bin/python3" "${MKBOOTIMG}" \
	--kernel "${BINARIES_DIR}/Image" \
	--ramdisk "${BINARIES_DIR}/initrd.lz4" \
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

touch "${KNULLI_BINARIES_DIR}/boot/boot/autoresize"

exit 0
