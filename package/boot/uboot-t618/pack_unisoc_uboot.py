#!/usr/bin/env python3
"""
Pack a raw U-Boot binary into an existing Unisoc DHTB uboot image template.

This keeps the known-good DHTB + SIMGHDR wrapper from a stock or previously
booting image, replaces the payload area with a new U-Boot binary padded to the
original payload size, and refreshes the DHTB/SIMGHDR hashes.
"""

import argparse
import hashlib
import struct
import sys
from pathlib import Path
from rehash import rehash  # type: ignore  # noqa: E402


DHTB_MAGIC = b"DHTB"
HEADER_SIZE = 0x200


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("template", help="Known-good DHTB uboot image to reuse as wrapper")
    ap.add_argument("payload", help="Raw U-Boot binary to embed")
    ap.add_argument("output", help="Output DHTB image path")
    ap.add_argument(
        "--fill-byte",
        default="00",
        help="Hex byte used to pad the payload area (default: 00)",
    )
    args = ap.parse_args()

    template_path = Path(args.template)
    payload_path = Path(args.payload)
    output_path = Path(args.output)

    try:
        fill_byte = int(args.fill_byte, 16)
    except ValueError as exc:
        raise SystemExit(f"Invalid --fill-byte {args.fill_byte!r}: {exc}") from exc
    if not 0 <= fill_byte <= 0xFF:
        raise SystemExit("--fill-byte must be in range 00..ff")

    image = bytearray(template_path.read_bytes())
    payload = payload_path.read_bytes()

    if image[:4] != DHTB_MAGIC:
        raise SystemExit(f"{template_path} is not a DHTB image")

    payload_size = struct.unpack("<Q", image[0x30:0x38])[0]
    if len(payload) > payload_size:
        raise SystemExit(
            f"Payload too large: {len(payload)} bytes > DHTB payload size {payload_size}"
        )

    payload_start = HEADER_SIZE
    payload_end = payload_start + payload_size

    image[payload_start:payload_end] = bytes([fill_byte]) * payload_size
    image[payload_start:payload_start + len(payload)] = payload

    result = rehash(image)
    output_path.write_bytes(image)

    print(f"Template:     {template_path}")
    print(f"Payload:      {payload_path}")
    print(f"Output:       {output_path}")
    print(f"Payload size: {len(payload)} / {payload_size} bytes")
    print(f"Pad byte:     0x{fill_byte:02x}")
    print(f"SHA256:       {hashlib.sha256(image).hexdigest()}")
    print(f"DHTB hash:    {result['new_hash']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
