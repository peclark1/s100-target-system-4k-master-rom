# S-100 Target System 4K Master ROM

A compact 4K Z80 monitor ROM for the target IMSAI 8080 configuration.

This project is intentionally target-specific rather than another two-page build of the older MASTER.Z80 monitor. It keeps a fixed 4K ROM window at `F000H-FFFFH`, uses the North Star ZPB-A2 reset/auto-jump path, boots either IDE/CF or 8-inch floppy, and carries only the monitor features useful on this machine.

## Target hardware

- IMSAI 8080 chassis and front panel
- North Star ZPB-A2 Z80A CPU
  - native IMSAI front-panel interface
  - auto-jump/reset target: `F000H`
- Altair FDC+
  - 60K RAM: `0000H-EFFFH`
  - 4K ROM window: `F000H-FFFFH`
  - existing full-64K modification remains installed
  - firmware 1.8, Drive Type 8 / FD3712 for 8-inch IBM-3740 SSSD media
  - 27C64 / 28C64 ROM socket
- S100Computers Dual IDE/CF V3 at `30H-34H`
- S100Computers Console I/O V2 at `00H-01H`
- S100Computers Serial I/O V3, channel A at `A1H/A3H`
- IMSAI MIO at `40H-43H`
  - SIO data: `42H`
  - SIO status/control: `43H`
  - verified at 19,200 baud, 8N1

## Memory and ROM layout

CPU-visible memory:

| Range | Function |
|---|---|
| `0000H-EFFFH` | FDC+ RAM |
| `F000H-FFFFH` | 4K master ROM |

Current logical ROM layout:

| Range | Function |
|---|---|
| `F000H-F7FFH` | compact monitor core |
| `F800H-FB91H` | native FDC+3712 boot/read/write module |
| `FB92H-FB9DH` | stable public FDC+3712 API jump table |
| `FB9EH-FB9FH` | reserved gap |
| `FBA0H-...` | monitor extension (`A/E/S/Z` plus IMSAI header) |
| remaining bytes through `FFFFH` | erased/padding |

At CPU address `F000H`, A12 is high, so the logical 4K ROM occupies the **upper 4K half** of the physical 27C64/28C64. `tools/build_image.py` creates an 8K programmer image with the lower physical 4K filled with `FFH` and the complete logical ROM in the upper 4K.

For the modified FDC+ Rev B target map, the PROM-page switches specify the last RAM page:

- RAM end: `EFFFH`
- PROM start: `F000H`
- PROM page switches `A12..A8`: `0 1 1 1 1` (page `EFH`)
- PROM enable: enabled

## IMSAI front-panel console selection

The IMSAI programmed-input/sense-switch byte is read at **port `FFH`**.

| SW09 | SW08 | Console |
|---:|---:|---|
| 0 | 0 | Console I/O V2 (`00H/01H`) |
| 0 | 1 | Serial I/O V3 Port A (`A1H/A3H`) |
| 1 | 0 | IMSAI MIO SIO (`42H/43H`) |
| 1 | 1 | Reserved; currently falls back to Console I/O |

The ROM exposes stable public console entries:

- `F003H` - blocking console input
- `F006H` - console output
- `F009H` - console status
- `F00CH` - warm monitor entry

The native floppy CP/M BIOS uses those same entries, so the front-panel console choice remains active after floppy boot.

## Public FDC+3712 ROM API

The physically-proven 914-byte native FDC+3712 module at `F800H-FB91H` is kept unchanged. The build now uses 12 bytes of the former reserved gap as a fixed ABI for other resident software, including the target CP/M 3 BIOS:

| Address | Entry | Contract |
|---|---|---|
| `FB92H` | INIT | initialize/reset/restore the native FDC+3712 path |
| `FB95H` | SELDRV | select physical drive in register `C` (`0` or `1`) |
| `FB98H` | READ | read one 128-byte sector using the native ROM workspace |
| `FB9BH` | WRITE | write one 128-byte sector using the native ROM workspace |

The API is generated from `fdc3712rom.sym`, so each vector is an absolute `JP` to the corresponding symbol in the proven module. This avoids maintaining a second copy of the low-level FD3712 driver in CP/M 3 while keeping the public entry addresses fixed if internal code addresses change.

The native service routines retain the original Mike-Douglas-compatible page-zero workspace at `0040H-0047H`. External callers that cannot reserve those bytes must save/restore them around API calls. The CP/M 3 adapter does exactly that and keeps its own persistent copy of the ROM driver's state.

## Monitor commands

- `A` - memory map, one character per 256-byte page (`R` RAM, `P` ROM/non-writable, `.` empty/FF)
- `B` - boot menu
- `C` - native Altair FDC+3712 floppy boot
- `D` - display memory as 16-byte hex rows with printable ASCII at the right
- `E` - console echo test; Ctrl-C or Ctrl-Z exits
- `F` - fill memory
- `G` - go to address
- `H` - hardware / front-panel status
- `J` - non-destructive RAM test
- `K` - command menu
- `M` - move memory
- `P` - boot CP/M from IDE/CF
- `Q` - single-port I/O read/write diagnostic
- `S` - interactive examine/substitute memory
- `V` - verify/compare memory
- `Z` - find highest writable RAM

`T=Type` was removed because `D` again includes the ASCII column.

Hex command parameters accept either a **space** or **comma** separator, and the typed delimiter is echoed. Examples:

```text
D F000,F07F
D F000 F07F
F 1000,10FF,00
M 1000 10FF 2000
Q I,43
Q O,43,00
S 1000
```

For `S`, each line shows the address and current byte. Enter a hex byte followed by space/comma/CR to replace it and advance; a bare delimiter advances without changing memory; `-` backs up one byte; ESC/Ctrl-C/Ctrl-Z exits.

## Native FDC+3712 floppy boot

The old CDBL payload has been removed. `C` now jumps to a ROM-native FD3712 module at `F800H` derived from Mike Douglas's FDC+3712 PROM programming model and validated on the physical IMSAI.

The loader is intentionally specific to the supplied 48K CP/M 2.2 system layout:

- IBM-3740 SSSD, 26 x 128-byte sectors
- CP/M system loaded at `A600H-BF7FH`
- BIOS base `BC00H`
- original 51-sector checksum `54B0H`

The loaded BIOS is patched in RAM to use the resident ROM disk services and master-ROM console primitives. Both floppy reads and writes are enabled. Write support uses the FD3712 write-buffer/write-sector sequence with optional CRC verification and explicit write-protect detection.

Physical validation includes:

- native cold boot to the CP/M `A>` prompt;
- directory reads;
- file creation/write/readback on drive A;
- a Digital Systems single-density disk in physical drive B;
- successful file copy from B: to A:, exercising drive selection, reads, allocation, directory updates, and writes end-to-end.

## Startup

On reset the monitor:

1. enters at `F000H` through the North Star auto-jump feature;
2. reads the IMSAI front-panel byte at `FFH`;
3. selects and initializes the requested console;
4. displays the aligned IMSAI 8080 front-panel header and target-system status;
5. initializes the Dual IDE/CF interface;
6. performs a short cancelable IDE/CF auto-boot countdown;
7. enters the monitor if a key is pressed.

## Building on Ubuntu

Install Pasmo once:

```sh
sudo apt update
sudo apt install pasmo
```

Then build and verify:

```sh
make clean
make verify
```

A successful build creates:

- `build/IMSAI_TARGET_MONITOR_4K.bin` - exactly 4096 bytes, logical `F000H-FFFFH`
- `build/IMSAI_TARGET_MONITOR_28C64.bin` - exactly 8192 bytes, ready for the FDC+ 27C64/28C64 socket
- `build/monitor.raw.bin` / `monitor.sym` - compact monitor core
- `build/fdc3712rom.bin` / `fdc3712rom.sym` - unchanged native floppy module
- `build/fdc3712api.bin` - four generated public FDC jump vectors at `FB92H-FB9DH`
- `build/monext.bin` / `monext.sym` - monitor extension

The build enforces all ROM boundaries and fails if the monitor crosses `F800H`, the proven FDC module crosses the API boundary at `FB92H`, the API crosses `FBA0H`, or the extension crosses `FFFFH`.

## Deliberately excluded

The target ROM still does not carry hardware-specific features that are not needed on this IMSAI, including RTC/time/date support, printer/speech support, Serial I/O channel B, IA-2 extended-memory window commands, scan-all-256-I/O-port diagnostics, auxiliary-processor support, Versafloppy/ZFDC support, or the old two-page ROM-banking framework.

XMODEM remains omitted for now because modern host-link/file-transfer tools make it much less valuable than the monitor, disk, and diagnostic features that fit in the 4K ROM.

## Development approach

GitHub is the source of truth. Development proceeds in small, reviewable commits with reproducible Ubuntu builds. Hardware-test candidates remain on branches/PRs until they pass the physical IMSAI bench test.
