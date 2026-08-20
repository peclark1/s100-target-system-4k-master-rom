#!/usr/bin/env python3
"""Build and verify the IMSAI target-system ROM images.

The assembler produces only the monitor body beginning at F000H. This script
pads that body through FEFFH, installs the published 256-byte CDBL image at
FF00H, and emits both the logical 4K CPU image and an 8K 27C64/28C64 programmer
image for the modified Altair FDC+.

For the target FDC+ configuration, CPU F000H-FFFFH corresponds to the upper
4K half of the physical 8K ROM device, so the lower half is filled with FFH.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

ROM_BASE = 0xF000
CDBL_ADDR = 0xFF00
MONITOR_MAX = CDBL_ADDR - ROM_BASE  # 0xF00 bytes
LOGICAL_ROM_SIZE = 0x1000
DEVICE_ROM_SIZE = 0x2000
ERASED = 0xFF

ROM4K_NAME = "IMSAI_TARGET_MONITOR_4K.bin"
ROM8K_NAME = "IMSAI_TARGET_MONITOR_28C64.bin"


def parse_intel_hex(path: Path) -> dict[int, int]:
    memory: dict[int, int] = {}
    upper = 0

    for line_number, raw in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise ValueError(f"{path}:{line_number}: invalid Intel HEX record")

        record = bytes.fromhex(line[1:])
        if len(record) < 5:
            raise ValueError(f"{path}:{line_number}: record too short")
        if sum(record) & 0xFF:
            raise ValueError(f"{path}:{line_number}: checksum failure")

        count = record[0]
        address = (record[1] << 8) | record[2]
        kind = record[3]
        payload = record[4 : 4 + count]

        if len(payload) != count:
            raise ValueError(f"{path}:{line_number}: truncated payload")

        if kind == 0x00:
            for offset, value in enumerate(payload):
                memory[upper + address + offset] = value
        elif kind == 0x01:
            break
        elif kind == 0x04:
            if count != 2:
                raise ValueError(f"{path}:{line_number}: bad extended address record")
            upper = int.from_bytes(payload, "big") << 16
        else:
            raise ValueError(f"{path}:{line_number}: unsupported record type {kind:02X}")

    return memory


def extract_cdbl(path: Path) -> bytes:
    memory = parse_intel_hex(path)
    expected = range(CDBL_ADDR, CDBL_ADDR + 0x100)
    missing = [addr for addr in expected if addr not in memory]
    if missing:
        raise ValueError(f"CDBL image is incomplete; first missing byte is {missing[0]:04X}H")

    outside = [addr for addr in memory if not CDBL_ADDR <= addr <= 0xFFFF]
    if outside:
        raise ValueError(f"CDBL HEX contains unexpected data at {outside[0]:04X}H")

    cdbl = bytes(memory[addr] for addr in expected)
    if len(cdbl) != 0x100:
        raise AssertionError("internal CDBL size error")
    return cdbl


def build_images(monitor: bytes, cdbl: bytes) -> tuple[bytes, bytes]:
    if not monitor:
        raise ValueError("assembler output is empty")
    if len(monitor) > MONITOR_MAX:
        over = len(monitor) - MONITOR_MAX
        raise ValueError(
            f"monitor is {len(monitor)} bytes and crosses FF00H by {over} byte(s); "
            f"maximum monitor body is {MONITOR_MAX} bytes"
        )

    logical = bytearray([ERASED] * LOGICAL_ROM_SIZE)
    logical[: len(monitor)] = monitor
    logical[MONITOR_MAX:] = cdbl

    device = bytearray([ERASED] * DEVICE_ROM_SIZE)
    device[0x1000:] = logical

    return bytes(logical), bytes(device)


def verify(logical: bytes, device: bytes, cdbl: bytes) -> None:
    assert len(logical) == LOGICAL_ROM_SIZE
    assert len(device) == DEVICE_ROM_SIZE
    assert logical[MONITOR_MAX:] == cdbl
    assert device[:0x1000] == bytes([ERASED]) * 0x1000
    assert device[0x1000:] == logical


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--monitor", type=Path, required=True)
    parser.add_argument("--cdbl", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    monitor = args.monitor.read_bytes()
    cdbl = extract_cdbl(args.cdbl)
    logical, device = build_images(monitor, cdbl)
    verify(logical, device, cdbl)

    if not args.verify_only:
        args.outdir.mkdir(parents=True, exist_ok=True)
        (args.outdir / ROM4K_NAME).write_bytes(logical)
        (args.outdir / ROM8K_NAME).write_bytes(device)

    print("IMSAI target ROM image verification passed")
    print(f"  monitor body : {len(monitor):4d} / {MONITOR_MAX} bytes")
    print(f"  free before CDBL: {MONITOR_MAX - len(monitor):4d} bytes")
    print("  CDBL         : FF00H-FFFFH, 256 bytes")
    print(f"  4K SHA-256   : {sha256(logical)}")
    print(f"  8K SHA-256   : {sha256(device)}")


if __name__ == "__main__":
    main()
