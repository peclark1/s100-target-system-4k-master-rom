;=============================================================================
; IMSAI TARGET ROM - NATIVE FDC+3712 BOOT MODULE
;
; Logical address: F800H
;
; Boots Mike Douglas's supplied 48K CP/M 2.2 FDC+3712 system directly from
; drive 0.  This is the ROM-native successor to the CDBL hook.
;
; The loader and controller primitives are derived from the physically proven
; 3712BOOT/3712SVC path in peclark1/altair-fdcplus-software and from Mike
; Douglas's PROM.ASM/BOOT.ASM programming model.
;
; First ROM milestone is intentionally READ ONLY.  The CP/M BIOS WRITE entry
; returns error without issuing an FDC+ write command.
;
; Console BIOS entries are patched in RAM to use the master ROM's public
; console primitives, so SW09/SW08 console selection continues into CP/M.
;=============================================================================

        ORG     0F800H

; Master ROM public entry points
MON_CONIN       EQU     0F003H
MON_CONOUT      EQU     0F006H
MON_CONST       EQU     0F009H
MONITOR         EQU     0F00CH
MON_STACK       EQU     0EFC0H

; Supplied 48K CP/M 2.2 image layout
CCPBASE         EQU     0A600H
BIOSBASE        EQU     0BC00H
COLDCOMMON      EQU     0BC9EH
LOADEND         EQU     0BF80H
LOADLEN         EQU     LOADEND-CCPBASE

IOBYTE          EQU     0003H
CDISK           EQU     0004H

; Page-zero work area used by Mike Douglas's PROM
DRVNUM          EQU     0040H
TRKNUM          EQU     0041H
SECNUM          EQU     0042H
DMAADDR         EQU     0043H
DRVTRK          EQU     0045H
BIOSADR         EQU     0046H

; FDC+3712 commands
C_READ          EQU     03H
C_SEEK          EQU     09H
C_CLRERR        EQU     0BH
C_RESTORE       EQU     0DH
C_SETTRK        EQU     11H
C_LDCFG         EQU     15H
C_DRVSEC        EQU     21H
C_RDBUF         EQU     40H
C_SHIFT         EQU     41H
C_RESET         EQU     81H

S_BUSY          EQU     01H
S_SKERR         EQU     02H
S_CRCERR        EQU     08H
S_NOTRDY        EQU     20H

CMDOUT          EQU     08H
DATAIN          EQU     08H
DATAOUT         EQU     09H

NUMSEC          EQU     26
SECLEN          EQU     128

;=============================================================================
; Cold ROM boot
;=============================================================================
FDC3712_BOOT:
        DI
        LD      SP,MON_STACK

        CALL    INIT_ALL

        ; Track 0: physical sectors 3,5,...25,2,4,...26.
        LD      C,0
        CALL    SETTRK
        LD      HL,CCPBASE+SECLEN       ; A680H
        LD      A,3
        CALL    LOAD_TRACK_COLD
        JP      NZ,BOOT_FAIL

        ; Track 1: physical sectors 1,3,...25,2,4,...26.
        LD      C,1
        CALL    SETTRK
        LD      HL,CCPBASE+SECLEN*(NUMSEC-1) ; B280H
        LD      A,1
        CALL    LOAD_TRACK_COLD
        JP      NZ,BOOT_FAIL

        ; Verify the exact physically validated 51-sector image before patching.
        LD      HL,CCPBASE
        LD      BC,LOADLEN
        CALL    CHECKSUM_RANGE
        LD      A,D
        CP      054H
        JP      NZ,BOOT_BAD_IMAGE
        LD      A,E
        CP      0B0H
        JP      NZ,BOOT_BAD_IMAGE

        CALL    PATCH_BIOS
        JP      BIOSBASE               ; patched cold vector -> COLD_FULL

; Load one physical track using interleave 2.  C0H is the first page beyond
; the 48K system image, so addresses C000H and above are skipped.
LOAD_TRACK_COLD:
        LD      C,A
LTC_LOOP:
        LD      A,H
        CP      0C0H
        JR      NC,LTC_SKIP

        PUSH    HL
        PUSH    BC
        CALL    SETSEC
        LD      B,H
        LD      C,L
        CALL    SETDMA
        CALL    READ
        POP     BC
        POP     HL
        OR      A
        RET     NZ

LTC_SKIP:
        LD      DE,0100H                ; +2 sectors
        ADD     HL,DE
        LD      A,2
        ADD     A,C
        CP      NUMSEC+1
        JR      C,LOAD_TRACK_COLD

        SUB     NUMSEC-1                ; 27->2, 28->3
        LD      DE,0F380H               ; -(25*128)
        ADD     HL,DE
        CP      2
        JR      Z,LOAD_TRACK_COLD
        XOR     A
        RET

BOOT_FAIL:
        LD      HL,MSG_READ_FAIL
        JR      BOOT_ERROR
BOOT_BAD_IMAGE:
        LD      HL,MSG_BAD_IMAGE
BOOT_ERROR:
        CALL    PRINT_Z
        JP      MONITOR

;=============================================================================
; RAM BIOS patching
;=============================================================================
; Disk image remains unchanged.  Only the freshly loaded BIOS jump table and
; four internal PROM calls are redirected to the resident ROM services.
PATCH_BIOS:
        ; BIOS cold start -> ROM-integrated cold start.
        LD      A,0C3H
        LD      (0BC00H),A
        LD      HL,COLD_FULL
        LD      (0BC01H),HL

        ; Console status/input/output.
        LD      A,0C3H
        LD      (0BC06H),A
        LD      HL,MON_CONST
        LD      (0BC07H),HL

        LD      A,0C3H
        LD      (0BC09H),A
        LD      HL,MON_CONIN
        LD      (0BC0AH),HL

        LD      A,0C3H
        LD      (0BC0CH),A
        LD      HL,CPM_CONOUT
        LD      (0BC0DH),HL

        ; LIST and PUNCH follow the selected console for the first milestone.
        LD      A,0C3H
        LD      (0BC0FH),A
        LD      HL,CPM_CONOUT
        LD      (0BC10H),HL

        LD      A,0C3H
        LD      (0BC12H),A
        LD      HL,CPM_CONOUT
        LD      (0BC13H),HL

        ; READER follows selected console input.
        LD      A,0C3H
        LD      (0BC15H),A
        LD      HL,MON_CONIN
        LD      (0BC16H),HL

        ; Disk entry vectors.  SELDSK remains the BIOS routine at BCxx because
        ; it validates the drive and returns a DPH; its internal PROM call is
        ; redirected below.
        LD      A,0C3H
        LD      (0BC18H),A
        LD      HL,HOME
        LD      (0BC19H),HL

        LD      A,0C3H
        LD      (0BC1EH),A
        LD      HL,SETTRK
        LD      (0BC1FH),HL

        LD      A,0C3H
        LD      (0BC21H),A
        LD      HL,SETSEC
        LD      (0BC22H),HL

        LD      A,0C3H
        LD      (0BC24H),A
        LD      HL,SETDMA
        LD      (0BC25H),HL

        LD      A,0C3H
        LD      (0BC27H),A
        LD      HL,READ
        LD      (0BC28H),HL

        LD      A,0C3H
        LD      (0BC2AH),A
        LD      HL,WRITE_RO
        LD      (0BC2BH),HL

        LD      A,0C3H
        LD      (0BC2DH),A
        LD      HL,CPM_LISTST
        LD      (0BC2EH),HL

        ; Original BIOS internal calls to the old F400H PROM.
        LD      A,0CDH
        LD      (0BC3CH),A
        LD      HL,PROM_COLD
        LD      (0BC3DH),HL

        LD      A,0CDH
        LD      (0BC95H),A
        LD      HL,PROM_WARM
        LD      (0BC96H),HL

        LD      A,0CDH
        LD      (0BCA1H),A
        LD      HL,SETDMA
        LD      (0BCA2H),HL

        LD      A,0CDH
        LD      (0BCCAH),A
        LD      HL,SELDRV
        LD      (0BCCBH),HL
        RET

;=============================================================================
; CP/M cold/warm integration
;=============================================================================
COLD_FULL:
        DI
        LD      SP,0100H
        LD      HL,BIOSBASE
        LD      (BIOSADR),HL

        CALL    INIT_ALL

        ; Preserve the supplied BIOS default IOBYTE for software compatibility.
        ; Actual CON/RDR/PUN/LST routing is currently handled by patched vectors.
        LD      A,095H
        LD      (IOBYTE),A
        XOR     A
        LD      (CDISK),A

        LD      HL,MSG_COLD
        CALL    PRINT_Z

        ; MODE=0 in the supplied image: no automatic cold command line.
        XOR     A
        PUSH    AF
        JP      COLDCOMMON

; Compatibility form used if the original cBoot body is entered directly.
PROM_COLD:
        LD      (BIOSADR),HL
        RET

; Reload CCP+BDOS on warm boot, preserving the patched BIOS in BC00H-BFFFH.
PROM_WARM:
        CALL    INIT_ALL

        LD      HL,CCPBASE+SECLEN       ; A680H, track 0 sector 3
        LD      C,0
        CALL    SETTRK
        LD      A,3
        CALL    LOAD_TRACK_WARM
        JR      NZ,PROM_WARM

        LD      HL,CCPBASE+SECLEN*(NUMSEC-1) ; B280H, track 1 sector 1
        LD      C,1
        CALL    SETTRK
        LD      A,1
        CALL    LOAD_TRACK_WARM
        JR      NZ,PROM_WARM
        XOR     A
        RET

; Same interleave algorithm, but do not reload pages BCh and above (the BIOS).
LOAD_TRACK_WARM:
        LD      C,A
LTW_LOOP:
        LD      A,H
        CP      0BCH
        JR      NC,LTW_SKIP

        PUSH    HL
        PUSH    BC
        CALL    SETSEC
        LD      B,H
        LD      C,L
        CALL    SETDMA
        CALL    READ
        POP     BC
        POP     HL
        OR      A
        RET     NZ

LTW_SKIP:
        LD      DE,0100H
        ADD     HL,DE
        LD      A,2
        ADD     A,C
        CP      NUMSEC+1
        JR      C,LOAD_TRACK_WARM

        SUB     NUMSEC-1
        LD      DE,0F380H
        ADD     HL,DE
        CP      2
        JR      Z,LOAD_TRACK_WARM
        XOR     A
        RET

CPM_CONOUT:
        LD      A,C
        JP      MON_CONOUT

CPM_LISTST:
        LD      A,0FFH
        RET

;=============================================================================
; FDC+3712 service primitives
;=============================================================================
HOME:
        LD      C,0
        ; fall through
SETTRK:
        LD      A,C
        LD      (TRKNUM),A
        RET

SELDRV:
        LD      A,C
        LD      (DRVNUM),A
        LD      A,0FFH
        LD      (DRVTRK),A
        RET

SETSEC:
        LD      A,C
        LD      (SECNUM),A
        RET

SETDMA:
        LD      H,B
        LD      L,C
        LD      (DMAADDR),HL
        RET

READ:
        CALL    SELECT_SEEK
        JP      NZ,ERR_EXIT

        LD      C,10
READ_RETRY:
        LD      A,C_READ
        CALL    DO_CMD
        AND     S_NOTRDY+S_CRCERR
        JR      Z,READ_TRANSFER
        CALL    CLR_ERRORS
        DEC     C
        JR      NZ,READ_RETRY
        JP      ERR_EXIT

READ_TRANSFER:
        LD      HL,(DMAADDR)
        LD      C,SECLEN
READ_BUFFER_LOOP:
        LD      A,C_RDBUF
        OUT     (CMDOUT),A
        IN      A,(DATAIN)
        LD      (HL),A
        LD      A,C_SHIFT
        OUT     (CMDOUT),A
        INC     HL
        DEC     C
        JR      NZ,READ_BUFFER_LOOP
        XOR     A
        OUT     (CMDOUT),A
        RET

; First native-ROM milestone is intentionally read-only.
WRITE_RO:
ERR_EXIT:
        LD      A,1
        OR      A
        RET

SELECT_SEEK:
        XOR     A
        OUT     (DATAOUT),A
        LD      A,C_LDCFG
        CALL    OUT_CMD
        CALL    SELECT_SECTOR
        CALL    SEEK
        RET

SELECT_SECTOR:
        LD      A,(DRVNUM)
        AND     03H
        RRCA
        RRCA
        LD      C,A
        LD      A,(SECNUM)
        OR      C
        OUT     (DATAOUT),A
        LD      A,C_DRVSEC
        CALL    OUT_CMD
        RET

SEEK:
        LD      C,2
SEEK_LOOP:
        LD      A,(TRKNUM)
        LD      HL,DRVTRK
        CP      (HL)
        RET     Z

        LD      (HL),A
        LD      A,(TRKNUM)
        OUT     (DATAOUT),A
        LD      A,C_SETTRK
        CALL    OUT_CMD

        LD      A,C_SEEK
        CALL    DO_CMD
        AND     S_NOTRDY+S_CRCERR
        RET     Z

        CALL    CLR_ERRORS
        LD      (HL),0FFH
        DEC     C
        JR      NZ,SEEK_LOOP

        CALL    RESET0
        LD      A,S_SKERR
        OR      A
        RET

INIT_ALL:
        XOR     A
        LD      (DRVNUM),A
        INC     A
        LD      (SECNUM),A
        ; fall through
RESET0:
        LD      A,C_RESET
        CALL    OUT_CMD
        CALL    SELECT_SECTOR
        LD      A,0FFH
        LD      (DRVTRK),A
        LD      A,C_RESTORE
        JP      DO_CMD

DO_CMD:
        CALL    OUT_CMD
DO_CMD_WAIT:
        IN      A,(DATAIN)
        AND     S_BUSY
        JR      NZ,DO_CMD_WAIT
        IN      A,(DATAIN)
        RET

CLR_ERRORS:
        LD      A,C_CLRERR
        ; fall through
OUT_CMD:
        OUT     (CMDOUT),A
        XOR     A
        OUT     (CMDOUT),A
        RET

;=============================================================================
; Verification / display helpers
;=============================================================================
CHECKSUM_RANGE:
        LD      DE,0000H
CHECKSUM_LOOP:
        LD      A,E
        ADD     A,(HL)
        LD      E,A
        JR      NC,CHECKSUM_NO_CARRY
        INC     D
CHECKSUM_NO_CARRY:
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CHECKSUM_LOOP
        RET

PRINT_Z:
        LD      A,(HL)
        OR      A
        RET     Z
        INC     HL
        CALL    MON_CONOUT
        JR      PRINT_Z

MSG_COLD:
        DB      0DH,0AH
        DB      '48K CP/M 2.2 - FDC+3712 / IMSAI',0DH,0AH
        DB      'ROM console selection active; disk writes disabled.',0DH,0AH,0
MSG_READ_FAIL:
        DB      0DH,0AH,'FDC+3712 READ/SEEK ERROR',0DH,0AH,0
MSG_BAD_IMAGE:
        DB      0DH,0AH,'FDC+3712 SYSTEM IMAGE CHECKSUM ERROR',0DH,0AH,0

        END     FDC3712_BOOT
