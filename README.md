# S-100 Target System 4K Master ROM

A clean 4K Z80 monitor ROM for the target IMSAI 8080 configuration.

This project is intentionally **not** another trimmed build of the older two-page MASTER.Z80 monitor. It is a new, small monitor designed around the final target hardware and a fixed 4K ROM window.

## Target hardware

- IMSAI 8080 chassis and front panel
- North Star ZPB-A2 Z80A CPU
  - native IMSAI front-panel interface
  - auto-jump/reset target: `F000H`
- Altair FDC+
  - 60K RAM: `0000H-EFFFH`
  - 4K ROM window: `F000H-FFFFH`
  - existing full-64K modification remains installed
  - 27C64 / 28C64 ROM socket
- S100Computers Dual IDE/CF V3 at `30H-34H`
- S100Computers Console I/O V2 at `00H-01H`
- S100Computers Serial I/O V3, channel A at `A1H/A3H`
- IMSAI MIO at `40H-43H`
  - SIO data: `42H`
  - SIO status/control: `43H`
  - verified working at 19,200 baud, 8N1

Future additions may include the Digital Systems disk subsystem, Polymorphic VTI, and other S-100 boards, but they are deliberately excluded from the first build.

## Memory map

| Range | Function |
|---|---|
| `0000H-EFFFH` | FDC+ RAM |
| `F000H-FEFFH` | 4K monitor code/data |
| `FF00H-FFFFH` | Martin Eberhard CDBL boot loader |

The monitor therefore has 3840 bytes available before the fixed 256-byte CDBL image.

Because the FDC+ full-64K modification is installed, the PROM switch page used for this target must make RAM end at `EFFFH` and PROM begin at `F000H`. The build will also generate an 8K programmer image for the physical 27C64/28C64 socket, with the logical `F000H-FFFFH` image placed in the correct half of the device.

## IMSAI front-panel console selection

The IMSAI programmed-input/sense-switch byte is read at **port `FFH`**. `EFH` was a legacy S100Computers/John Monahan convention and is not used by this IMSAI target.

Switches 09 and 08 select the monitor console:

| SW09 | SW08 | Console |
|---:|---:|---|
| 0 | 0 | Console I/O V2 (`00H/01H`) |
| 0 | 1 | Serial I/O V3 Port A (`A1H/A3H`) |
| 1 | 0 | IMSAI MIO SIO (`42H/43H`) |
| 1 | 1 | Reserved; initially falls back to Console I/O |

The reserved state is intentionally available for a future fourth console such as the Polymorphic VTI.

The monitor will expose three generic console primitives and keep board-specific code behind them:

- `CONST` - character available?
- `CONIN` - read a character
- `CONOUT` - write a character

## First-build monitor features

Planned initial command set:

- `B` - boot menu
- `C` - boot Altair FDC+ using CDBL
- `D` - display memory
- `F` - fill memory
- `G` - go to address
- `H` - hardware / front-panel status
- `J` - RAM test
- `K` - command menu
- `M` - move memory
- `P` - boot CP/M from IDE/CF
- `Q` - single-port I/O read/write diagnostic
- `T` - type memory as ASCII
- `V` - verify/compare memory

`Ctrl-C` will immediately boot the configured IDE/CF device.

On reset the monitor will:

1. enter at `F000H` through the North Star auto-jump feature;
2. read the IMSAI front-panel byte from `FFH`;
3. select and initialize the requested console;
4. initialize the Dual IDE/CF interface;
5. display a compact IMSAI banner and hardware status;
6. perform a short cancelable IDE/CF auto-boot countdown;
7. enter the monitor if a key is pressed.

## Deliberately excluded from v0.1

To keep the ROM small and target-specific, the first build will not contain:

- Z80 CPU V2 ROM banking / port `D3H` support
- duplicate high/low ROM pages
- XMODEM
- RTC/time/date support
- printer support
- speech support
- Serial I/O channel B support
- extended-memory window commands
- scan-all-256-I/O-ports diagnostics
- legacy CP/M 1.x jump tables
- auxiliary processor support
- Versafloppy / ZFDC support
- Digital Systems disk support
- Polymorphic VTI support

These can be reconsidered later if ROM space remains.

## Build goals

The repository will build from Z80 source and produce at least:

- `IMSAI_TARGET_MONITOR_4K.bin` - exactly 4096 bytes, logical `F000H-FFFFH`
- `IMSAI_TARGET_MONITOR_28C64.bin` - exactly 8192 bytes, ready for the FDC+ 27C64/28C64 socket
- listing / symbol output when supported by the selected assembler

The build must fail if monitor code crosses into the fixed CDBL region at `FF00H` or if either final image has the wrong size.

## Development approach

GitHub is the source of truth from the beginning. Development will proceed in small, reviewable commits with reproducible local builds on Ubuntu.
