;=============================================================================
; DIGITAL SYSTEMS FDC-2 BOOT SUPPORT
;
; Software replacement for the HB-1.3 automatic bootstrap.  Reads physical
; drive 0, track 0, sector 1 into a private 131-byte descriptor/data buffer,
; copies the 128-byte boot sector to 0000H-007FH, then jumps to 0000H.
;
; Protocol and timings are derived from the hardware-tested CP/M 3 DSIFDC2
; driver, which in turn follows the period Digital Systems CBIOS14 behavior.
;=============================================================================

DSI_DMA_LO       EQU     07DH
DSI_DMA_HI       EQU     07EH
DSI_CMD          EQU     07FH
DSI_STATUS       EQU     07FH
DSI_SELECT0      EQU     08H
DSI_READ_CMD     EQU     040H
DSI_STEP_READY   EQU     02H
DSI_TRACK_ZERO   EQU     04H
DSI_ERR_MASK     EQU     0F0H

; Private boot-time RAM.  The monitor stack/work area starts at EFC0H, so this
; 131-byte DMA buffer and status byte do not overlap it.
DSI_BUF          EQU     0EE00H         ; 00=track, 01=sector, 02=FB, 03..82=data
DSI_LAST_STATUS  EQU     0EE83H
DSI_READ_RETRIES EQU     3

DSI_BOOT:
        LD      SP,STACK_TOP
        CALL    PRINT_CRLF
        LD      HL,MSG_DSI_BOOT
        CALL    PRINT_STR

        CALL    DSI_HOME0
        JR      C,DSI_BOOT_HOME_ERROR

        XOR     A
        LD      (DSI_BUF),A             ; track 0
        INC     A
        LD      (DSI_BUF+1),A           ; physical sector 1
        LD      A,0FBH
        LD      (DSI_BUF+2),A           ; normal data address mark

        LD      B,DSI_READ_RETRIES
DSI_BOOT_RETRY:
        PUSH    BC
        CALL    DSI_READ_SECTOR
        POP     BC
        JR      NC,DSI_BOOT_COPY
        DJNZ    DSI_BOOT_RETRY

        LD      HL,MSG_DSI_READ_ERROR
        CALL    PRINT_STR
        LD      A,(DSI_LAST_STATUS)
        CALL    PRINT_HEX8
        LD      A,CR
        CALL    CONOUT
        LD      A,LF
        CALL    CONOUT
        JP      MONITOR

DSI_BOOT_HOME_ERROR:
        LD      HL,MSG_DSI_HOME_ERROR
        CALL    PRINT_STR
        JP      MONITOR

DSI_BOOT_COPY:
        LD      HL,DSI_BUF+3
        LD      DE,0000H
        LD      BC,0080H
        LDIR
        JP      0000H

; Select physical unit 0 and step outward until TRACK ZERO is asserted.
; Carry set on timeout/failure.
DSI_HOME0:
        LD      A,DSI_SELECT0
        OUT     (DSI_CMD),A
        LD      B,90                    ; more than enough for a 77-track drive
DSI_HOME_LOOP:
        IN      A,(DSI_STATUS)
        AND     DSI_TRACK_ZERO
        JR      NZ,DSI_HOME_DONE
        PUSH    BC
        CALL    DSI_STEP_OUT
        POP     BC
        RET     C
        DJNZ    DSI_HOME_LOOP
        SCF
        RET
DSI_HOME_DONE:
        CALL    DSI_SETTLE
        OR      A                       ; clear carry
        RET

; One physical step toward track zero.  The FDC-2 keeps the selected unit
; latched after DSI_SELECT0, matching the period driver behavior.
DSI_STEP_OUT:
        LD      DE,0FFFFH
DSI_STEP_WAIT:
        IN      A,(DSI_STATUS)
        AND     DSI_STEP_READY
        JR      NZ,DSI_STEP_PULSE
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,DSI_STEP_WAIT
        SCF
        RET
DSI_STEP_PULSE:
        XOR     A                       ; direction OUT
        OUT     (DSI_CMD),A
        LD      A,02H                   ; pulse STEP
        OUT     (DSI_CMD),A
        XOR     A
        OUT     (DSI_CMD),A
        OR      A                       ; clear carry
        RET

; Conservative head-settle delay copied from the hardware-tested CP/M driver.
; About 24.6 ms even at a 10 MHz Z80, longer on slower CPUs.
DSI_SETTLE:
        LD      BC,2800H
DSI_SETTLE_LOOP:
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,DSI_SETTLE_LOOP
        RET

; Read track 0 / sector 1 into DSI_BUF.  The FDC-2 DMA record is 131 bytes:
; three descriptor bytes followed by 128 data bytes.  Carry set on timeout or
; controller error; DSI_LAST_STATUS always contains the final observed status.
DSI_READ_SECTOR:
        LD      HL,DSI_BUF
        LD      A,H
        OUT     (DSI_DMA_HI),A
        LD      A,L
        OUT     (DSI_DMA_LO),A
        LD      A,DSI_READ_CMD
        OUT     (DSI_CMD),A

        LD      DE,0FFFFH
DSI_IO_WAIT:
        IN      A,(DSI_STATUS)
        LD      (DSI_LAST_STATUS),A
        AND     0F8H                    ; I/O finish or any high error bit
        JR      NZ,DSI_IO_DONE
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,DSI_IO_WAIT
        LD      A,0FFH                  ; synthetic timeout marker
        LD      (DSI_LAST_STATUS),A
        SCF
        RET

DSI_IO_DONE:
        IN      A,(DSI_STATUS)
        LD      (DSI_LAST_STATUS),A
        AND     DSI_ERR_MASK
        JR      NZ,DSI_IO_ERROR
        OR      A                       ; clear carry
        RET
DSI_IO_ERROR:
        SCF
        RET

MSG_DSI_BOOT:
        DB      'BOOTING DIGITAL SYSTEMS FDC-2 DRIVE 0...',CR,LF,0
MSG_DSI_HOME_ERROR:
        DB      'DSI FDC-2 HOME/STEP TIMEOUT',CR,LF,0
MSG_DSI_READ_ERROR:
        DB      'DSI FDC-2 READ ERROR STATUS=',0
