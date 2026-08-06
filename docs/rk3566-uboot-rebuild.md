# Rebuilding u-boot-rk3566.bin from source

`package/boot/uboot-rk3566/` ships a prebuilt `u-boot-rk3566.bin`
(and a separate `u-boot-rk3566-x55.bin` for the Powkiddy X55). Neither
comes with a buildroot recipe — the `.mk` only wraps `boot_package`
packing. This document is the reproducible source-to-.bin recipe so
that (a) anyone can audit the shipped binary, (b) our new
`001-rgb30-hw-rev-detect.patch` can be verified in a rebuild, and
(c) acmeplus's incoming rk3566 unification can rebase on top of our
patch set.

## Source lineage

The currently shipped `u-boot-rk3566.bin` identifies itself as:

    U-Boot 2024.07 (Sep 22 2025 - 03:13:02 +0000)

That's a build of **mainline u-boot v2024.07**, exact tag, with just
one patch on top:

- `000-DTB_DIR_boot.patch` — changes `DTB_DIR "rockchip/"` →
  `DTB_DIR "boot/"` in the anbernic-rgxx3 board code + its defconfig,
  so u-boot looks for DTBs where knulli lays them out on-disk.

Our contribution adds a second patch:

- `001-rgb30-hw-rev-detect.patch` — after mainline's SARADC-based
  board detection resolves `board_id == RGB30`, probes i2c0 for the
  tcs4525 CPU regulator at 0x40 and, on ACK, sets
  `pxe_label_override=rgb30-v2` so u-boot's extlinux parser picks the
  v2 LABEL block from our extlinux.conf. Silent no-op on v1 boards
  and on all non-RGB30 boards sharing this binary.

Both patches live in `board/rockchip/rk3566/patches/uboot/` so the
tree carries the full delta from mainline.

## Prerequisites

- aarch64 cross toolchain. On Debian/Ubuntu:
  ```sh
  sudo apt install -y gcc-aarch64-linux-gnu bison flex bc libssl-dev \
                      python3-pyelftools swig python3-setuptools
  ```
- Rockchip TPL/BL31 blobs. Mainline u-boot pulls these from the
  `rockchip/rkbin` repo at build time via the `BL31=` / `ROCKCHIP_TPL=`
  make variables. Clone `https://github.com/rockchip-linux/rkbin`
  next to your u-boot checkout; we point at
  `rkbin/bin/rk35/rk3568_bl31_v*.elf` and
  `rkbin/bin/rk35/rk3566_ddr_1056MHz_v*.bin`.
- ~1 GB free disk for the u-boot build tree.

## Rebuild steps

```sh
# 1. Fetch u-boot and rkbin at the exact tag / recent state.
git clone --branch v2024.07 --depth 1 \
    https://source.denx.de/u-boot/u-boot.git
git clone --depth 1 https://github.com/rockchip-linux/rkbin.git

# 2. Apply our two patches from the knulli-linux tree.
cd u-boot
for p in ../knulli-linux/board/rockchip/rk3566/patches/uboot/*.patch; do
    patch -p1 < "$p"
done

# 3. Configure for the rgxx3 board family (RGB30 is one of the
#    boards handled by this defconfig; SARADC decides at boot).
make CROSS_COMPILE=aarch64-linux-gnu- anbernic-rgxx3-rk3566_defconfig

# 4. Verify DM_I2C is enabled (needed by our hw-rev detect patch's
#    uclass_get_device_by_seq / dm_i2c_probe calls). Mainline defaults
#    should include it; check to be sure:
grep '^CONFIG_DM_I2C=y' .config \
  || echo 'CONFIG_DM_I2C is missing — enable it before building'

# 5. Build. Point BL31 / ROCKCHIP_TPL at the rkbin blobs.
make CROSS_COMPILE=aarch64-linux-gnu- \
     BL31=$(ls ../rkbin/bin/rk35/rk3568_bl31_v*.elf | sort -V | tail -1) \
     ROCKCHIP_TPL=$(ls ../rkbin/bin/rk35/rk3566_ddr_1056MHz_v*.bin | sort -V | tail -1) \
     -j"$(nproc)" u-boot-rockchip.bin

# 6. Copy the result into place.
cp u-boot-rockchip.bin \
   ../knulli-linux/package/boot/uboot-rk3566/u-boot-rk3566.bin
```

Rebuild for the Powkiddy X55 (separate binary) uses
`anbernic-rgxx3-rk3566-x55_defconfig` and drops into
`u-boot-rk3566-x55.bin`. It doesn't need our patch — the X55 isn't
RGB30 and the i2c probe silently no-ops there anyway, but keeping
patch set changes off the X55 binary reduces the surface for a
regression report.

## Verifying the rebuild

Boot the resulting binary on a device and look for either:

1. **Boot log** (needs serial): u-boot prints its version banner. It
   should show the date/time of your build, not `Sep 22 2025`.
2. **On the running system**: `dd if=/dev/mmcblk*boot0 bs=512 count=8k
   2>/dev/null | strings | grep 'U-Boot 2024'` reads the version
   string out of the u-boot image on the boot partition.

For RGB30 v2 detection specifically:

- On a v2 board, `env print pxe_label_override` at the u-boot prompt
  should return `rgb30-v2`.
- On a v1 board, it should be unset. `sysboot` will then pick the
  DEFAULT `rgb30-v1` label from extlinux.conf, loading the v1 DTB.

## Extlinux.conf pairing

The kernel + extlinux side lives in
`board/rockchip/rk3566/powkiddy-rgb30/boot/extlinux.conf` and expects
u-boot to set (or not set) `pxe_label_override` as above. See
`docs/rk3566-sdl2-drastic.md` for the wider drastic story that
depends on this HW-rev split coming out right.

## Longer-term: proper buildroot recipe

Options for the next iteration:

- **(a) Keep shipping the prebuilt .bin** with patches carried in-tree
  for auditability (current approach). Small diff, matches how the
  other rockchip u-boot packages in knulli work.
- **(b) Convert `package/boot/uboot-rk3566/` to a real buildroot recipe**
  that fetches u-boot v2024.07 + rkbin blobs and builds in the
  buildroot flow. Reproducible without the manual steps above, but a
  bigger PR ask that changes the delivery pattern used by every other
  rockchip u-boot package.

Recommend (a) for the first PR and revisit (b) if maintainers ask,
or as part of acmeplus's rk3566 unification if that already touches
u-boot packaging.
