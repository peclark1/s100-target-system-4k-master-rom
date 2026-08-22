# Native FDC+3712 ROM boot

This branch replaces the final-ROM CDBL payload with a native FDC+ firmware 1.8 Drive Type 8 / FD3712 boot module at `F800H`.

## Scope of the first milestone

The native module is intentionally specific to Mike Douglas's supplied `CPM22v1.0-FDC+3712-48K.dsk` layout:

- 8-inch IBM-3740 SSSD, 26 x 128-byte sectors per track
- CP/M 2.2 48K system image at `A600H-BF7FH`
- BIOS base `BC00H`
- original 51-sector system checksum `54B0H`

The loader reads the same physical system-sector ordering already proven on the physical IMSAI:

- track 0: sectors `3,5,...25,2,4,...26`
- track 1: sectors `1,3,...25,2,4,...26`

After the exact `54B0H` image is present, only the RAM copy of the BIOS is patched. The floppy is never modified.

## Console integration

The loaded CP/M BIOS console vectors are redirected to the master ROM public console primitives:

- `F003H` blocking console input
- `F006H` console output
- `F009H` console status

Therefore the IMSAI front-panel `SW09/SW08` console selection made by the monitor remains active after floppy boot: Console I/O, Serial I/O A, or IMSAI MIO.

The BIOS default IOBYTE value `95H` is still initialized at page-zero location `0003H` for compatibility, but the first native-ROM version does not yet use IOBYTE to change the patched hardware routing.

## Disk safety

The first native-ROM milestone is read-only. The CP/M BIOS WRITE entry returns error and the ROM contains no FDC+ write command in this path.

## Build layout

- `F000H-F7FFH`: existing monitor (currently 1993 bytes, 55 bytes spare before `F800H`)
- `F800H-...`: native FDC+3712 module
- remainder through `FFFFH`: erased/padding

The physical 28C64 programmer image is unchanged in overall arrangement: the lower physical 4K is `FFH`, and the complete logical `F000H-FFFFH` image occupies the upper physical 4K.

For the first hardware-validation branch, `tools/build_image.py` assertion-patches the legacy monitor's assembled `JP FF00H` hook to `JP F800H` and changes the two CDBL display labels to 3712 labels. After bench validation, these three small changes should be folded directly into `src/monitor4k.asm`.

## First bench test

1. Use the already validated Mike Douglas 48K CP/M 2.2 disk in FDC+ drive 0.
2. Pull `feature/fdc3712-native-boot` and run `make clean && make verify`.
3. Burn `build/IMSAI_TARGET_MONITOR_28C64.bin` to the target ROM device.
4. Reset/Run the IMSAI and cancel the normal IDE/CF auto-boot.
5. Press `C`, or choose `F` from the boot menu.
6. Expected result is the ROM-native CP/M banner followed by the CP/M `A>` prompt.
7. First operation should be `DIR` only; writes are deliberately disabled.

On read/seek failure the ROM prints `FDC+3712 READ/SEEK ERROR` and returns to the monitor. If the 51-sector image does not match the validated system, it prints `FDC+3712 SYSTEM IMAGE CHECKSUM ERROR` and returns to the monitor.
