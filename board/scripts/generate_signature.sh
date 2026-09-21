#!/bin/bash

# Firmware Signature Generator
# This script generates MD5 signatures for firmware components during build.
#
# Usage:
#   generate_signature.sh BOARD_DIR BINARIES_DIR BOOT_DIR
#
# BOARD_DIR     - board-specific source directory (e.g. board/rockchip/rk3566/rg-arc-s)
# BINARIES_DIR  - buildroot images output directory
# BOOT_DIR      - assembled boot FAT directory (KNULLI_BINARIES_DIR/boot), populated
#                 by create-boot-script.sh before this script runs

BOARD_DIR=$1
BINARIES_DIR=$2
BOOT_DIR=$3

set -e

SIGNATURE_FILE="${BINARIES_DIR}/firmware.sig"

log_info() {
    echo -e "[INFO] $1"
}

log_warn() {
    echo -e "[WARN] $1"
}

# Function to calculate MD5 of a file
calculate_md5() {
    local file="$1"
    if [[ -f "$file" ]]; then
        md5sum "$file" | cut -d' ' -f1
    else
        echo "MISSING"
    fi
}

# MD5 of the rootfs: post-image-script.sh hashes it once for all the images of a build
rootfs_md5() {
    if [[ -n "${KNULLI_ROOTFS_MD5}" ]]; then
        echo "${KNULLI_ROOTFS_MD5}"
    else
        calculate_md5 "${BINARIES_DIR}/rootfs.squashfs"
    fi
}

# Function to get file size
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        stat -c%s "$file"
    else
        echo "0"
    fi
}

# Append a single file entry to the signature file.
# Args: absolute_file_path  relative_path_in_boot_fat  [key_override]
#   relative_path_in_boot_fat is the path as seen when the FAT is mounted at /boot
#   (e.g.  "boot/linux"  or  "extlinux/extlinux.conf")
add_file_entry() {
    local file="$1"
    local rel_path="$2"
    local key_override="$3"

    local md5
    local size
    local key

    md5=$(calculate_md5 "$file")
    size=$(get_file_size "$file")
    key="${key_override:-$(basename "$file")}"

    echo "${key}_md5=${md5}"   >> "$SIGNATURE_FILE"
    echo "${key}_size=${size}" >> "$SIGNATURE_FILE"
    echo "${key}_path=${rel_path}" >> "$SIGNATURE_FILE"

    if [[ "$md5" == "MISSING" ]]; then
        log_warn "File missing: $file"
    else
        log_info "Signed: ${rel_path} (MD5: ${md5:0:8}..., Size: ${size} bytes)"
    fi
}

# --- Allwinner BSP signature (h700, a133) ---
# These boards have pre-built partition images written via dd; they are tracked
# by filename only (no _path entry needed — the upgrade script has hardcoded
# dd offsets for each known partition name).
generate_signature_allwinner_bsp() {
    local board_name arch_name
    board_name=$(basename "$BOARD_DIR")
    arch_name=$(basename "$(dirname "$BOARD_DIR")")   # h700 or a133 — from path, not knulli.arch

    # Static partition images from source tree (basename == key name)
    local static_partitions=(
        "${BOARD_DIR}/partitions/boot0.img"
        "${BOARD_DIR}/partitions/boot.img"
        "${BOARD_DIR}/partitions/env.img"
    )

    for file in "${static_partitions[@]}"; do
        local md5 size bn
        md5=$(calculate_md5 "$file")
        size=$(get_file_size "$file")
        bn=$(basename "$file")
        echo "${bn}_md5=${md5}"   >> "$SIGNATURE_FILE"
        echo "${bn}_size=${size}" >> "$SIGNATURE_FILE"
        if [[ "$md5" == "MISSING" ]]; then
            log_warn "Partition file missing: $file"
        else
            log_info "Signed partition: $file (MD5: ${md5:0:8}..., Size: ${size} bytes)"
        fi
    done

    # boot_package.fex: h700/a133 build it per-board into BINARIES_DIR (with a board prefix);
    # a527 and similar keep it as a static source-tree file.  Try the build-output path first
    # and fall back to the source tree so both cases use the same key name.
    local boot_pkg="${BINARIES_DIR}/${arch_name}-boot-packages/${board_name}_boot_package.fex"
    if [[ ! -f "$boot_pkg" ]]; then
        boot_pkg="${BOARD_DIR}/partitions/boot_package.fex"
    fi
    local md5 size
    md5=$(calculate_md5 "$boot_pkg")
    size=$(get_file_size "$boot_pkg")
    echo "boot_package.fex_md5=${md5}"   >> "$SIGNATURE_FILE"
    echo "boot_package.fex_size=${size}" >> "$SIGNATURE_FILE"
    if [[ "$md5" == "MISSING" ]]; then
        log_warn "Partition file missing: $boot_pkg"
    else
        log_info "Signed partition: $boot_pkg (MD5: ${md5:0:8}..., Size: ${size} bytes)"
    fi

    # rootfs — no _path entry for backward compatibility; handled specially by the upgrade script
    local rootfs="${BINARIES_DIR}/rootfs.squashfs"
    local md5
    local size
    md5=$(rootfs_md5)
    size=$(get_file_size "$rootfs")
    echo "rootfs.squashfs_md5=${md5}"   >> "$SIGNATURE_FILE"
    echo "rootfs.squashfs_size=${size}" >> "$SIGNATURE_FILE"
    log_info "Signed rootfs: (MD5: ${md5:0:8}..., Size: ${size} bytes)"
}

# --- Simple boot-FAT signature (rk3326, rk3566/rk3568, sm8250, etc.) ---
# All updateable files live inside the boot FAT partition; no dd writes needed.
# We scan the assembled boot dir so we hash the exact files that end up on-device
# (important for rk3326 where the kernel goes through mkimage, and for rk3566
# where DTBs are renamed from the build output).
generate_signature_boot_fat() {
    if [[ -z "$BOOT_DIR" ]]; then
        log_warn "BOOT_DIR not provided — cannot generate boot-FAT signatures"
        return 1
    fi

    # --- rootfs ---
    # rootfs.squashfs is placed into the boot dir as knulli.update (renamed to
    # knulli after archiving).  Hash from BINARIES_DIR for consistency; no
    # _path entry for backward compatibility with the existing rootfs update path.
    local rootfs="${BINARIES_DIR}/rootfs.squashfs"
    local md5
    local size
    md5=$(rootfs_md5)
    size=$(get_file_size "$rootfs")
    echo "rootfs.squashfs_md5=${md5}"   >> "$SIGNATURE_FILE"
    echo "rootfs.squashfs_size=${size}" >> "$SIGNATURE_FILE"
    log_info "Signed rootfs: (MD5: ${md5:0:8}..., Size: ${size} bytes)"

    # --- Files in boot/boot/ (kernel, initrd, DTBs) ---
    # Skip the rootfs file (knulli / knulli.update) and per-device config files
    # that are not firmware (knulli.board, firmware.sig, autoresize).
    local skip_pattern="^(knulli|knulli\.update|knulli\.board|firmware\.sig|autoresize)$"
    if [[ -d "${BOOT_DIR}/boot" ]]; then
        for f in "${BOOT_DIR}/boot/"*; do
            [[ -f "$f" ]] || continue
            local bn
            bn=$(basename "$f")
            if echo "$bn" | grep -qE "$skip_pattern"; then
                continue
            fi
            add_file_entry "$f" "boot/${bn}"
        done
    fi

    # --- Boot configuration ---
    # extlinux (RK3326, RK3566)
    if [[ -f "${BOOT_DIR}/extlinux/extlinux.conf" ]]; then
        add_file_entry "${BOOT_DIR}/extlinux/extlinux.conf" "extlinux/extlinux.conf"
    fi

    # GRUB / EFI (SM8250 and other EFI-booting platforms)
    if [[ -f "${BOOT_DIR}/EFI/BOOT/grub.cfg" ]]; then
        add_file_entry "${BOOT_DIR}/EFI/BOOT/grub.cfg" "EFI/BOOT/grub.cfg"
    fi

    # U-Boot script / boot.ini (RK3326 and similar)
    if [[ -f "${BOOT_DIR}/boot.ini" ]]; then
        add_file_entry "${BOOT_DIR}/boot.ini" "boot.ini"
    fi
}

# --- Main ---
generate_signature() {
    log_info "Generating firmware signature..."

    VERSION=$(cat "${BINARIES_DIR}/../target/usr/share/knulli/knulli.version")
    ARCH=$(cat "${BINARIES_DIR}/../target/usr/share/knulli/knulli.arch" 2>/dev/null || echo "unknown")

    cat > "$SIGNATURE_FILE" << EOF
# Firmware Signature File
# Generated on: $(date)

[metadata]
version="$VERSION"
board=$(basename "$BOARD_DIR")
arch=$ARCH
timestamp=$(date +%s)
build_date=$(date -Iseconds)

[partitions]
EOF

    # Detect platform from the board directory path
    if [[ "$BOARD_DIR" == */allwinner/h700/* ]] || [[ "$BOARD_DIR" == */allwinner/a133/* ]] || [[ "$BOARD_DIR" == */allwinner/a527/* ]]; then
        generate_signature_allwinner_bsp
    else
        generate_signature_boot_fat
    fi

    log_info "Firmware signature generated: $SIGNATURE_FILE"
}

# Remove stale signature file before regenerating
[[ -f "$SIGNATURE_FILE" ]] && rm "$SIGNATURE_FILE"

generate_signature

log_info "Signature generation complete!"

exit 0
