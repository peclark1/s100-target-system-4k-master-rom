# IMSAI 8080 Front Panel ASCII Template

This is a preserved 80-column ASCII-art template of the IMSAI 8080 front panel for possible use in a future 4K monitor ROM update.

The artwork is intentionally kept separate from the current ROM source so it can be evaluated for ROM-space cost and incorporated later when another monitor change is being made.

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

## Intended future use

When the monitor ROM is next revised, this template can be converted to ROM string data and displayed as an optional startup/splash screen, subject to available space in the 4K image. The source version should remain here as the canonical spacing reference even if a compact or encoded ROM representation is later added.
