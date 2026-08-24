#!/usr/bin/env python3
"""Build and verify IMSAI target-system ROM images.

The compact monitor is assembled at F000H, the physically-proven native
FDC+3712 module at F800H, a generated public FDC ABI at FB92H, and the monitor
extension at FBA0H.  This script combines them into the logical 4K ROM image
and emits the physical 8K 27C64/28C64 programmer image used by the modified
Altair FDC+.

All hooks remain source/build generated; no opaque assembled-binary patching
is performed.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

ROM_BASE = 0xF000
FDC_ADDR = 0xF800
FDC_API_ADDR = 0xFB92
EXT_ADDR = 0xFBA0
FDC_OFFSET = FDC_ADDR - ROM_BASE
FDC_API_OFFSET = FDC_API_ADDR - ROM_BASE
EXT_OFFSET = EXT_ADDR - ROM_BASE
LOGICAL_ROM_SIZE = 0x1000
DEVICE_ROM_SIZE = 0x2000
ERASED = 0xFF
FDC_API_SIZE = 12

ROM4K_NAME = "IMSAI_TARGET_MONITOR_4K.bin"
ROM8K_NAME = "IMSAI_TARGET_MONITOR_28C64.bin"


def build_images(
    monitor: bytes, fdc_module: bytes, fdc_api: bytes, ext_module: bytes
) -> tuple[bytes, bytes]:
    if not monitor:
        raise ValueError("assembler monitor output is empty")
    if len(monitor) > FDC_OFFSET:
        raise ValueError(
            f"monitor is {len(monitor)} bytes and crosses native FDC module "
            f"address {FDC_ADDR:04X}H; maximum is {FDC_OFFSET} bytes"
        )

    if not fdc_module:
        raise ValueError("FDC+3712 module is empty")
    if len(fdc_module) > FDC_API_OFFSET - FDC_OFFSET:
        raise ValueError(
            f"FDC+3712 module is {len(fdc_module)} bytes and crosses public "
            f"API address {FDC_API_ADDR:04X}H; maximum is "
            f"{FDC_API_OFFSET - FDC_OFFSET} bytes"
        )

    if len(fdc_api) != FDC_API_SIZE:
        raise ValueError(
            f"FDC+3712 API is {len(fdc_api)} bytes; expected exactly "
            f"{FDC_API_SIZE} bytes (four JP vectors)"
        )
    if FDC_API_OFFSET + len(fdc_api) > EXT_OFFSET:
        raise ValueError("FDC+3712 API overlaps monitor extension")

    if not ext_module:
        raise ValueError("monitor extension is empty")
    if len(ext_module) > LOGICAL_ROM_SIZE - EXT_OFFSET:
        raise ValueError(
            f"monitor extension is {len(ext_module)} bytes; maximum at "
            f"{EXT_ADDR:04X}H is {LOGICAL_ROM_SIZE - EXT_OFFSET} bytes"
        )

    logical = bytearray([ERASED] * LOGICAL_ROM_SIZE)
    logical[: len(monitor)] = monitor
    logical[FDC_OFFSET : FDC_OFFSET + len(fdc_module)] = fdc_module
    logical[FDC_API_OFFSET : FDC_API_OFFSET + len(fdc_api)] = fdc_api
    logical[EXT_OFFSET : EXT_OFFSET + len(ext_module)] = ext_module

    device = bytearray([ERASED] * DEVICE_ROM_SIZE)
    device[0x1000:] = logical

    return bytes(logical), bytes(device)


def verify(
    logical: bytes,
    device: bytes,
    monitor: bytes,
    fdc_module: bytes,
    fdc_api: bytes,
    ext_module: bytes,
) -> None:
    assert len(logical) == LOGICAL_ROM_SIZE
    assert len(device) == DEVICE_ROM_SIZE
    assert device[:0x1000] == bytes([ERASED]) * 0x1000
    assert device[0x1000:] == logical

    assert logical[: len(monitor)] == monitor
    assert logical[FDC_OFFSET : FDC_OFFSET + len(fdc_module)] == fdc_module
    assert logical[FDC_API_OFFSET : FDC_API_OFFSET + len(fdc_api)] == fdc_api
    assert logical[EXT_OFFSET : EXT_OFFSET + len(ext_module)] == ext_module

    # Public cold entry remains at F000H; source-level hooks target the native
    # FDC module at F800H and extension dispatcher/header at FBA0H/FBA3H.
    assert logical[0] == 0xC3
    assert bytes((0xC3, 0x00, 0xF8)) in monitor
    assert bytes((0xC3, 0xA0, 0xFB)) in monitor
    assert bytes((0xCD, 0xA3, 0xFB)) in monitor

    # Stable external FDC ABI: four absolute JP vectors at FB92/95/98/9B.
    assert len(fdc_api) == FDC_API_SIZE
    assert all(fdc_api[i] == 0xC3 for i in (0, 3, 6, 9))


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--monitor", type=Path, required=True)
    parser.add_argument("--fdc", type=Path, required=True)
    parser.add_argument("--fdc-api", type=Path, required=True)
    parser.add_argument("--ext", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    monitor = args.monitor.read_bytes()
    fdc_module = args.fdc.read_bytes()
    fdc_api = args.fdc_api.read_bytes()
    ext_module = args.ext.read_bytes()
    logical, device = build_images(monitor, fdc_module, fdc_api, ext_module)
    verify(logical, device, monitor, fdc_module, fdc_api, ext_module)

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
    print(f"  gap to API   : {FDC_API_OFFSET - FDC_OFFSET - len(fdc_module):4d} bytes")
    print(
        f"  FDC public API: {FDC_API_ADDR:04X}H-"
        f"{FDC_API_ADDR + len(fdc_api) - 1:04X}H, {len(fdc_api)} bytes"
    )
    print(f"  gap to ext   : {EXT_OFFSET - FDC_API_OFFSET - len(fdc_api):4d} bytes")
    print(
        f"  monitor ext  : {EXT_ADDR:04X}H-"
        f"{EXT_ADDR + len(ext_module) - 1:04X}H, {len(ext_module)} bytes"
    )
    print(f"  free at top  : {LOGICAL_ROM_SIZE - EXT_OFFSET - len(ext_module):4d} bytes")
    print(f"  4K SHA-256   : {sha256(logical)}")
    print(f"  8K SHA-256   : {sha256(device)}")


if __name__ == "__main__":
    main()
