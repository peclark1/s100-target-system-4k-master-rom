#!/usr/bin/env python3
"""Generate the DSI-enabled monitor source from the hardware-tested v0.1 source.

The generator deliberately leaves src/monitor4k.asm untouched as the validated
baseline. It performs a small set of exact, reviewable textual edits, inserts
src/dsi_boot.inc before AUTO_BOOT, and replaces the compact startup banner with
the canonical IMSAI front-panel ASCII artwork preserved in docs/. If the
baseline changes and an expected anchor no longer matches exactly, generation
fails rather than silently producing an unintended monitor.
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

    front_panel_banner = (
        "MSG_BANNER:\n"
        "        DB      '+------------------------------------------------------------------------------+',CR,LF\n"
        "        DB      '| o  o  o  o  o  o  o  o  PROGRAMMED                        I M S A I   8 0 8 0|',CR,LF\n"
        "        DB      '| 7  6  5  4  3  2  1  0  OUTPUT                           --------------------|',CR,LF\n"
        "        DB      '| MR IN M1 OT HL ST WO IA          7  6  5  4  3  2  1  0                      |',CR,LF\n"
        "        DB      '| o  o  o  o  o  o  o  o  STATUS   o  o  o  o  o  o  o  o  DATA                |',CR,LF\n"
        "        DB      '|                         BYTE                             BUS                 |',CR,LF\n"
        "        DB      '| 15 14 13 12 11 10 9  8  ADDRESS  7  6  5  4  3  2  1  0 ENABLED RUN WAIT HOLD|',CR,LF\n"
        "        DB      '| o  o  o  o  o  o  o  o  BUS      o  o  o  o  o  o  o  o      o    o    o    o|',CR,LF\n"
        "        DB      '| ADDRESS + PROGRAM INPUT          ADDRESS + DATA      EXA DEP RST RUN STP PWR |',CR,LF\n"
        "        DB      '| [_][_][_][_][_][_][_][_]    [_][_][_][_][_][_][_][_]  [_] [_] [_] [_] [_] [_]|',CR,LF\n"
        "        DB      '+------------------------------------------------------------------------------+',CR,LF,0\n"
    )

    text = replace_once(
        text,
        "MSG_BANNER:\n"
        "        DB      'IMSAI 8080 TARGET MONITOR 4K @ F000H',CR,LF,0\n",
        front_panel_banner,
        "startup banner",
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text, encoding="ascii")
    print(
        f"generated {args.output} with Digital Systems FDC-2 boot support "
        "and IMSAI front-panel banner"
    )


if __name__ == "__main__":
    main()
