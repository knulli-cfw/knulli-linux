#!/bin/bash
#
# Check that the image provides what the drop's binaries need.
#
# One drop serves every board on an ABI, but the boards do not ship identical
# rootfs: a board whose config drops a library still installs the same emulator
# binaries.  Without this check that failure is invisible until a user launches
# the emulator and it exits with a loader error.  With it, the board's build
# stops and names the missing library.
#
# Sonames only -- not versions.  Same buildroot, same profile, so a soname that
# is present is the same library; what varies between boards is whether it is
# present at all.
#
# Usage: check-sonames.sh SONAMES_LIST TARGET_DIR

SONAMES_LIST=$1
TARGET_DIR=$2

test -f "${SONAMES_LIST}" || {
    echo "check-sonames: missing ${SONAMES_LIST}" >&2
    exit 1
}

# Where a dynamic loader would look, plus the GPU stack's own directory: the
# Mali and PowerVR blobs install libEGL/libGLESv2 outside the default paths on
# some boards, and they are exactly the libraries most emulators need.
SEARCH_DIRS=(
    "${TARGET_DIR}/lib"
    "${TARGET_DIR}/usr/lib"
    "${TARGET_DIR}/usr/lib/gpu"
    "${TARGET_DIR}/usr/lib/aarch64-linux-gnu"
    "${TARGET_DIR}/usr/lib/arm-linux-gnueabihf"
)

MISSING=""
while read -r soname; do
    [ -n "${soname}" ] || continue
    case "${soname}" in \#*) continue ;; esac
    found=""
    for dir in "${SEARCH_DIRS[@]}"; do
        if [ -e "${dir}/${soname}" ]; then
            found=y
            break
        fi
    done
    # A few libraries are installed under a versioned name only, with the
    # soname recorded inside them; look one level deeper before giving up.
    if [ -z "${found}" ]; then
        for dir in "${SEARCH_DIRS[@]}"; do
            if compgen -G "${dir}/${soname}*" > /dev/null 2>&1; then
                found=y
                break
            fi
        done
    fi
    [ -n "${found}" ] || MISSING="${MISSING} ${soname}"
done < "${SONAMES_LIST}"

if [ -n "${MISSING}" ]; then
    echo "" >&2
    echo "knulli-emulators-drop: the image does not provide libraries the drop needs:" >&2
    for soname in ${MISSING}; do
        echo "    ${soname}" >&2
    done
    echo "" >&2
    echo "The drop was built against a different library set than this board ships." >&2
    echo "Either this board's config drops something the emulators link against, or" >&2
    echo "the drop is stale and needs a refresh (make <board>-emulators-drop)." >&2
    echo "" >&2
    exit 1
fi

echo "[INFO] knulli-emulators-drop: all $(grep -cve '^\s*$' "${SONAMES_LIST}") required sonames are present"
exit 0
