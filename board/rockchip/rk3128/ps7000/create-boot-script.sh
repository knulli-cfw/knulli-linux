#!/bin/bash

# HOST_DIR = host dir
# BOARD_DIR = board specific dir
# BUILD_DIR = base dir/build
# BINARIES_DIR = images dir
# TARGET_DIR = target dir
# KNULLI_BINARIES_DIR =  binaries sub directory

HOST_DIR=$1
BOARD_DIR=$2
BUILD_DIR=$3
BINARIES_DIR=$4
TARGET_DIR=$5
KNULLI_BINARIES_DIR=$6

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot"     || exit 1
mkdir -p "${KNULLI_BINARIES_DIR}/boot/extlinux" || exit 1

cp "${BINARIES_DIR}/zImage"             "${KNULLI_BINARIES_DIR}/boot/boot/linux"           || exit 1
cp "${BINARIES_DIR}/uInitrd"           "${KNULLI_BINARIES_DIR}/boot/boot/uInitrd"         || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs"    "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update" || exit 1

cp "${BINARIES_DIR}/rk3128-ps7000.dtb"     "${KNULLI_BINARIES_DIR}/boot/boot/"     || exit 1
cp "${BOARD_DIR}/boot/extlinux.conf"    "${KNULLI_BINARIES_DIR}/boot/extlinux/" || exit 1

exit 0
