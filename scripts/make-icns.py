#!/usr/bin/python3
import struct
import sys
from pathlib import Path


def chunk(kind: bytes, path: Path) -> bytes:
    payload = path.read_bytes()
    return kind + struct.pack(">I", len(payload) + 8) + payload


if len(sys.argv) != 3:
    raise SystemExit("Usage: make-icns.py <iconset> <output.icns>")

iconset = Path(sys.argv[1])
output = Path(sys.argv[2])
entries = [
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
]

body = b"".join(chunk(kind, iconset / filename) for kind, filename in entries)
output.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
