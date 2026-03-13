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

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot"       || exit 1
mkdir -p "${KNULLI_BINARIES_DIR}/boot/extlinux"   || exit 1

cp "${BOARD_DIR}/idbloader.img"		                	"${BINARIES_DIR}/idbloader.img"              || exit 1
cp "${BOARD_DIR}/resource.img"		                	"${BINARIES_DIR}/resource.img"              || exit 1
cp "${BOARD_DIR}/u-boot.img"		                	"${BINARIES_DIR}/u-boot.img"              || exit 1
cp "${BINARIES_DIR}/initrd.lz4"                                 "${KNULLI_BINARIES_DIR}/boot/boot/initrd.lz4"         || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs"                            "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"      || exit 1
# FIXME, temporarily copy the compiled kernel from the board folder
cp "${BOARD_DIR}/Image"                            		"${KNULLI_BINARIES_DIR}/boot/boot/Image"      || exit 1
# cp "${BINARIES_DIR}/Image"                            		"${KNULLI_BINARIES_DIR}/boot/boot/Image"      || exit 1
cp "${BOARD_DIR}/rk3576-anbernic-rg-vita-pro.dtb"		"${KNULLI_BINARIES_DIR}/boot/boot/rk3576-anbernic-rg-vita-pro.dtb"   || exit 1

cp "${BOARD_DIR}/boot/extlinux.conf"                            "${KNULLI_BINARIES_DIR}/boot/extlinux/"               || exit 1

exit 0
