#!/usr/bin/env python3
"""uboot-head.py <in u-boot.bin> <out> [size]: pad an Allwinner U-Boot image to
<size> (default 1 MiB, like the vendor's) and fill the 'uboot' header's
length fields and checksum the way the vendor's update_uboot tool does."""
import struct, sys
STAMP = 0x5F0A6C39
d = bytearray(open(sys.argv[1], 'rb').read())
size = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x100000
assert d[4:9] == b'uboot', 'no uboot header'
assert len(d) <= size, 'image larger than %#x' % size
d += b'\xff' * (size - len(d))
struct.pack_into('<I', d, 0x14, size)   # length
struct.pack_into('<I', d, 0x18, size)   # uboot_length
struct.pack_into('<I', d, 0x0c, STAMP)  # check_sum placeholder
s = sum(struct.unpack_from('<%dI' % (size // 4), d)) & 0xffffffff
struct.pack_into('<I', d, 0x0c, s)
open(sys.argv[2], 'wb').write(d)
print('wrote %s: %d bytes, checksum %#x' % (sys.argv[2], size, s))
