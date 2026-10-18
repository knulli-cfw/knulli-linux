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
mkdir -p "${KNULLI_BINARIES_DIR}/boot/fdts"       || exit 1
mkdir -p "${KNULLI_BINARIES_DIR}/boot/dtbs"       || exit 1

cp "${BINARIES_DIR}/Image"                            "${KNULLI_BINARIES_DIR}/boot/boot/linux"            || exit 1
cp "${BINARIES_DIR}/initrd.lz4"                                    "${KNULLI_BINARIES_DIR}/boot/boot/initrd.lz4"       || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs"                               "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"    || exit 1

# FIXME: currently copying a patched dtb
cp "${BINARIES_DIR}"/*.dtb "${KNULLI_BINARIES_DIR}/boot/fdts/"                 || exit 1

# U-Boot dtbs, one per hwrev profile; U-Boot loads dtbs/<profile>.dtb
cp "${BOARD_DIR}/uboot-dtbs/"*.dtb "${KNULLI_BINARIES_DIR}/boot/dtbs/"         || exit 1
cp "${BOARD_DIR}/boot/hwrev.ini.example" "${KNULLI_BINARIES_DIR}/boot/"         || exit 1

# FIXME: Workaround until we have the proper mali blobs repo
#cp "${BOARD_DIR}/libmali.so.1.9.0"	                               "${TARGET_DIR}/usr/lib/libMali.so"		           || exit 1
cp "${BOARD_DIR}/boot/extlinux.conf"                               "${KNULLI_BINARIES_DIR}/boot/extlinux/"             || exit 1
cp -r "${BOARD_DIR}/battery" "${KNULLI_BINARIES_DIR}/boot/"                 || exit 1
cp -r "${BOARD_DIR}/bootlogos/"*.bmp "${KNULLI_BINARIES_DIR}/boot/"                 || exit 1
cp -r "${BOARD_DIR}/resource.img" "${KNULLI_BINARIES_DIR}/boot/"                 || exit 1

exit 0
