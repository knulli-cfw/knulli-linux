#!/bin/bash
#
# make-logo.sh <source.png> <output.png|output.bmp> <W>x<H> [rotate] [fit]
#
# One boot/splash logo of the given final size from the 1920x1080 source:
#   rotate  degrees applied last (90, -90): the logo is laid out on the
#           landscape <H>x<W> canvas and turned, for panels mounted rotated
#   fit     the artwork is centred at <fit>% of the canvas width, on the
#           source's background colour (vertical panels); without it the
#           source is scaled to fill the canvas and centre-cropped
# A .bmp output is written as 32-bit BMP v4, what the boot splash loads.

set -e

SRC=$1 OUT=$2 SIZE=$3 ROT=${4:-0} FIT=$5

if [ ! -f "${SRC}" ] || [ -z "${OUT}" ] || ! echo "${SIZE}" | grep -qE '^[0-9]+x[0-9]+$'; then
	echo "usage: $0 <source.png> <output.png|.bmp> <W>x<H> [rotate] [fit%]" >&2
	exit 1
fi

W=${SIZE%x*} H=${SIZE#*x}
case "${ROT}" in
	0)		CW=$W CH=$H ;;
	90|-90|270)	CW=$H CH=$W ;;
	*)		echo "$0: rotate must be 0, 90 or -90" >&2; exit 1 ;;
esac

if [ -n "${FIT}" ]; then
	BG=$(convert "${SRC}" -format '%[pixel:p{5,5}]' info:)
	SW=$(convert "${SRC}" -format '%w' info:)
	ART=$(convert "${SRC}" -fuzz 8% -trim -format '%w' info:)
	SCALE=(-resize "$(( CW * FIT * SW / (100 * ART) ))x" -background "${BG}")
else
	SCALE=(-resize "${CW}x${CH}^")
fi

FMT=()
case "${OUT}" in
	*.bmp) FMT=(-define bmp:format=bmp4) ;;
esac

mkdir -p "$(dirname "${OUT}")"
convert "${SRC}" "${SCALE[@]}" -gravity center -extent "${CW}x${CH}" -rotate "${ROT}" "${FMT[@]}" "${OUT}"
