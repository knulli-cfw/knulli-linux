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

cp "${BINARIES_DIR}/Image"              "${KNULLI_BINARIES_DIR}/boot/boot/Image"                      || exit 1
cp "${BINARIES_DIR}/initrd.lz4"         "${KNULLI_BINARIES_DIR}/boot/boot/initrd.lz4"                 || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs"    "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"            || exit 1

cp "${BINARIES_DIR}/sm8250-retroidpocket-rpminiv2.dtb"    "${KNULLI_BINARIES_DIR}/boot/boot/"           || exit 1
cp -f "${BOARD_DIR}/grub.cfg"                           "${BINARIES_DIR}/efi-part/EFI/BOOT/grub.cfg"    || exit 1
cp -r "${BINARIES_DIR}/efi-part/EFI/"                   "${KNULLI_BINARIES_DIR}/boot/"                || exit 1

exit 0
