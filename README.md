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

The current v0.1 source assembles to **1993 bytes**, leaving **1847 bytes free** before CDBL. The build checks this limit automatically.

### FDC+ Rev B target configuration

This project assumes the existing FDC+ full-64K modification remains installed. With that modification, the PROM page switch specifies the **last RAM page**, and PROM starts on the following 256-byte page. For the target map:

- RAM start: `0000H`
- RAM end: `EFFFH`
- PROM start: `F000H`
- PROM page address switches `A12..A8`: `0 1 1 1 1` (page `EFH`)
- PROM enable: enabled

At CPU address `F000H`, A12 is high, so the logical 4K ROM occupies the **upper 4K half** of the physical 27C64/28C64. `tools/build_image.py` therefore creates an 8K programmer image with the lower 4K filled with `FFH` and the complete logical monitor in the upper 4K.

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

The monitor exposes three generic console primitives and keeps board-specific code behind them:

- `CONST` - character available?
- `CONIN` - read a character
- `CONOUT` - write a character

Only Serial I/O Port A requires software initialization. The MIO SIO is configured by the board's hardware options and is designed to require no serial initialization at power-up.

## First-build monitor features

Implemented initial command set:

- `B` - boot menu
- `C` - boot Altair FDC+ using CDBL
- `D` - display memory
- `F` - fill memory
- `G` - go to address
- `H` - hardware / front-panel status
- `J` - non-destructive RAM test
- `K` - command menu
- `M` - move memory
- `P` - boot CP/M from IDE/CF
- `Q` - single-port I/O read/write diagnostic
- `T` - type memory as ASCII
- `V` - verify/compare memory

`Ctrl-C` immediately boots the configured IDE/CF device.

On reset the monitor:

1. enters at `F000H` through the North Star auto-jump feature;
2. reads the IMSAI front-panel byte from `FFH`;
3. selects the requested console and initializes it if required;
4. initializes the Dual IDE/CF interface;
5. displays a compact IMSAI banner and hardware status;
6. performs a short cancelable IDE/CF auto-boot countdown;
7. enters the monitor if a key is pressed.

## Deliberately excluded from v0.1

To keep the ROM small and target-specific, the first build does not contain:

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

These can be reconsidered later if useful; the current build has substantial ROM space remaining.

## Building on Ubuntu

Install the assembler once:

```sh
sudo apt update
sudo apt install pasmo
```

Then clone/pull the repository and build:

```sh
make verify
```

A successful build creates:

- `build/IMSAI_TARGET_MONITOR_4K.bin` - exactly 4096 bytes, logical `F000H-FFFFH`
- `build/IMSAI_TARGET_MONITOR_28C64.bin` - exactly 8192 bytes, ready for the FDC+ 27C64/28C64 socket
- `build/monitor.raw.bin` - assembled monitor body before padding/CDBL insertion
- `build/monitor.sym` - Pasmo symbol table

The build fails if monitor code crosses into the fixed CDBL region at `FF00H`, if CDBL is not exactly 256 bytes, or if either final ROM image has the wrong structure/size.

The first successful GitHub Actions build produced:

- monitor body: `1993 / 3840` bytes
- free before CDBL: `1847` bytes
- 4K SHA-256: `50edb2a1bfceb5fc19b782550c9dbacefd75629a773200bb88f6ee8eab26724c`
- 8K SHA-256: `1473d9295a72b156ced08d68aa026537eb48888ccb6efbcdea1e19b95548c696`

## Development approach

GitHub is the source of truth from the beginning. Development proceeds in small, reviewable commits with reproducible local builds on Ubuntu. Hardware-test candidates are developed on a branch/PR and are not merged to `main` until reviewed and bench-tested.
