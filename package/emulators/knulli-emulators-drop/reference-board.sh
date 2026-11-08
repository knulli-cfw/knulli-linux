#!/bin/bash
#
# Print the board an emulator drop is harvested from, for the (profile, GPU)
# the given board belongs to.  Used by %-emulators-drop in the top-level
# Makefile, both to redirect a request made on a consumer board and to guard
# the harvest itself.
#
# Usage: reference-board.sh OVERLAY_DIR BOARD

OVERLAY=$1
BOARD=$2

set -e

device="${OVERLAY}/devices/${BOARD}.device"
test -f "$device" || {
    echo "emulators-drop: no device file ${device}" >&2
    exit 1; }

profile=$(awk '$1=="PROFILE"{print $2}' "$device")
gpu=$(awk '$1=="GPU"{print $2}' "$device")

pf="${OVERLAY}/profiles/${profile}.profile"
test -f "$pf" || {
    echo "emulators-drop: no profile ${pf}" >&2
    exit 1; }

# The reference is per (profile, GPU).  "mali" is the incumbent and uses the
# unsuffixed EMULATORS_BOARD, falling back to SYSROOT_BOARD.
if [ -n "$gpu" ] && [ "$gpu" != "mali" ]; then
    key=$(echo "$gpu" | tr 'a-z' 'A-Z')
    ref=$(awk -v k="EMULATORS_BOARD_${key}" '$1==k{print $2}' "$pf")
    test -n "$ref" || {
        echo "emulators-drop: no EMULATORS_BOARD_${key} in ${pf}" >&2
        echo "  ${BOARD} is ${gpu} on ${profile} and needs its own drop; name its" >&2
        echo "  reference board in the profile before harvesting." >&2
        exit 1; }
else
    ref=$(awk '$1=="EMULATORS_BOARD"{print $2}' "$pf")
    test -n "$ref" || ref=$(awk '$1=="SYSROOT_BOARD"{print $2}' "$pf")
fi

test -n "$ref" || {
    echo "emulators-drop: no reference board for ${profile}" >&2
    exit 1; }

echo "$ref"
