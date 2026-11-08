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

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot" || exit 1

"${HOST_DIR}/bin/mkimage" -A arm64 -O linux -T kernel -C none -a 0x1080000 -e 0x1080000 -n 6.1 -d "${BINARIES_DIR}/Image" "${KNULLI_BINARIES_DIR}/boot/boot/linux" || exit 1
cp "${BINARIES_DIR}/uInitrd"         "${KNULLI_BINARIES_DIR}/boot/boot/uInitrd"       || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs" "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update" || exit 1

# Kernel DTBs: every device's, boot.ini picks one with ${dtb_kernel}.
cp "${BINARIES_DIR}"/rk3326-*.dtb "${KNULLI_BINARIES_DIR}/boot/boot/" || exit 1

# U-Boot's own device trees (${dtb_uboot}) and the artwork it shows
# (${logo_filename} and the status/battery images) -- one per handheld and one
# artwork set per panel resolution, so both go in subdirectories rather than
# burying the root.  hwrev picks which from the SARADC value.
mkdir -p "${KNULLI_BINARIES_DIR}/boot/dtbs" || exit 1
cp "${BOARD_DIR}/uboot-dtbs/"*.dtb "${KNULLI_BINARIES_DIR}/boot/dtbs/"  || exit 1
mkdir -p "${KNULLI_BINARIES_DIR}/boot/logos" || exit 1
cp "${BOARD_DIR}/bootlogos/"*.bmp  "${KNULLI_BINARIES_DIR}/boot/logos/"  || exit 1

cp "${BOARD_DIR}/boot/boot.ini" "${KNULLI_BINARIES_DIR}/boot/" || exit 1

# Manual board override; inert until renamed to hwrev.ini (see the file).
cp "${BOARD_DIR}/boot/hwrev.ini.example" "${KNULLI_BINARIES_DIR}/boot/" || exit 1

exit 0
