#!/bin/bash
#
# Harvest the 32-bit (armhf) userspace of a <board>_armhf_libs build into the
# armhf cache, so an image build can install it without that second build being
# present -- the same arrangement as the cores and emulators drops.
#
# Usage: harvest-armhf.sh <board> <armhf-target-dir> <cache-dir>
#
#   board             the 64-bit board this payload is for (h700, rk3326, ...)
#   armhf-target-dir  output/<board>_armhf_libs/target
#   cache-dir         <repo>/armhf-cache
#
# KEYED ON THE BOARD, not on an ABI profile.  cores/ and emulators/ key on the
# profile because their payload is plain armv7 code, but this one is not
# interchangeable: every <board>_armhf_libs config pins that board's kernel
# headers (4.9.170 / 4.4.189 / 5.10.209 ...) and its own Mali userspace
# (mali-g31-fbdev vs mali-g31-gbm vs ...).  Sharing one armhf drop between two
# SoCs would hand a device the wrong GPU blob.

set -e

BOARD=$1
SRC=$2
CACHE=$3

test -n "$BOARD" && test -n "$SRC" && test -n "$CACHE" || {
    echo "usage: $0 <board> <armhf-target-dir> <cache-dir>" >&2
    exit 1
}

test -d "$SRC" || {
    echo "harvest-armhf: no armhf build at $SRC" >&2
    echo "  build it first: make ${BOARD}_armhf_libs-build" >&2
    exit 1
}

LOADER=ld-linux-armhf.so.3
test -e "$SRC/lib/$LOADER" || {
    echo "harvest-armhf: $SRC/lib/$LOADER is missing -- that build is not armhf" >&2
    exit 1
}

DROP="$CACHE/drop/$BOARD"
rm -rf "$DROP"
mkdir -p "$DROP/lib" "$DROP/usr-lib"

# -a keeps symlinks as symlinks: the .so -> .so.N -> .so.N.M chains are what the
# runtime linker resolves, and flattening them would triple the payload.
rsync -a --exclude="$LOADER" "$SRC/lib/"     "$DROP/lib/"
rsync -a                     "$SRC/usr/lib/" "$DROP/usr-lib/"
cp -a "$SRC/lib/$LOADER" "$DROP/$LOADER"

( cd "$DROP" && find lib usr-lib "$LOADER" \( -type f -o -type l \) | sort ) > "$DROP/files.list"

NFILES=$(wc -l < "$DROP/files.list")
NLIB=$(find "$DROP/lib" \( -type f -o -type l \) | wc -l)
NUSR=$(find "$DROP/usr-lib" \( -type f -o -type l \) | wc -l)
SIZE=$(du -sh "$DROP" | cut -f1)

{
    echo "board    $BOARD"
    echo "source   $SRC"
    echo "files    $NFILES (lib $NLIB, usr/lib $NUSR)"
    echo "size     $SIZE"
    echo "loader   $LOADER"
} > "$DROP/drop.info"

echo "harvest-armhf: $BOARD -> $DROP"
sed 's/^/  /' "$DROP/drop.info"

exit 0
