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
# resource.img carries rk-kernel.dtb, the tree U-Boot binds its own devices
# from; it must be byte-identical to the DTB extlinux loads, or U-Boot resolves
# names in the wrong blob and aborts (seen as a UFS "cannot ioremap" crash).
# Repack the vendor image (logos, charge animation) with the DTB just built.
RESOURCE_TOOL=$(ls "${BUILD_DIR}"/linux-[0-9a-f]*/scripts/resource_tool 2>/dev/null | head -n 1)
[ -x "${RESOURCE_TOOL}" ] || { echo "rg-vita-pro: no resource_tool in the kernel build" >&2; exit 1; }
RES_DIR="${BUILD_DIR}/resource-rg-vita-pro"
rm -rf "${RES_DIR}" && mkdir -p "${RES_DIR}"					|| exit 1
"${RESOURCE_TOOL}" --unpack --image="${BOARD_DIR}/resource.img" "${RES_DIR}" >/dev/null || exit 1
cp "${BINARIES_DIR}/rk3576-anbernic-rg-vita-pro.dtb" "${RES_DIR}/rk-kernel.dtb"	|| exit 1
(cd "${RES_DIR}" && "${RESOURCE_TOOL}" --pack --image="${BINARIES_DIR}/resource.img" \
	rk-kernel.dtb battery_0.bmp battery_1.bmp battery_2.bmp battery_3.bmp \
	battery_4.bmp battery_5.bmp battery_fail.bmp logo.bmp logo_kernel.bmp >/dev/null) || exit 1
cp "${BOARD_DIR}/u-boot.img"		                	"${BINARIES_DIR}/u-boot.img"              || exit 1
cp "${BINARIES_DIR}/initrd.lz4"                                 "${KNULLI_BINARIES_DIR}/boot/boot/initrd.lz4"         || exit 1
cp "${BINARIES_DIR}/rootfs.squashfs"                            "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update"      || exit 1
cp "${BINARIES_DIR}/Image"					"${KNULLI_BINARIES_DIR}/boot/boot/Image"      || exit 1
cp "${BINARIES_DIR}/rk3576-anbernic-rg-vita-pro.dtb"		"${KNULLI_BINARIES_DIR}/boot/boot/rk3576-anbernic-rg-vita-pro.dtb"   || exit 1

# boot logo for progressbar_rk (logo_<W>x<H>.bmp of the framebuffer, portrait)
cp "${BOARD_DIR}/bootlogos/"*.bmp "${KNULLI_BINARIES_DIR}/boot/"		|| exit 1

cp "${BOARD_DIR}/boot/extlinux.conf"                            "${KNULLI_BINARIES_DIR}/boot/extlinux/"               || exit 1

exit 0
