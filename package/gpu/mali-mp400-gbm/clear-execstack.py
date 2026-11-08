#!/usr/bin/env python3
# clear PF_X on PT_GNU_STACK of a 32-bit LE ELF (glibc refuses to dlopen execstack libs)
import struct, sys

with open(sys.argv[1], 'r+b') as f:
    b = bytearray(f.read())
    phoff, = struct.unpack_from('<I', b, 0x1c)
    phentsize, phnum = struct.unpack_from('<HH', b, 0x2a)
    for i in range(phnum):
        o = phoff + i * phentsize
        if struct.unpack_from('<I', b, o)[0] == 0x6474e551:
            flags, = struct.unpack_from('<I', b, o + 24)
            struct.pack_into('<I', b, o + 24, flags & ~1)
    f.seek(0)
    f.write(b)
