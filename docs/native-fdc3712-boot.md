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

## Stable public FDC API

The physically-tested 914-byte FDC implementation remains unchanged at `F800H-FB91H`. Rather than duplicate that controller code in the target CP/M 3 BIOS, 12 bytes of the former reserved gap now form a fixed jump-table ABI:

| Address | Entry | Contract |
|---|---|---|
| `FB92H` | INIT | initialize/reset/restore the native FDC+3712 path |
| `FB95H` | SELDRV | select physical drive in register `C` (`0` or `1`) |
| `FB98H` | READ | read one 128-byte sector |
| `FB9BH` | WRITE | write one 128-byte sector |

`tools/build_fdc_api.py` reads the Pasmo symbols from the unchanged native module and emits four absolute Z80 `JP` vectors. Thus the public addresses stay fixed even if an internal service label moves in a future source revision.

The service routines retain their original page-zero workspace:

- `0040H` drive number
- `0041H` track
- `0042H` physical sector number, `1..26`
- `0043H-0044H` DMA address
- `0045H` cached drive track
- `0046H-0047H` BIOS address used by optional write verification

External software that does not reserve those bytes must preserve them. The CP/M 3 adapter saves `0040H-0047H`, installs a private persistent copy of the ROM-driver state for the duration of the call, then restores CP/M page zero.

## Final 4K layout

The CDBL reservation is gone. The logical ROM is now composed as:

- `F000H-F7FFH`: compact monitor core
- `F800H-FB91H`: unchanged native FDC+3712 module
- `FB92H-FB9DH`: generated public FDC+3712 API jump table
- `FB9EH-FB9FH`: reserved gap
- `FBA0H-FF2EH`: monitor extension
- `FF2FH-FFFFH`: erased/padding

The monitor extension restores the aligned IMSAI 8080 front-panel sign-on graphic and adds the `A`, `E`, `S`, and `Z` commands. The core dispatches those commands through fixed entry `FBA0H` and calls the extension header through `FBA3H`.

The `A` memory-map command uses John's RAM/PROM/empty-page idea but is made safer for this EEPROM-based target: it never performs a write probe in the fixed `F000H-FFFFH` ROM window. Below `F000H` it uses a nondestructive complement/restore RAM test; non-writable pages are scanned for non-`FFH` data.

The physical 28C64 programmer image remains unchanged in overall arrangement: the lower physical 4K is `FFH`, and the complete logical `F000H-FFFFH` image occupies the upper physical 4K.

The previously bench-tested ROM before the API vectors were added had:

- monitor core: 2018 bytes, 30 bytes free before `F800H`
- FDC+3712 implementation: 914 bytes, ending at `FB91H`
- monitor extension: 911 bytes, ending at `FF2EH`
- 4K SHA-256: `86dce57d8cb7e37162b555c8ca1e04eca7bd031daddc8c854b9ca3e53657e6c0`
- 8K SHA-256: `2bf008fb3a95ccc2824e0bdd27749d8abe2f5c6beb93bd912bb4c3332e6cf37b`

The new API build intentionally changes only bytes `FB92H-FB9DH` from erased `FFH` to jump vectors. New image hashes are produced by CI and should be recorded after the API-enabled ROM is physically smoke-tested.

## Physical bench validation to date

The native ROM path, including writes, has been validated on the physical IMSAI with the FDC+ firmware 1.8 Drive Type 8 configuration and SA800-class drives.

Verified behavior of the underlying native module:

- native ROM cold boot reaches 48K CP/M 2.2 and the `A>` prompt;
- `DIR` succeeds from the boot disk;
- CP/M file creation and writeback on drive A succeed;
- the written file can be read back correctly;
- a Digital Systems single-density CP/M disk placed in physical drive B is readable through the same FDC+3712 BIOS path;
- CP/M successfully copied a file from B: to A:, simultaneously exercising drive-B selection/read and drive-A allocation/directory/data writes;
- final monitor header, `D` display, delimiter handling, `A/E/S/Z`, and native FDC boot were smoke-tested successfully before the API addition.

Because the API generation leaves `fdc3712rom.bin` byte-for-byte unchanged, the only new hardware validation required is a smoke test of the new ROM image plus the CP/M 3 consumer of the API.

A write-protect rejection test remains a useful optional FDC error-path check.

On read/seek failure the native boot path prints `FDC+3712 READ/SEEK ERROR` and returns to the monitor. If the 51-sector boot image does not match the validated system, it prints `FDC+3712 SYSTEM IMAGE CHECKSUM ERROR` and returns to the monitor.
