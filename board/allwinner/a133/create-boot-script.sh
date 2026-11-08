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

# One boot partition for every A133 board; the images differ only in boot0
# (the DRAM family), which the post-image script writes per boot0/<family>.img.
# U-Boot picks the board's DT from that boot0's DRAM type.

# framebuffer sizes of the boards (make-logo.sh entries)
A133_LOGOS="640x480 480x800,0,60 1024x768 1280x720"

mkdir -p "${BATOCERA_BINARIES_DIR}/boot/boot"     || exit 1

# hard link instead of a 2GB copy per image (the rootfs is never modified in place)
ln -f "${BINARIES_DIR}/rootfs.squashfs"	"${BATOCERA_BINARIES_DIR}/boot/boot/knulli.update"	2>/dev/null || \
cp "${BINARIES_DIR}/rootfs.squashfs"	"${BATOCERA_BINARIES_DIR}/boot/boot/knulli.update"	|| exit 1
cp "${BOARD_DIR}/knulli-boot.conf" 	"${BATOCERA_BINARIES_DIR}/boot/knulli-boot.conf"	|| exit 1
# boot logos, logo_<W>x<H>.bmp per framebuffer size, from the splash logo;
# /boot/bootlogo.bmp, which the splash prefers, is left to the user
SPLASH_DIR="${BOARD_DIR}/../../../package/system/knulli-splash"
for e in ${A133_LOGOS}; do
	set -- $(echo "${e}" | tr , ' ')
	"${SPLASH_DIR}/make-logo.sh" "${SPLASH_DIR}/images/logo.png" \
		"${BATOCERA_BINARIES_DIR}/boot/logos/logo_${1}.bmp" "$1" "$2" "$3"	|| exit 1
done

# raw areas: the boot package (boot0 is per image, so not in the update)
mkdir -p "${BATOCERA_BINARIES_DIR}/boot/partitions"					|| exit 1

# The boot package: our U-Boot (uboot-a133) with the vendor monitor, scp and
# the vendor DTB U-Boot uses for its own needs (PMU, MMC).  The kernel gets
# its DTB from extlinux.
PKG_DIR="${BOARD_DIR}/../../../package/boot/uboot-a133/trimui-brick/boot_package"
PACK_DIR="${BUILD_DIR}/boot_package-a133"
rm -rf "${PACK_DIR}" && mkdir -p "${PACK_DIR}"						|| exit 1
cp "${PKG_DIR}/boot_package.cfg" "${PKG_DIR}/monitor.bin" "${PKG_DIR}/scp.bin" "${PACK_DIR}" || exit 1
cp "${BINARIES_DIR}/u-boot-a133.bin" "${PACK_DIR}/u-boot.bin"				|| exit 1
# burn_key off: no 3 s wait for the PC flashing tool on every boot
sed 's/burn_key = <0x01>/burn_key = <0x00>/' "${PKG_DIR}/trimui-brick.dts" |
	"${HOST_DIR}/bin/dtc" -q -I dts -O dtb -o "${PACK_DIR}/dtb.bin" -	|| exit 1
(cd "${PACK_DIR}" && "${HOST_DIR}/bin/dragonsecboot" -pack boot_package.cfg)		|| exit 1
mkdir -p "${BINARIES_DIR}/a133-boot-packages"						|| exit 1
cp "${PACK_DIR}/boot_package.fex" "${BINARIES_DIR}/a133-boot-packages/a133_boot_package.fex" || exit 1
# boot0 of the assembled image; the post-image script writes each family's
cp "${BOARD_DIR}/boot0/trimui.img" "${BINARIES_DIR}/a133-boot-packages/boot0.img"	|| exit 1
# the copy knulli-upgrade writes to the raw area
cp "${PACK_DIR}/boot_package.fex" "${BATOCERA_BINARIES_DIR}/boot/partitions/"		|| exit 1

# extlinux: U-Boot loads the kernel, the initrd and the per-device DTB from
# the FAT partition; "auto" takes the DTB U-Boot detected, one entry per DTB
# forces a board.
BOOT="${BATOCERA_BINARIES_DIR}/boot"
mkdir -p "${BOOT}/dtb" "${BOOT}/extlinux"						|| exit 1
cp "${BINARIES_DIR}/Image"      "${BOOT}/Image"						|| exit 1
cp "${BINARIES_DIR}/initrd.lz4" "${BOOT}/initrd.lz4"					|| exit 1
cp "${BINARIES_DIR}"/sun50i-a133-*.dtb "${BOOT}/dtb/"					|| exit 1
{
	echo "# knulli A133: \"auto\" boots the detected board, the other entries force one"
	echo "default auto"
	echo "timeout 0"
	echo ""
	echo "# U-Boot sets \${fdtfile} from the board it detects"
	echo "label auto"
	echo "  kernel /Image"
	echo "  initrd /initrd.lz4"
	echo "  fdtdir /dtb/"
	echo "  append loglevel=3 console=ttyAS0,115200 vt.global_cursor_default=0 label=KNULLI rootwait"
	for dtb in "${BOOT}"/dtb/sun50i-a133-*.dtb; do
		dev=$(basename "${dtb}" .dtb); dev=${dev#sun50i-a133-}
		echo ""
		echo "label ${dev}"
		echo "  kernel /Image"
		echo "  initrd /initrd.lz4"
		echo "  fdt /dtb/$(basename "${dtb}")"
		echo "  append loglevel=3 console=ttyAS0,115200 vt.global_cursor_default=0 label=KNULLI rootwait"
	done
} > "${BOOT}/extlinux/extlinux.conf"							|| exit 1

touch "${BATOCERA_BINARIES_DIR}/boot/boot/autoresize"

exit 0
