#!/usr/bin/env python3
"""mkbootimg-h700.py <Image> <initrd cpio> <cmdline> <out boot.img>

Android boot image v0 for the vendor U-Boot 2018 (boot_normal: sunxi_flash
read 45000000 boot; bootm 45000000).  Load addresses are the ones every
vendor H700 boot.img uses.  The DTB is not in here: U-Boot hands the kernel
the one from boot_package.
"""
import gzip, hashlib, struct, sys

PAGE = 2048
KERNEL_ADDR = 0x40080000
RAMDISK_ADDR = 0x42000000
SECOND_ADDR = 0x40f00000
TAGS_ADDR = 0x40000100
NAME = b'sun50i_arm64'

image, initrd, cmdline, out = sys.argv[1:5]
kernel = open(image, 'rb').read()
ramdisk = gzip.compress(open(initrd, 'rb').read(), 9, mtime=0)
cmd = cmdline.encode()
if len(cmd) >= 512:
    sys.exit('cmdline is %d bytes, v0 holds 511' % len(cmd))

# arm64 Image header: text_offset @8, image_size @16 (includes BSS)
text_offset, image_size = struct.unpack_from('<QQ', kernel, 8)
end = KERNEL_ADDR + image_size
if end > RAMDISK_ADDR:
    sys.exit('kernel footprint ends at 0x%x, past the ramdisk at 0x%x' % (end, RAMDISK_ADDR))

sha = hashlib.sha1()
for blob in (kernel, ramdisk, b''):
    sha.update(blob)
    sha.update(struct.pack('<I', len(blob)))

hdr = bytearray(PAGE)
struct.pack_into('<8s10I', hdr, 0, b'ANDROID!',
                 len(kernel), KERNEL_ADDR, len(ramdisk), RAMDISK_ADDR,
                 0, SECOND_ADDR, TAGS_ADDR, PAGE, 0, 0)
hdr[48:64] = NAME.ljust(16, b'\0')
hdr[64:576] = cmd.ljust(512, b'\0')
hdr[576:608] = sha.digest().ljust(32, b'\0')


def pad(b):
    return b + b'\0' * (-len(b) % PAGE)


img = bytes(hdr) + pad(kernel) + pad(ramdisk)
open(out, 'wb').write(img)
print('%s: %d bytes, kernel ends 0x%x (ramdisk 0x%x)' % (out, len(img), end, RAMDISK_ADDR))
