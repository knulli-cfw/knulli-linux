#!/bin/bash
#
# Emit the manifest shipped inside (and beside) the cores squashfs.
#
# Usage: gen-cores-manifest.sh CORES_DIR PROFILE SUPER_REV OUTPUT

CORES_DIR=$1
PROFILE=$2
SUPER_REV=$3
OUTPUT=$4

set -e

test -d "${CORES_DIR}" || {
    echo "gen-cores-manifest: no such directory ${CORES_DIR}" >&2
    exit 1
}

mkdir -p "$(dirname "${OUTPUT}")"

{
    echo "# profile      ${PROFILE}"
    echo "# libretro-super ${SUPER_REV}"
    echo "# generated    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# name  size  mtime  sha256"
    cd "${CORES_DIR}"
    for so in *.so; do
        [ -e "$so" ] || continue
        printf '%s  %s  %s  %s\n' \
            "$so" \
            "$(stat -c %s "$so")" \
            "$(date -u -d "@$(stat -c %Y "$so")" +%Y-%m-%dT%H:%M:%SZ)" \
            "$(sha256sum "$so" | cut -d' ' -f1)"
    done
} > "${OUTPUT}"

COUNT=$(grep -cv '^#' "${OUTPUT}" || true)
echo "[INFO] libretro-super: manifest lists ${COUNT} cores"

exit 0
