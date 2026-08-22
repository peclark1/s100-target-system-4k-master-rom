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

The CP/M BIOS READ and WRITE entries use native FDC+3712 ROM services.

The write sequence follows Mike Douglas's F400 PROM implementation:

1. select the drive/sector and seek the requested track;
2. move the 128-byte DMA sector into the FD3712 write buffer with command `31H`;
3. issue the `05H` write-sector command;
4. if BIOS MODE bit 6 (`40H`) is enabled, issue `07H` read-CRC and retry failed verification up to ten times.

The ROM additionally treats the FD3712 write-protect status bit (`10H`) as a write error. CP/M receives `A=0` for success and nonzero for failure, matching the BIOS contract.

## Build layout

- `F000H-F7FFH`: monitor body
- `F800H-...`: native FDC+3712 module
- remainder through `FFFFH`: erased/padding

The physical 28C64 programmer image is unchanged in overall arrangement: the lower physical 4K is `FFH`, and the complete logical `F000H-FFFFH` image occupies the upper physical 4K.

The native boot hook is source-level code in `src/monitor4k.asm`: `FDC_BOOT` jumps directly to `F800H`, and the monitor strings identify the 3712 module directly. `tools/build_image.py` no longer patches the assembled monitor binary; it only verifies the layout and combines the monitor and FDC+3712 module.

The cleaned source build is byte-for-byte identical to the physically tested pre-cleanup ROM image:

- 4K SHA-256: `532ba8a7c68d0087746cb6cb5848fc30875d4c737ee089cb264527f8135cac7e`
- 8K SHA-256: `3665eec485fe167ba67173a097efaebdad1f51ba6f59e9b2724c5fc1357c1099`

## Physical bench validation

The native ROM path, including writes, has now been validated on the physical IMSAI with the FDC+ firmware 1.8 Drive Type 8 configuration and SA800-class drives.

Verified behavior:

- native ROM cold boot reaches 48K CP/M 2.2 and the `A>` prompt;
- `DIR` succeeds from the boot disk;
- CP/M file creation and writeback on drive A succeed;
- the written file can be read back correctly;
- a Digital Systems single-density CP/M disk placed in physical drive B is readable through the same FDC+3712 BIOS path;
- CP/M successfully copied a file from B: to A:, simultaneously exercising drive-B selection/read and drive-A allocation/directory/data writes.

This cross-drive copy is strong end-to-end validation of the drive-select, seek, read, write-buffer, write-sector, directory-update, and CP/M BIOS integration paths. It also confirms useful media compatibility with the archived Digital Systems single-density disk format used in this IMSAI project.

A write-protect rejection test is still recommended as a final error-path check.

For the final post-cleanup smoke test, pull the branch, run `make clean && make verify`, confirm the two hashes above, burn `build/IMSAI_TARGET_MONITOR_28C64.bin`, boot with `C`, run `DIR`, and perform one small read/write operation. Because the hashes are unchanged, this is a regression smoke test of the source cleanup rather than a new ROM design.

On read/seek failure the ROM prints `FDC+3712 READ/SEEK ERROR` and returns to the monitor. If the 51-sector boot image does not match the validated system, it prints `FDC+3712 SYSTEM IMAGE CHECKSUM ERROR` and returns to the monitor.
