#!/usr/bin/env python3
"""Generate the DSI-enabled monitor source from the hardware-tested v0.1 source.

This branch deliberately leaves src/monitor4k.asm untouched as the validated
baseline.  The generator performs a small set of exact, reviewable textual
edits and inserts src/dsi_boot.inc before AUTO_BOOT.  If the baseline changes
and an expected anchor no longer matches exactly, generation fails rather than
silently producing an unintended monitor.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"error: expected exactly one {label} anchor, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--dsi", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    text = args.base.read_text(encoding="ascii")
    dsi = args.dsi.read_text(encoding="ascii").rstrip() + "\n\n"

    text = replace_once(
        text,
        ";   IMSAI MIO SIO at 42H/43H\n",
        ";   IMSAI MIO SIO at 42H/43H\n"
        ";   Digital Systems HB-1.3 + FDC-2 at 7DH-7FH\n",
        "hardware-list",
    )

    text = replace_once(
        text,
        "        CP      'F'\n"
        "        JP      Z,FDC_BOOT\n"
        "        CP      'M'\n",
        "        CP      'F'\n"
        "        JP      Z,FDC_BOOT\n"
        "        CP      'D'\n"
        "        JP      Z,DSI_BOOT\n"
        "        CP      'M'\n",
        "boot-menu dispatch",
    )

    text = replace_once(
        text,
        "FDC_BOOT:\n"
        "        CALL    PRINT_CRLF\n"
        "        LD      HL,MSG_FDC_BOOT\n"
        "        CALL    PRINT_STR\n"
        "        JP      0FF00H                  ; exact published CDBL 2.05\n\n"
        "AUTO_BOOT:\n",
        "FDC_BOOT:\n"
        "        CALL    PRINT_CRLF\n"
        "        LD      HL,MSG_FDC_BOOT\n"
        "        CALL    PRINT_STR\n"
        "        JP      0FF00H                  ; exact published CDBL 2.05\n\n"
        + dsi
        + "AUTO_BOOT:\n",
        "DSI insertion",
    )

    text = replace_once(
        text,
        "        DB      'BOOT: [I] IDE/CF  [F] ALTAIR FDC+  [M] MONITOR : ',0\n",
        "        DB      'BOOT: [I] IDE/CF  [F] ALTAIR FDC+  [D] DSI FDC-2  [M] MONITOR : ',0\n",
        "boot-menu text",
    )

    text = replace_once(
        text,
        "        DB      'IDE/CF 30H-34H  FDC+ 08H-0AH  CDBL FF00H',CR,LF,0\n",
        "        DB      'IDE/CF 30H-34H  FDC+ 08H-0AH  DSI 7DH-7FH',CR,LF\n"
        "        DB      'CDBL FF00H',CR,LF,0\n",
        "hardware text",
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text, encoding="ascii")
    print(f"generated {args.output} with Digital Systems FDC-2 boot support")


if __name__ == "__main__":
    main()
