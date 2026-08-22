#!/usr/bin/env python3
"""Build and verify IMSAI target-system ROM images.

The monitor is assembled at F000H and the native FDC+3712 boot module is
assembled separately at F800H.  This script combines the two into the logical
4K ROM image and emits the physical 8K 27C64/28C64 programmer image used by the
modified Altair FDC+.

The current monitor source still contains the former CDBL jump hook and two
human-readable CDBL labels.  For this first hardware-validation branch, the
builder changes only those exact bytes in the assembled monitor image:

  JP FF00H              -> JP F800H
  "WITH CDBL"           -> "WITH 3712"
  "CDBL FF00H"          -> "3712 F800H"

Each replacement is assertion-checked and must occur exactly once.  Once the
native boot path is bench-proven, these small source-level cleanups can be
folded directly into monitor4k.asm without changing the binary design.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

ROM_BASE = 0xF000
FDC_ADDR = 0xF800
FDC_OFFSET = FDC_ADDR - ROM_BASE
LOGICAL_ROM_SIZE = 0x1000
DEVICE_ROM_SIZE = 0x2000
ERASED = 0xFF

ROM4K_NAME = "IMSAI_TARGET_MONITOR_4K.bin"
ROM8K_NAME = "IMSAI_TARGET_MONITOR_28C64.bin"


def replace_once(data: bytes, old: bytes, new: bytes, description: str) -> bytes:
    if len(old) != len(new):
        raise ValueError(f"{description}: replacement length mismatch")
    count = data.count(old)
    if count != 1:
        raise ValueError(f"{description}: expected exactly one match, found {count}")
    return data.replace(old, new, 1)


def patch_monitor(monitor: bytes) -> bytes:
    if not monitor:
        raise ValueError("assembler monitor output is empty")
    if len(monitor) > FDC_OFFSET:
        raise ValueError(
            f"monitor is {len(monitor)} bytes and crosses native FDC module "
            f"address {FDC_ADDR:04X}H; maximum is {FDC_OFFSET} bytes"
        )

    patched = monitor
    patched = replace_once(
        patched,
        bytes((0xC3, 0x00, 0xFF)),
        bytes((0xC3, 0x00, 0xF8)),
        "legacy CDBL boot jump",
    )
    patched = replace_once(patched, b"WITH CDBL", b"WITH 3712", "FDC boot banner")
    patched = replace_once(patched, b"CDBL FF00H", b"3712 F800H", "hardware banner")
    return patched


def build_images(monitor: bytes, fdc_module: bytes) -> tuple[bytes, bytes]:
    monitor = patch_monitor(monitor)

    if not fdc_module:
        raise ValueError("FDC+3712 module is empty")
    if len(fdc_module) > LOGICAL_ROM_SIZE - FDC_OFFSET:
        raise ValueError(
            f"FDC+3712 module is {len(fdc_module)} bytes; maximum at F800H is "
            f"{LOGICAL_ROM_SIZE - FDC_OFFSET} bytes"
        )

    logical = bytearray([ERASED] * LOGICAL_ROM_SIZE)
    logical[: len(monitor)] = monitor
    logical[FDC_OFFSET : FDC_OFFSET + len(fdc_module)] = fdc_module

    device = bytearray([ERASED] * DEVICE_ROM_SIZE)
    device[0x1000:] = logical

    return bytes(logical), bytes(device)


def verify(logical: bytes, device: bytes, monitor: bytes, fdc_module: bytes) -> None:
    assert len(logical) == LOGICAL_ROM_SIZE
    assert len(device) == DEVICE_ROM_SIZE
    assert device[:0x1000] == bytes([ERASED]) * 0x1000
    assert device[0x1000:] == logical

    patched_monitor = patch_monitor(monitor)
    assert logical[: len(patched_monitor)] == patched_monitor
    assert logical[FDC_OFFSET : FDC_OFFSET + len(fdc_module)] == fdc_module

    # Public cold entry remains at F000H and the native hook is a JP F800H.
    assert logical[0] == 0xC3
    assert bytes((0xC3, 0x00, 0xF8)) in logical[:FDC_OFFSET]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--monitor", type=Path, required=True)
    parser.add_argument("--fdc", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    monitor = args.monitor.read_bytes()
    fdc_module = args.fdc.read_bytes()
    logical, device = build_images(monitor, fdc_module)
    verify(logical, device, monitor, fdc_module)

    if not args.verify_only:
        args.outdir.mkdir(parents=True, exist_ok=True)
        (args.outdir / ROM4K_NAME).write_bytes(logical)
        (args.outdir / ROM8K_NAME).write_bytes(device)

    print("IMSAI target ROM image verification passed")
    print(f"  monitor body : {len(monitor):4d} / {FDC_OFFSET} bytes before F800H")
    print(f"  gap to F800H : {FDC_OFFSET - len(monitor):4d} bytes")
    print(
        f"  FDC+3712     : {FDC_ADDR:04X}H-"
        f"{FDC_ADDR + len(fdc_module) - 1:04X}H, {len(fdc_module)} bytes"
    )
    print(f"  free at top  : {LOGICAL_ROM_SIZE - FDC_OFFSET - len(fdc_module):4d} bytes")
    print(f"  4K SHA-256   : {sha256(logical)}")
    print(f"  8K SHA-256   : {sha256(device)}")


if __name__ == "__main__":
    main()
