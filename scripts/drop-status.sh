#!/bin/bash
#
# Print every board with the ABI profile it belongs to and the state of the two
# drops it consumes.
#
# A drop is shared: the key, not the board, is what gets built.  Boards on the
# same key show the same status because they are looking at the same directory.
#
#   cores     keyed on PROFILE alone -- cores link only libGLESv2/libEGL, which
#             every GPU stack provides.
#   emulators keyed on PROFILE and GPU -- emulators link the vendor GL stack, so
#             a Mali payload cannot run on an Adreno board.  "mali" is the
#             incumbent and keeps the unsuffixed key.
#
# "use" is whether this board's config actually consumes the drop; a board with
# a built drop it does not consume is compiling that content from source.
#
# STALE marks a drop older than the buildroot submodule's current commit -- the
# library set it was built against has since moved, which shows up as missing
# sonames at target-finalize.
#
# Usage: scripts/drop-status.sh [-v]
#   -v  also list the drop paths and their dates

set -u

PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
OVERLAY="${PROJECT_DIR}/package/cores/libretro-super/overlay"
CORES_CACHE="${PROJECT_DIR}/cores-cache/drop"
EMUS_CACHE="${PROJECT_DIR}/emulators-cache/drop"

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

# The reference point for staleness: a drop built before the current buildroot
# was checked out was linked against a different library set.
BR_EPOCH=$(git -C "${PROJECT_DIR}/buildroot" log -1 --format=%ct 2>/dev/null || echo 0)

age_state() {
    # $1 = a file whose mtime dates the drop; prints "built" or "STALE"
    local f=$1 t
    t=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    if [ "$BR_EPOCH" -gt 0 ] && [ "$t" -lt "$BR_EPOCH" ]; then
        echo "STALE"
    else
        echo "built"
    fi
}

printf "%-12s %-24s %-8s  %-24s %-12s %-4s  %-32s %-12s %-4s  %s\n" \
    BOARD ARCH GPU "CORES DROP" STATUS USE "EMULATORS DROP" STATUS USE REFERENCE
printf "%.0s-" {1..152}; echo

for cfg in "${PROJECT_DIR}"/configs/knulli-*.board; do
    board=$(basename "$cfg" .board); board=${board#knulli-}

    device=$(grep -oP 'BR2_PACKAGE_LIBRETRO_SUPER_DEVICE="\K[^"]+' "$cfg" 2>/dev/null)
    [ -n "$device" ] || continue

    dfile="${OVERLAY}/devices/${device}.device"
    if [ ! -f "$dfile" ]; then
        printf "%-12s %-16s %s\n" "$board" "?" "no ${dfile#$PROJECT_DIR/}"
        continue
    fi
    profile=$(awk '$1=="PROFILE"{print $2}' "$dfile")
    gpu=$(awk '$1=="GPU"{print $2}' "$dfile")
    [ -n "$gpu" ] || gpu=mali

    ckey="$profile"
    ekey="$profile"
    [ "$gpu" != "mali" ] && ekey="${profile}-${gpu}"

    # Does this board's config consume each drop?
    grep -q "^BR2_PACKAGE_KNULLI_EXTERNAL_LIBRETRO_CORES=y" "$cfg" && cuse=yes || cuse=NO
    grep -q "^BR2_PACKAGE_KNULLI_EXTERNAL_EMULATORS=y"      "$cfg" && euse=yes || euse=NO

    # Cores drop: cores/ is the payload, drop.info dates it.
    if [ -d "${CORES_CACHE}/${ckey}/cores" ]; then
        n=$(find "${CORES_CACHE}/${ckey}/cores" -maxdepth 1 -name '*.so' | wc -l)
        cstate="$(age_state "${CORES_CACHE}/${ckey}/drop.info") ${n}"
        [ -f "${CORES_CACHE}/${ckey}/PARTIAL" ] && cstate="PARTIAL ${n}"
    else
        cstate="MISSING"
    fi

    # Emulators drop: drop.info records the package count.
    if [ -f "${EMUS_CACHE}/${ekey}/drop.info" ]; then
        n=$(awk '$1=="packages"{print $2}' "${EMUS_CACHE}/${ekey}/drop.info")
        estate="$(age_state "${EMUS_CACHE}/${ekey}/drop.info") ${n:-?}"
    else
        estate="MISSING"
    fi

    ref=$("${PROJECT_DIR}/package/emulators/knulli-emulators-drop/reference-board.sh" \
            "$OVERLAY" "$device" 2>/dev/null) || ref="none"

    printf "%-12s %-24s %-8s  %-24s %-12s %-4s  %-32s %-12s %-4s  %s\n" \
        "$board" "$profile" "$gpu" "$ckey" "$cstate" "$cuse" "$ekey" "$estate" "$euse" "$ref"
done

echo
echo "STATUS   built N / STALE N (N = cores or packages) / PARTIAL / MISSING"
echo "USE      whether this board's .board consumes the drop; NO means it compiles that content"
echo "STALE    drop predates the current buildroot commit ($(date -d "@${BR_EPOCH}" +%Y-%m-%d 2>/dev/null))"
echo "REFERENCE  board an emulators drop must be harvested on; 'none' = no reference defined"

if [ "$VERBOSE" = 1 ]; then
    echo
    echo "Drop directories:"
    for d in "${CORES_CACHE}"/*/ "${EMUS_CACHE}"/*/; do
        [ -d "$d" ] || continue
        printf "  %-56s %s\n" "${d#$PROJECT_DIR/}" \
            "$(stat -c %y "$d/drop.info" 2>/dev/null | cut -d' ' -f1 || echo '-')"
    done
fi
