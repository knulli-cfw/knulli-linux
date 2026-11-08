/* Force-included into every TU by the atm7051-gcc/g++ wrappers.
 *
 * The ATM7051 sysroot's kernel headers predate the ARMv8 crypto/CRC HWCAP2
 * bits, so any vendored 7-Zip/LZMA CpuArch.c that probes for them fails to
 * compile:
 *
 *   CpuArch.c:833: error: 'HWCAP2_CRC32' undeclared
 *
 * Four Tier-2 cores vendor their own copy (fbneo's lib7z, and the
 * libchdr/deps/lzma-24.05 bundled by picodrive, pcsx_rearmed and neocd), and
 * any future core carrying libchdr will hit it too -- so this is fixed once
 * here rather than as N near-identical patches.
 *
 * Values are the standard Linux uapi ones. asm/hwcap.h in this sysroot defines
 * none of them, so there is nothing to collide with; the guards keep it safe if
 * a newer sysroot ever does. On ARMv7 the runtime checks simply return 0.
 */
#ifndef ATM7051_COMPAT_H
#define ATM7051_COMPAT_H

#if defined(__arm__) || defined(__aarch64__)
#ifndef HWCAP2_AES
#define HWCAP2_AES    (1 << 0)
#endif
#ifndef HWCAP2_PMULL
#define HWCAP2_PMULL  (1 << 1)
#endif
#ifndef HWCAP2_SHA1
#define HWCAP2_SHA1   (1 << 2)
#endif
#ifndef HWCAP2_SHA2
#define HWCAP2_SHA2   (1 << 3)
#endif
#ifndef HWCAP2_CRC32
#define HWCAP2_CRC32  (1 << 4)
#endif
#endif

#endif /* ATM7051_COMPAT_H */
