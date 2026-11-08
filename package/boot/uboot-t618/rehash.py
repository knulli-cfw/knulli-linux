#!/usr/bin/env python3
"""
Recompute DHTB SHA256 and SIMGHDR data hash for a modified Unisoc DHTB image.

This is the universal "re-hash" tool. After modifying the data payload of any
DHTB image (SPL, SML, TrustOS, UBoot), run this to regenerate the integrity
hashes. The RSA signature in the SIMGHDR will become invalid, but since SPL
signature verification is bypassed after patching, only the DHTB hash matters
for BootROM acceptance, and the SIMGHDR data hash is what SPL's (now-NOPed)
verify routine would read.

Usage:
    python3 rehash.py <image.img>               # in-place update
    python3 rehash.py <image.img> -o <out.img>  # write to new file

Exit codes:
    0 - success (hashes updated)
    1 - error (not a DHTB image, truncated, etc.)
"""

import argparse
import hashlib
import struct
import sys


DHTB_MAGIC = b"DHTB"
SIMGHDR_MAGIC = b"SIMGHDR\x00"


def rehash(data: bytearray) -> dict:
    """Recompute DHTB hash and SIMGHDR data hash in-place.

    Returns a dict describing what was done.
    """
    if data[0:4] != DHTB_MAGIC:
        raise ValueError("Not a DHTB image (magic missing)")

    data_size = struct.unpack("<Q", data[0x30:0x38])[0]
    if 0x200 + data_size > len(data):
        raise ValueError(
            f"Truncated image: data_size=0x{data_size:x} "
            f"but only {len(data)} bytes available"
        )

    # Compute new SHA256 over the data payload
    payload = bytes(data[0x200:0x200 + data_size])
    new_hash = hashlib.sha256(payload).digest()
    old_dhtb = bytes(data[8:0x28])

    result = {
        "data_size": data_size,
        "old_dhtb_hash": old_dhtb.hex(),
        "new_hash": new_hash.hex(),
        "dhtb_changed": old_dhtb != new_hash,
        "simghdr_changed": False,
    }

    # Update DHTB header hash
    data[8:0x28] = new_hash

    # Update SIMGHDR data hash copy if SIMGHDR present
    simghdr_off = 0x200 + data_size
    if simghdr_off + 1172 <= len(data) and data[simghdr_off:simghdr_off+8] == SIMGHDR_MAGIC:
        hash_off = simghdr_off + 0x16C
        old_simghdr = bytes(data[hash_off:hash_off + 32])
        data[hash_off:hash_off + 32] = new_hash
        result["simghdr_changed"] = old_simghdr != new_hash
        result["old_simghdr_hash"] = old_simghdr.hex()
        result["simghdr_present"] = True
    else:
        result["simghdr_present"] = False

    return result


def main():
    ap = argparse.ArgumentParser(description="Re-hash a modified Unisoc DHTB image")
    ap.add_argument("image", help="Path to the DHTB image to re-hash")
    ap.add_argument("-o", "--output", help="Output file (default: overwrite input)")
    ap.add_argument("-q", "--quiet", action="store_true", help="Minimal output")
    args = ap.parse_args()

    with open(args.image, "rb") as f:
        data = bytearray(f.read())

    try:
        result = rehash(data)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    out_path = args.output or args.image
    with open(out_path, "wb") as f:
        f.write(data)

    if not args.quiet:
        print(f"Rehashed {args.image}")
        print(f"  data_size:     0x{result['data_size']:x}")
        print(f"  new hash:      {result['new_hash']}")
        if result['dhtb_changed']:
            print(f"  old DHTB hash: {result['old_dhtb_hash']}")
            print("  DHTB hash:     UPDATED")
        else:
            print("  DHTB hash:     unchanged (code was unmodified)")
        if result['simghdr_present']:
            if result['simghdr_changed']:
                print(f"  old SIMGHDR:   {result['old_simghdr_hash']}")
                print("  SIMGHDR hash:  UPDATED")
            else:
                print("  SIMGHDR hash:  unchanged")
        else:
            print("  SIMGHDR:       not present (unsigned image or truncated)")
        print(f"  wrote:         {out_path}")


if __name__ == "__main__":
    main()
