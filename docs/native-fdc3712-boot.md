# Native FDC+3712 ROM boot

This branch replaces the final-ROM CDBL payload with a native FDC+ firmware 1.8 Drive Type 8 / FD3712 boot module at `F800H`.

## Scope

The native module is intentionally specific to Mike Douglas's supplied `CPM22v1.0-FDC+3712-48K.dsk` layout:

- 8-inch IBM-3740 SSSD, 26 x 128-byte sectors per track
- CP/M 2.2 48K system image at `A600H-BF7FH`
- BIOS base `BC00H`
- original 51-sector system checksum `54B0H`

The loader reads the same physical system-sector ordering already proven on the physical IMSAI:

- track 0: sectors `3,5,...25,2,4,...26`
- track 1: sectors `1,3,...25,2,4,...26`

After the exact `54B0H` image is present, only the RAM copy of the BIOS is patched. The system tracks on the floppy are not modified during boot.

## Console integration

The loaded CP/M BIOS console vectors are redirected to the master ROM public console primitives:

- `F003H` blocking console input
- `F006H` console output
- `F009H` console status

Therefore the IMSAI front-panel `SW09/SW08` console selection made by the monitor remains active after floppy boot: Console I/O, Serial I/O A, or IMSAI MIO.

The BIOS default IOBYTE value `95H` is still initialized at page-zero location `0003H` for compatibility, but the current native-ROM version does not yet use IOBYTE to change the patched hardware routing.

## Read/write support

The CP/M BIOS READ and WRITE entries now use native FDC+3712 ROM services.

The write sequence follows Mike Douglas's F400 PROM implementation:

1. select the drive/sector and seek the requested track;
2. move the 128-byte DMA sector into the FD3712 write buffer with command `31H`;
3. issue the `05H` write-sector command;
4. if BIOS MODE bit 6 (`40H`) is enabled, issue `07H` read-CRC and retry failed verification up to ten times.

The ROM additionally treats the FD3712 write-protect status bit (`10H`) as a write error. CP/M receives `A=0` for success and nonzero for failure, matching the BIOS contract.

## Build layout

- `F000H-F7FFH`: existing monitor (currently 1993 bytes, 55 bytes spare before `F800H`)
- `F800H-...`: native FDC+3712 module
- remainder through `FFFFH`: erased/padding

The physical 28C64 programmer image is unchanged in overall arrangement: the lower physical 4K is `FFH`, and the complete logical `F000H-FFFFH` image occupies the upper physical 4K.

For the first hardware-validation branch, `tools/build_image.py` assertion-patches the legacy monitor's assembled `JP FF00H` hook to `JP F800H` and changes the two CDBL display labels to 3712 labels. After bench validation, these three small changes should be folded directly into `src/monitor4k.asm`.

## Bench validation

Native ROM cold boot and `DIR` have already passed on the physical IMSAI with the validated 48K CP/M 2.2 disk.

For the first write validation, use a scratch/duplicate floppy rather than the reference disk:

1. Pull `feature/fdc3712-native-boot` and run `make clean && make verify`.
2. Burn `build/IMSAI_TARGET_MONITOR_28C64.bin` to the target ROM device.
3. Boot the scratch copy with `C` from the monitor.
4. Create a small file with `PIP WTEST.TXT=CON:`; type a short line and terminate input with Ctrl-Z.
5. Run `DIR` and `TYPE WTEST.TXT`.
6. Warm boot with Ctrl-C, then repeat `DIR` and `TYPE WTEST.TXT` to prove the directory and data survived a reload.
7. Power-cycle and repeat the readback for persistence.
8. As a separate safety test, write-protect the scratch disk and confirm a write is rejected rather than silently accepted.

On read/seek failure the ROM prints `FDC+3712 READ/SEEK ERROR` and returns to the monitor. If the 51-sector boot image does not match the validated system, it prints `FDC+3712 SYSTEM IMAGE CHECKSUM ERROR` and returns to the monitor.
