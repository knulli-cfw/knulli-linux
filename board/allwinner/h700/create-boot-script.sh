#!/bin/bash

# HOST_DIR = host dir
# BOARD_DIR = board specific dir
# BUILD_DIR = base dir/build
# BINARIES_DIR = images dir
# TARGET_DIR = target dir
# BATOCERA_BINARIES_DIR = knulli binaries sub directory

HOST_DIR=$1
BOARD_DIR=$2
BUILD_DIR=$3
BINARIES_DIR=$4
TARGET_DIR=$5
BATOCERA_BINARIES_DIR=$6

mkdir -p "${BATOCERA_BINARIES_DIR}/boot/boot"     || exit 1

# hard link instead of a 2GB copy per image (the rootfs is never modified in place)
ln -f "${BINARIES_DIR}/rootfs.squashfs"	"${BATOCERA_BINARIES_DIR}/boot/boot/knulli.update"	2>/dev/null || \
cp "${BINARIES_DIR}/rootfs.squashfs"	"${BATOCERA_BINARIES_DIR}/boot/boot/knulli.update"	|| exit 1
cp "${BOARD_DIR}/knulli-boot.conf" 	"${BATOCERA_BINARIES_DIR}/boot/knulli-boot.conf"	|| exit 1
# one image for every board: a logo per panel size, bootlogo-<W>x<H>.bmp, from
# the splash logo (the charger, the progress bar and the device menu pick the
# one matching the panel); bootlogo.bmp is their fallback
SPLASH_DIR="${BOARD_DIR}/../../../package/system/knulli-splash"
for e in 640x480 720x480 720x720 480x640,-90; do
	set -- $(echo "${e}" | tr , ' ')
	"${SPLASH_DIR}/make-logo.sh" "${SPLASH_DIR}/images/logo.png" \
		"${BATOCERA_BINARIES_DIR}/boot/bootlogo-${1}.bmp" "$1" "$2"		|| exit 1
done
cp "${BATOCERA_BINARIES_DIR}/boot/bootlogo-640x480.bmp" \
   "${BATOCERA_BINARIES_DIR}/boot/bootlogo.bmp"						|| exit 1

# raw areas only: boot0 and the boot package (U-Boot + monitor + generic DTB)
mkdir -p "${BATOCERA_BINARIES_DIR}/boot/partitions"					|| exit 1
cp "${BOARD_DIR}/partitions/boot0.img"	"${BATOCERA_BINARIES_DIR}/boot/partitions/"	|| exit 1

# One image for every board.  The boot package carries the DTB U-Boot uses
# for its own needs (PMU, MMC, env: the same on every board), repacked here
# with the kernel's rg35xx-plus tree: uboot-h700 only repacks when buildroot
# rebuilds that package, which a later kernel rebuild does not trigger.  The
# kernel gets its per-device tree from extlinux.
KERNEL_DTB="${BINARIES_DIR}/sun50i-h700-anbernic-rg35xx-plus.dtb"
if [ -f "${KERNEL_DTB}" ]; then
	PKG_DIR="${BOARD_DIR}/../../../package/boot/uboot-h700/rg35xx-plus/boot_package"
	PACK_DIR="${BUILD_DIR}/boot_package-h700"
	rm -rf "${PACK_DIR}" && mkdir -p "${PACK_DIR}"				|| exit 1
	cp "${PKG_DIR}/boot_package.cfg" "${PKG_DIR}/u-boot.bin" \
	   "${PKG_DIR}/monitor.bin" "${PKG_DIR}/dtbo.bin" "${PACK_DIR}"		|| exit 1
	# our U-Boot (uboot-h700)
	cp "${BINARIES_DIR}/u-boot-h700.bin" "${PACK_DIR}/u-boot.bin"		|| exit 1
	cp "${KERNEL_DTB}" "${PACK_DIR}/dtb.bin"				|| exit 1
	(cd "${PACK_DIR}" && "${HOST_DIR}/bin/dragonsecboot" -pack boot_package.cfg) || exit 1
	mkdir -p "${BINARIES_DIR}/h700-boot-packages"				|| exit 1
	cp "${PACK_DIR}/boot_package.fex" \
	   "${BINARIES_DIR}/h700-boot-packages/h700_boot_package.fex"		|| exit 1
	# the copy knulli-upgrade writes to the raw area
	cp "${PACK_DIR}/boot_package.fex" "${BATOCERA_BINARIES_DIR}/boot/partitions/"	|| exit 1
fi

# extlinux: U-Boot loads the kernel, the initrd and the per-device DTB from
# the FAT partition; one entry per DTB, "default" picks the board.
BOOT="${BATOCERA_BINARIES_DIR}/boot"
mkdir -p "${BOOT}/dtb" "${BOOT}/extlinux"						|| exit 1
cp "${BINARIES_DIR}/Image"  "${BOOT}/Image"						|| exit 1
cp "${BINARIES_DIR}/initrd" "${BOOT}/initrd"						|| exit 1
cp "${BINARIES_DIR}"/sun50i-h700-anbernic-*.dtb "${BOOT}/dtb/"				|| exit 1
{
	echo "# knulli H700: one image, one entry per device; \"default\" selects the board"
	echo "default select"
	echo "timeout 0"
	for dtb in "${BOOT}"/dtb/sun50i-h700-anbernic-*.dtb; do
		dev=$(basename "${dtb}" .dtb); dev=${dev#sun50i-h700-anbernic-}
		echo ""
		echo "label ${dev}"
		echo "  kernel /Image"
		echo "  initrd /initrd"
		echo "  fdt /dtb/$(basename "${dtb}")"
		echo "  append loglevel=3 console=ttyS0,115200 vt.global_cursor_default=0 label=KNULLI rootwait elevator=noop"
	done
} > "${BOOT}/extlinux/extlinux.conf"							|| exit 1

touch "${BATOCERA_BINARIES_DIR}/boot/boot/autoresize"

exit 0
