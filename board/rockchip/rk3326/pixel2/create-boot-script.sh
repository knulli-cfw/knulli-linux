#!/bin/bash

# HOST_DIR = host dir
# BOARD_DIR = board specific dir
# BUILD_DIR = base dir/build
# BINARIES_DIR = images dir
# TARGET_DIR = target dir
# KNULLI_BINARIES_DIR = knulli binaries sub directory
# KNULLI_TARGET_DIR = knulli target sub directory

HOST_DIR=$1
BOARD_DIR=$2
BUILD_DIR=$3
BINARIES_DIR=$4
TARGET_DIR=$5
KNULLI_BINARIES_DIR=$6

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot" || exit 1

#"${HOST_DIR}/bin/mkimage" -A arm64 -O linux -T kernel -C none -a 0x1080000 -e 0x1080000 -n 5.x -d "${BINARIES_DIR}/Image" "${KNULLI_BINARIES_DIR}/boot/boot/linux" || exit 1
cp "${BOARD_DIR}/Image"		     "${KNULLI_BINARIES_DIR}/boot/Image" || exit 1
#cp "${BINARIES_DIR}/uInitrd"         "${KNULLI_BINARIES_DIR}/boot/boot/uInitrd"         || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs" "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update" || exit 1

#cp "${BOARD_DIR}/boot/boot.ini"                     "${KNULLI_BINARIES_DIR}/boot/"                                    || exit 1
cp "${BOARD_DIR}/boot/rk3326s-gkd-pixel2.dtb"       "${KNULLI_BINARIES_DIR}/boot/rk3326s-gkd-pixel2.dtb"     || exit 1

cp -r "${BOARD_DIR}/partitions"         "${KNULLI_BINARIES_DIR}/boot/"                         || exit 1

exit 0
