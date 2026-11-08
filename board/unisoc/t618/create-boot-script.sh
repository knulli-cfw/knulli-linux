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

DTB="ums512-rg-rotate.dtb"

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot"     || exit 1
mkdir -p "${KNULLI_BINARIES_DIR}/boot/extlinux" || exit 1

cp "${BINARIES_DIR}/Image"              "${KNULLI_BINARIES_DIR}/boot/boot/Image"            || exit 1
cp "${BINARIES_DIR}/${DTB}"             "${KNULLI_BINARIES_DIR}/boot/boot/${DTB}"           || exit 1
cp "${BINARIES_DIR}/initrd.lz4"         "${KNULLI_BINARIES_DIR}/boot/boot/initrd.lz4"       || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs"    "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"    || exit 1

cp "${BOARD_DIR}/boot/extlinux.conf"    "${KNULLI_BINARIES_DIR}/boot/extlinux/"             || exit 1

# The SPL finds U-Boot by the GPT partition name "uboot", so it is a raw
# partition rather than a file in the boot filesystem.  genimage.cfg pulls it
# straight out of BINARIES_DIR as ../../u-boot.img.
#
# Produced by the uboot-t618 package's install-images step, which runs before
# post-image -- it is NOT copied from the board directory any more.  Copying a
# hand-dropped board-dir image over it would silently replace the one this build
# just produced with a stale one.  Checked here rather than left to genimage so
# the message names the package instead of a relative path.
if [ ! -f "${BINARIES_DIR}/u-boot.img" ]; then
    echo "ERROR: ${BINARIES_DIR}/u-boot.img is missing -- the image would not boot." >&2
    echo "       It is built by package/boot/uboot-t618 (BR2_PACKAGE_UBOOT_T618)." >&2
    exit 1
fi

exit 0
