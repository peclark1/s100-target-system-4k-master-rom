# Digital Systems FDC-2 ROM Boot Test

This branch adds a software bootstrap for the Digital Systems HB-1.3 + FDC-2 subsystem while preserving the hardware-tested v0.1 monitor source as the baseline.

## Boot menu

The monitor boot submenu becomes:

- `I` — IDE/CF
- `F` — Altair FDC+ / CDBL
- `D` — Digital Systems FDC-2 drive 0
- `M` — return to monitor

The main monitor `D` command remains Display; `D` means DSI only inside the `B` boot submenu.

## What the DSI ROM bootstrap does

1. Select FDC-2 physical drive 0 with command `08H`.
2. Home the drive to track 0 using FDC-2 Step Ready (`02H`) and Track Zero (`04H`) status.
3. Build a 131-byte DMA record at `EE00H`:
   - byte 0: track `00H`
   - byte 1: physical sector `01H`
   - byte 2: address mark `FBH`
   - bytes 3..130: sector data
4. Program DMA low/high through ports `7DH/7EH` and issue READ `40H` on `7FH`.
5. Retry the read up to three times.
6. Copy the returned 128 bytes from `EE03H` to `0000H-007FH`.
7. Jump to `0000H`.

Finite step/read timeouts return to the monitor instead of hanging. Read failures display the final FDC-2 status byte.

## Why a bounce buffer is required

The FDC-2 wants the track/sector/address-mark descriptor immediately before the 128-byte sector data. A historical bootstrap can arrange for the descriptor to sit below address zero and wrap the actual sector into `0000H`.

That is unsuitable for this target system because the monitor ROM occupies `F000H-FFFFH`. The software bootstrap therefore DMA-reads the complete 131-byte record into ordinary RAM at `EE00H`, then copies only the 128 data bytes to address zero.

This private boot-time buffer does not reduce CP/M TPA; CP/M may overwrite it after boot.

## Safe hardware acceptance test before disabling HB-1.3 auto-bootstrap

Use a known-good bootable DSI single-density CP/M floppy in physical drive 0.

1. Reset and cancel the IDE auto-boot so the 4K monitor is running.
2. Deliberately destroy the already-loaded bootstrap sector in RAM:

   ```text
   F 0000,007F,00
   ```

3. Optional: display a few bytes to confirm they are zero:

   ```text
   D 0000,000F
   ```

4. Enter the boot submenu and choose DSI:

   ```text
   B
   D
   ```

5. A successful CP/M boot proves that the ROM itself homed the drive, read track 0 sector 1, copied it to zero, and transferred execution to it.

Only after this passes should the HB-1.3 automatic bootstrap feature be inhibited.

## Failure messages

- `DSI FDC-2 HOME/STEP TIMEOUT`
- `DSI FDC-2 READ ERROR STATUS=xx`

On either error the monitor remains available for diagnostics.
