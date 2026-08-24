# IMSAI 8080 Front Panel ASCII Template

This is the canonical 80-column ASCII-art template used by the target 4K monitor startup banner.

The monitor extension stores a compact encoded copy because the literal artwork would consume too much of the remaining ROM. `src/monext.asm` expands the packed data at startup and reproduces these eleven lines exactly.

**Formatting requirements:**

- Keep the artwork in a monospaced font.
- Every artwork line is exactly 80 characters wide, including the left and right borders.
- Preserve spacing carefully; the three lamp rows and right-hand control group are positioned to resemble the physical IMSAI front panel.
- `ADDRESS + DATA` is centered over the middle bank of eight switches.

```text
+------------------------------------------------------------------------------+
| o  o  o  o  o  o  o  o  PROGRAMMED                        I M S A I   8 0 8 0|
| 7  6  5  4  3  2  1  0  OUTPUT                           --------------------|
| MR IN M1 OT HL ST WO IA          7  6  5  4  3  2  1  0                      |
| o  o  o  o  o  o  o  o  STATUS   o  o  o  o  o  o  o  o  DATA                |
|                         BYTE                             BUS                 |
| 15 14 13 12 11 10 9  8  ADDRESS  7  6  5  4  3  2  1  0 ENABLED RUN WAIT HOLD|
| o  o  o  o  o  o  o  o  BUS      o  o  o  o  o  o  o  o      o    o    o    o|
| ADDRESS + PROGRAM INPUT          ADDRESS + DATA      EXA DEP RST RUN STP PWR |
| [_][_][_][_][_][_][_][_]    [_][_][_][_][_][_][_][_]  [_] [_] [_] [_] [_] [_]|
+------------------------------------------------------------------------------+
```

## ROM encoding

The startup code uses a small target-specific stream format:

- `00H`: end of artwork
- `01H-1EH`: emit that many spaces
- `1FH`: emit CR/LF
- `20H-7EH`: emit the byte literally
- `80H-FFH`: emit `-` `(token AND 7FH)` times

This compression is intentionally simple enough for a very small Z80 decoder while saving enough space to keep the full 80-column banner in the 4K ROM alongside the native FDC+3712 driver, its public API, and the monitor extension commands.
