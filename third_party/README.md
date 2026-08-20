# Third-party ROM content

## CDBL 2.05

`CDBL.HEX` is the 256-byte Martin Eberhard Combined Disk Boot Loader used by the Altair FDC+ software ecosystem. It executes at `FF00H`, relocates itself to RAM at `4C00H`, and supports the original Altair 8-inch and Minidisk interfaces through FDC/FDC+ ports `08H-0AH`.

The source image used by the earlier IMSAI V5.6 target project contained data through `FFF4H`; the published assembled source shows the remaining bytes `FFF5H-FFFFH` as zero padding. This repository makes those eleven trailing zero bytes explicit and uses a normal Intel HEX EOF record so the build can verify that the complete `FF00H-FFFFH` region is defined.

The loader itself is otherwise unchanged.

Upstream reference: Mike Douglas / deramp.com Altair FDC+ software and Martin Eberhard improved ROMs.
