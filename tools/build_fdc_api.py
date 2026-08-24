#!/usr/bin/env python3
"""Build the fixed FDC+3712 public jump table from Pasmo symbols.

The physically-tested FDC module remains byte-for-byte unchanged.  This helper
reads its symbol file and emits four three-byte Z80 JP vectors that occupy the
reserved ROM gap at FB92H-FB9DH.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

API_BASE = 0xFB92
ROM_LO = 0xF800
ROM_HI = API_BASE

VECTORS = (
    ("INIT_ALL", "INIT"),
    ("SELDRV", "SELDRV"),
    ("READ", "READ"),
    ("WRITE", "WRITE"),
)


def parse_symbols(path: Path) -> dict[str, int]:
    text = path.read_text(errors="replace")
    symbols: dict[str, int] = {}

    # Pasmo normally emits lines such as "READ EQU 0F9A3H".  Accept a few
    # harmless formatting variants so the build is not tied to whitespace.
    patterns = (
        re.compile(r"^\s*([A-Za-z_.$?][\w.$?]*)\s+EQU\s+([0-9A-Fa-f]+)H\b", re.I),
        re.compile(r"^\s*([A-Za-z_.$?][\w.$?]*)\s*=\s*\$?([0-9A-Fa-f]+)H?\b", re.I),
        re.compile(r"^\s*([A-Za-z_.$?][\w.$?]*)\s+\$?([0-9A-Fa-f]{4,5})H?\s*$", re.I),
    )

    for line in text.splitlines():
        for pat in patterns:
            m = pat.match(line)
            if m:
                symbols[m.group(1).upper()] = int(m.group(2), 16)
                break

    return symbols


def build_api(symbols: dict[str, int]) -> bytes:
    out = bytearray()
    for symbol, _label in VECTORS:
        try:
            address = symbols[symbol]
        except KeyError as exc:
            raise ValueError(f"required Pasmo symbol {symbol!r} was not found") from exc
        if not (ROM_LO <= address < ROM_HI):
            raise ValueError(
                f"{symbol} resolved to {address:04X}H, outside native FDC module "
                f"{ROM_LO:04X}H-{ROM_HI - 1:04X}H"
            )
        out.extend((0xC3, address & 0xFF, address >> 8))
    return bytes(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--symbols", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    symbols = parse_symbols(args.symbols)
    api = build_api(symbols)
    if len(api) != 12:
        raise AssertionError("FDC API must be exactly four JP vectors / 12 bytes")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(api)

    print("FDC+3712 public ROM API")
    for index, (symbol, label) in enumerate(VECTORS):
        vector = API_BASE + index * 3
        target = symbols[symbol]
        print(f"  {vector:04X}H  {label:<6} -> {target:04X}H ({symbol})")


if __name__ == "__main__":
    main()
