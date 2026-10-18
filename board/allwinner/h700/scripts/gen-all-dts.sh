#!/bin/bash
# Regenerate board/allwinner/h700/dts/sunxi/*.dts for every H700 device from
# the vendor trees in package/boot/uboot-h700/<device>/boot_package/.
# <kernel tree> needs drivers/pinctrl/sunxi/pinctrl-sun50iw9{,-r}.c.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
KTREE=$1
[ -d "$KTREE/drivers/pinctrl/sunxi" ] || { echo "usage: $0 <linux-5.4 tree>" >&2; exit 1; }
declare -A MODEL=(
	[rg28xx]="Anbernic RG28XX" [rg34xx]="Anbernic RG34XX" [rg34xx-sp]="Anbernic RG34XX-SP"
	[rg35xx-h]="Anbernic RG35XX-H" [rg35xx-plus]="Anbernic RG35XX-Plus" [rg35xx-pro]="Anbernic RG35XX-Pro"
	[rg35xx-sp]="Anbernic RG35XX-SP" [rg40xx-h]="Anbernic RG40XX-H" [rg40xx-v]="Anbernic RG40XX-V"
	[rg-cubexx]="Anbernic RG CubeXX"
)
for dev in "${!MODEL[@]}"; do
	python3 "$HERE/build_dts.py" "$HERE/../../../../package/boot/uboot-h700/$dev/boot_package/$dev.dts" \
		"$KTREE" "${MODEL[$dev]}" "$HERE/../dts/sunxi/sun50i-h700-anbernic-$dev.dts"
done
# the RG-SP (no sticks) has no vendor tree; the rg34xx-sp one fits it
python3 "$HERE/build_dts.py" "$HERE/../../../../package/boot/uboot-h700/rg34xx-sp/boot_package/rg34xx-sp.dts" \
	"$KTREE" "Anbernic RG-SP" "$HERE/../dts/sunxi/sun50i-h700-anbernic-rg-sp.dts" rg-sp
# first boot: the rg35xx-plus tree plus one node per panel (h700-panels.conf)
python3 "$HERE/build_dts.py" "$HERE/../../../../package/boot/uboot-h700/rg35xx-plus/boot_package/rg35xx-plus.dts" \
	"$KTREE" "Anbernic H700" "$HERE/../dts/sunxi/sun50i-h700-anbernic-select.dts" select
python3 "$HERE/gen-select-dts.py" "$HERE/../dts/sunxi" "$HERE/../fsoverlay/usr/share/knulli/h700-panels.conf"
