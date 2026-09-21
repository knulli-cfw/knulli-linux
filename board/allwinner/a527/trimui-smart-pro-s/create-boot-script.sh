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

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot"     || exit 1

#cp "${BINARIES_DIR}/rootfs.squashfs"	"${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"	|| exit 1
# touch "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update" || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs"	"${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"	|| exit 1
cp "${BOARD_DIR}/knulli-boot.conf"	"${KNULLI_BINARIES_DIR}/boot/knulli-boot.conf"	|| exit 1
cp "${BOARD_DIR}/bootlogo.bmp"      	"${KNULLI_BINARIES_DIR}/boot/bootlogo.bmp"		|| exit 1

cp -r "${BOARD_DIR}/partitions"		"${KNULLI_BINARIES_DIR}/boot/"			|| exit 1

touch "${KNULLI_BINARIES_DIR}/boot/boot/autoresize"

exit 0
