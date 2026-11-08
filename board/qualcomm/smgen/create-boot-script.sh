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

mkdir -p "${KNULLI_BINARIES_DIR}/boot/boot" || exit 1

echo "*** Copying the Knulli base system files ***"
cp "${BINARIES_DIR}/rootfs.squashfs" "${KNULLI_BINARIES_DIR}/boot/boot/knulli.update" || exit 1

echo "*** Compressing the Kernel ***"
gzip -9c "${BINARIES_DIR}/Image" > "${BINARIES_DIR}/kernel.gz" || exit 1

# Only the DTBs this configuration builds: buildroot never removes a stale
# .dtb from images/, and ABL picks by msm-id/board-id, so a leftover DTB of a
# retired device tree for the same SoC can win over the current one.
echo "*** Appending the configured .dtb files to the end of the compressed kernel ***"
DTS_NAMES=$(sed -n 's/^BR2_LINUX_KERNEL_INTREE_DTS_NAME="\(.*\)"/\1/p' "$(dirname "${BUILD_DIR}")/.config")
for name in ${DTS_NAMES}; do
    dtb="${BINARIES_DIR}/$(basename "${name}").dtb"
    if [ -f "$dtb" ]; then
        echo "Appending: $dtb"
        cat "$dtb" >> "${BINARIES_DIR}/kernel.gz"
    else
        echo "missing DTB: $dtb" >&2
        exit 1
    fi
done

# Define the Kernel command line
# One boot image for every SM board: ABL picks the DTB appended here by msm-id/board-id.
# Per-SoC knobs that used to live on the kernel command line (sm4450: s2idle) are
# set at runtime from the fsoverlay instead.
CMDLINE="label=KNULLI rootwait console=ttyMSM0,115200n8 clk_ignore_unused pd_ignore_unused logo.nologo quiet vt.cur_default=1 vt.global_cursor_default=0"

MKBOOTIMG="${HOST_DIR}/usr/bin/mkbootimg.py"

# Comment out the missing 'gki' import since Header V0 doesn't need it.
chmod u+w "${MKBOOTIMG}" 2>/dev/null || true
sed -i 's/^from gki.generate_gki_certificate/#from gki.generate_gki_certificate/' "${MKBOOTIMG}"

echo "*** Generating the Android boot image ***"
${HOST_DIR}/bin/python3 "${MKBOOTIMG}" \
    --kernel "${BINARIES_DIR}/kernel.gz" \
    --ramdisk "${BINARIES_DIR}/initrd.lz4" \
    --kernel_offset 0x00000000 \
    --ramdisk_offset 0x00000000 \
    --tags_offset 0x00000000 \
    --os_version 12.0.0 \
    --os_patch_level "$(date '+%Y-%m')" \
    --header_version 0 \
    --cmdline "${CMDLINE}" \
    -o "${KNULLI_BINARIES_DIR}/boot/boot/Image" || exit 1

exit 0
