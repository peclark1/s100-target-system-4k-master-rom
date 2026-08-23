# IMSAI 8080 Front Panel ASCII Template

This is the canonical 80-column ASCII-art template of the IMSAI 8080 front panel used by the 4K target monitor startup banner.

The artwork is kept here as the human-readable spacing reference. The ROM build generator mirrors this exact artwork into the generated monitor source so future code changes can preserve the approved layout.

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

## ROM integration

`tools/make_dsi_monitor.py` replaces the compact baseline `MSG_BANNER` with this front-panel artwork when it generates the production monitor source. The normal panel-byte and selected-console status line is printed immediately below the artwork.

Keep this document and the generator copy synchronized if the artwork is adjusted in the future. The generated image must still fit below FF00H because FF00H-FFFFH is reserved for the FDC+ CDBL image.
