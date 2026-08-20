;=============================================================================
; IMSAI 8080 TARGET SYSTEM - 4K MASTER ROM
;
; Clean monitor for:
;   North Star ZPB-A2 Z80A CPU
;   Altair FDC+ RAM 0000H-EFFFH / ROM F000H-FFFFH
;   Dual IDE/CF V3 at 30H-34H
;   Console I/O V2 at 00H/01H
;   Serial I/O V3 channel A at A1H/A3H
;   IMSAI MIO SIO at 42H/43H
;
; Assemble with Pasmo.  CDBL is installed separately by tools/build_image.py
; at FF00H-FFFFH, so this source MUST remain below FF00H.
;=============================================================================

        ORG     0F000H

;-----------------------------------------------------------------------------
; Fixed public entry points.  Keep these stable once released.
;-----------------------------------------------------------------------------
        JP      RESET                   ; F000H - cold entry / North Star auto-jump
        JP      CONIN                   ; F003H - blocking console input, A=character
        JP      CONOUT                  ; F006H - console output, A=character
        JP      CONST                   ; F009H - A=FF if character ready, else 00
        JP      MONITOR                 ; F00CH - warm monitor entry

;-----------------------------------------------------------------------------
; Constants and target hardware map
;-----------------------------------------------------------------------------
CR              EQU     0DH
LF              EQU     0AH
SPACE           EQU     20H
ESC             EQU     1BH
CTRL_C          EQU     03H

PANEL_PORT      EQU     0FFH            ; IMSAI programmed-input/sense switches

CIO_STATUS      EQU     00H
CIO_DATA        EQU     01H
CIO_RX_READY    EQU     02H             ; status bit 1
CIO_TX_READY    EQU     04H             ; status bit 2

SER_A_CTRL      EQU     0A1H
SER_A_DATA      EQU     0A3H
SER_RX_READY    EQU     01H             ; SCC RR0 bit 0
SER_TX_READY    EQU     04H             ; SCC RR0 bit 2

MIO_DATA        EQU     042H
MIO_STATUS      EQU     043H
MIO_TX_READY    EQU     01H             ; CTL0 is jumpered to TR
MIO_RX_READY    EQU     02H             ; CTL1 is jumpered to RR

IDE_A           EQU     030H
IDE_B           EQU     031H
IDE_C           EQU     032H
IDE_CTRL        EQU     033H
IDE_DRIVE       EQU     034H

IDE_RD_CFG      EQU     092H            ; 8255: A/B input, C output
IDE_WR_CFG      EQU     080H            ; 8255: all output
IDE_RESET_BIT   EQU     080H
IDE_RD_BIT      EQU     040H
IDE_WR_BIT      EQU     020H

IDE_REG_DATA    EQU     008H
IDE_REG_COUNT   EQU     00AH
IDE_REG_SECTOR  EQU     00BH
IDE_REG_CYL_LO  EQU     00CH
IDE_REG_CYL_HI  EQU     00DH
IDE_REG_SDH     EQU     00EH
IDE_REG_STATUS  EQU     00FH
IDE_REG_COMMAND EQU     00FH
IDE_CMD_READ    EQU     020H

CPMLDR_ADDR     EQU     0100H
CPMLDR_SECTORS  EQU     12              ; proven V5.6 target setting

; Monitor-private RAM.  The physical FDC+ RAM still extends through EFFFH.
; Keep the stack/work bytes away from the CP/M loader at 0100H.
PANEL_BYTE      EQU     0EFC0H
CONSOLE_SEL     EQU     0EFC1H
STACK_TOP       EQU     0EFC0H

CONSOLE_CIO     EQU     0
CONSOLE_SERIAL  EQU     1
CONSOLE_MIO     EQU     2

;=============================================================================
; RESET / STARTUP
;=============================================================================
RESET:
        DI
        LD      SP,STACK_TOP

        IN      A,(PANEL_PORT)
        LD      (PANEL_BYTE),A
        AND     03H                     ; bit 0=SW08, bit 1=SW09
        CP      03H
        JR      NZ,RESET_SEL_OK
        XOR     A                       ; reserved 11 -> Console I/O fallback
RESET_SEL_OK:
        LD      (CONSOLE_SEL),A

        CP      CONSOLE_SERIAL
        CALL    Z,SERIAL_INIT_A         ; only initialize SCC A when selected

        CALL    PRINT_BANNER
        CALL    IDE_INIT                ; harmless reset/init before countdown
        JP      AUTO_BOOT

;=============================================================================
; MAIN MONITOR
;=============================================================================
MONITOR:
        LD      SP,STACK_TOP
MONITOR_LOOP:
        CALL    PRINT_CRLF
        LD      HL,MSG_PROMPT
        CALL    PRINT_STR

MONITOR_GET_CMD:
        CALL    CONIN
        CP      CR
        JR      Z,MONITOR_GET_CMD
        CP      SPACE
        JR      Z,MONITOR_GET_CMD
        CP      CTRL_C
        JP      Z,IDE_BOOT
        CALL    TO_UPPER
        PUSH    AF
        CALL    CONOUT
        POP     AF

        CP      'B'
        JP      Z,CMD_BOOT_MENU
        CP      'C'
        JP      Z,FDC_BOOT
        CP      'D'
        JP      Z,CMD_DISPLAY
        CP      'F'
        JP      Z,CMD_FILL
        CP      'G'
        JP      Z,CMD_GOTO
        CP      'H'
        JP      Z,CMD_HARDWARE
        CP      'J'
        JP      Z,CMD_RAMTEST
        CP      'K'
        JP      Z,CMD_MENU
        CP      'M'
        JP      Z,CMD_MOVE
        CP      'P'
        JP      Z,IDE_BOOT
        CP      'Q'
        JP      Z,CMD_IO
        CP      'T'
        JP      Z,CMD_TYPE
        CP      'V'
        JP      Z,CMD_VERIFY

        LD      HL,MSG_ERROR
        CALL    PRINT_STR
        JP      MONITOR_LOOP

;=============================================================================
; THREE-CONSOLE ABSTRACTION
;=============================================================================
; Console selector:
;   SW09 SW08 = 00 Console I/O, 01 Serial I/O A, 10 IMSAI MIO, 11 reserved.
;
; MIO status mapping is the verified base-40H setup: CTL0=TR and CTL1=RR.
; The MIO UART is configured by board jumpers and requires no monitor init.

CONST:
        LD      A,(CONSOLE_SEL)
        CP      CONSOLE_SERIAL
        JP      Z,SERIAL_CONST
        CP      CONSOLE_MIO
        JP      Z,MIO_CONST

CIO_CONST:
        IN      A,(CIO_STATUS)
        AND     CIO_RX_READY
        JR      Z,CONST_NONE
CONST_YES:
        LD      A,0FFH
        RET
CONST_NONE:
        XOR     A
        RET

CONIN:
        LD      A,(CONSOLE_SEL)
        CP      CONSOLE_SERIAL
        JP      Z,SERIAL_IN
        CP      CONSOLE_MIO
        JP      Z,MIO_IN
CIO_IN_WAIT:
        IN      A,(CIO_STATUS)
        AND     CIO_RX_READY
        JR      Z,CIO_IN_WAIT
        IN      A,(CIO_DATA)
        AND     7FH
        RET

CONOUT:
        PUSH    BC
        LD      B,A                     ; preserve character while dispatching
        LD      A,(CONSOLE_SEL)
        CP      CONSOLE_SERIAL
        JR      Z,CONOUT_SERIAL
        CP      CONSOLE_MIO
        JR      Z,CONOUT_MIO
        LD      A,B
CIO_OUT_WAIT:
        PUSH    AF
        IN      A,(CIO_STATUS)
        AND     CIO_TX_READY
        JR      NZ,CIO_OUT_GO
        POP     AF
        JR      CIO_OUT_WAIT
CIO_OUT_GO:
        POP     AF
        OR      A
        JR      Z,CONOUT_DONE           ; do not send NUL to Console I/O
        OUT     (CIO_DATA),A
        JR      CONOUT_DONE
CONOUT_SERIAL:
        LD      A,B
        CALL    SERIAL_OUT
        JR      CONOUT_DONE
CONOUT_MIO:
        LD      A,B
        CALL    MIO_OUT
CONOUT_DONE:
        POP     BC
        RET

;-------------------------- Serial I/O V3 channel A ---------------------------
SERIAL_CONST:
        IN      A,(SER_A_CTRL)
        AND     SER_RX_READY
        JR      Z,CONST_NONE
        JR      CONST_YES

SERIAL_IN:
        CALL    SERIAL_CONST
        JR      Z,SERIAL_IN
        IN      A,(SER_A_DATA)
        AND     7FH
        RET

SERIAL_OUT:
        PUSH    AF
SERIAL_OUT_WAIT:
        IN      A,(SER_A_CTRL)
        AND     SER_TX_READY
        JR      Z,SERIAL_OUT_WAIT
        POP     AF
        OUT     (SER_A_DATA),A
        RET

SERIAL_INIT_A:
        LD      C,SER_A_CTRL
        LD      B,14
        LD      HL,SCC_A_INIT
        OTIR
        RET

; 4.9152 MHz SCC clock, 38,400 baud, 8N1.  Proven V5.6 Port-A setup.
SCC_A_INIT:
        DB      04H,44H                 ; WR4: x16, 1 stop, no parity
        DB      03H,0C1H                ; WR3: receiver enable, 8 bits
        DB      05H,0EAH                ; WR5: transmitter enable, 8 bits
        DB      0BH,56H                 ; WR11: RX/TX clocks from BRG
        DB      0CH,02H                 ; WR12: 38,400 baud low byte
        DB      0DH,00H                 ; WR13: BRG high byte
        DB      0EH,01H                 ; WR14: enable BRG

;------------------------------- IMSAI MIO -----------------------------------
MIO_CONST:
        IN      A,(MIO_STATUS)
        AND     MIO_RX_READY
        JR      Z,CONST_NONE
        JR      CONST_YES

MIO_IN:
        CALL    MIO_CONST
        JR      Z,MIO_IN
        IN      A,(MIO_DATA)
        AND     7FH
        RET

MIO_OUT:
        PUSH    AF
MIO_OUT_WAIT:
        IN      A,(MIO_STATUS)
        AND     MIO_TX_READY
        JR      Z,MIO_OUT_WAIT
        POP     AF
        OUT     (MIO_DATA),A
        RET

;=============================================================================
; TEXT / HEX / INPUT SUPPORT
;=============================================================================
PRINT_STR:                              ; zero-terminated string at HL
        LD      A,(HL)
        OR      A
        RET     Z
        INC     HL
        CALL    CONOUT
        JR      PRINT_STR

PRINT_CRLF:
        LD      A,CR
        CALL    CONOUT
        LD      A,LF
        JP      CONOUT

PRINT_SPACE:
        LD      A,SPACE
        JP      CONOUT

PRINT_HEX8:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PRINT_NIBBLE
        POP     AF
PRINT_NIBBLE:
        AND     0FH
        ADD     A,'0'
        CP      ':'
        JR      C,PRINT_NIBBLE_GO
        ADD     A,7
PRINT_NIBBLE_GO:
        JP      CONOUT

PRINT_HEX16:                            ; preserves HL
        PUSH    HL
        LD      A,H
        CALL    PRINT_HEX8
        LD      A,L
        CALL    PRINT_HEX8
        POP     HL
        RET

TO_UPPER:
        CP      'a'
        RET     C
        CP      'z'+1
        RET     NC
        AND     5FH
        RET

; Read a hexadecimal value (1-4 digits) from the console.  Spaces and commas
; are skipped before the first digit.  The terminating delimiter is consumed.
; Returns HL=value.
GET_HEX16:
        LD      HL,0
        LD      B,0                     ; digit count
GET_HEX_CHAR:
        CALL    CONIN
        CP      CTRL_C
        JP      Z,IDE_BOOT
        CALL    TO_UPPER

        CP      SPACE
        JR      Z,GET_HEX_DELIM
        CP      ','
        JR      Z,GET_HEX_DELIM
        CP      CR
        JR      Z,GET_HEX_DELIM

        PUSH    AF
        CALL    CONOUT
        POP     AF
        CALL    HEX_VALUE
        JR      C,GET_HEX_CHAR          ; ignore non-hex input

        LD      C,A
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      A,L
        OR      C
        LD      L,A
        INC     B
        JR      GET_HEX_CHAR

GET_HEX_DELIM:
        LD      A,B
        OR      A
        JR      Z,GET_HEX_CHAR          ; no digits yet: keep skipping delimiters
        RET

HEX_VALUE:                              ; ASCII A -> nibble A, carry on error
        SUB     '0'
        JR      C,HEX_BAD
        CP      10
        JR      C,HEX_GOOD
        SUB     7                       ; 'A' becomes 10
        CP      10
        JR      C,HEX_BAD
        CP      16
        JR      NC,HEX_BAD
HEX_GOOD:
        OR      A                       ; clear carry
        RET
HEX_BAD:
        SCF
        RET

GET_TWO:                               ; HL=start, DE=end
        CALL    GET_HEX16
        PUSH    HL
        CALL    GET_HEX16
        EX      DE,HL
        POP     HL
        RET

GET_THREE:                             ; HL=start, DE=end, BC=third value/address
        CALL    GET_HEX16
        PUSH    HL
        CALL    GET_HEX16
        PUSH    HL
        CALL    GET_HEX16
        LD      B,H
        LD      C,L
        POP     DE
        POP     HL
        RET

RANGE_AT_END:                          ; Z when HL == DE
        LD      A,H
        CP      D
        RET     NZ
        LD      A,L
        CP      E
        RET

;=============================================================================
; COMMANDS
;=============================================================================
CMD_MENU:
        CALL    PRINT_CRLF
        LD      HL,MSG_MENU1
        CALL    PRINT_STR
        LD      HL,MSG_MENU2
        CALL    PRINT_STR
        JP      MONITOR_LOOP

CMD_HARDWARE:
        CALL    PRINT_CRLF
        LD      HL,MSG_HW1
        CALL    PRINT_STR
        LD      A,(PANEL_BYTE)
        CALL    PRINT_HEX8
        LD      HL,MSG_HW2
        CALL    PRINT_STR
        LD      A,(CONSOLE_SEL)
        OR      A
        JR      Z,HW_CIO
        CP      CONSOLE_SERIAL
        JR      Z,HW_SERIAL
        LD      HL,MSG_CON_MIO
        JR      HW_CON_PRINT
HW_CIO:
        LD      HL,MSG_CON_CIO
        JR      HW_CON_PRINT
HW_SERIAL:
        LD      HL,MSG_CON_SERIAL
HW_CON_PRINT:
        CALL    PRINT_STR
        LD      HL,MSG_HW3
        CALL    PRINT_STR
        JP      MONITOR_LOOP

CMD_DISPLAY:                            ; D start,end
        CALL    GET_TWO
DISP_LOOP:
        LD      A,L
        AND     0FH
        JR      NZ,DISP_BYTE
        CALL    PRINT_CRLF
        CALL    PRINT_HEX16
        LD      A,':'
        CALL    CONOUT
DISP_BYTE:
        CALL    PRINT_SPACE
        LD      A,(HL)
        CALL    PRINT_HEX8
        CALL    RANGE_AT_END
        JP      Z,MONITOR_LOOP
        INC     HL
        JR      DISP_LOOP

CMD_FILL:                               ; F start,end,value
        CALL    GET_THREE
        LD      A,C
FILL_LOOP:
        LD      (HL),A
        CALL    RANGE_AT_END
        JP      Z,MONITOR_LOOP
        INC     HL
        JR      FILL_LOOP

CMD_GOTO:                               ; G address
        CALL    GET_HEX16
        JP      (HL)

CMD_RAMTEST:                            ; J start,end, nondestructive
        CALL    GET_TWO
RAMTEST_LOOP:
        LD      A,(HL)
        LD      C,A                     ; original byte
        CPL
        LD      (HL),A
        CP      (HL)
        JR      NZ,RAMTEST_FAIL
        LD      A,C
        LD      (HL),A
        CP      (HL)
        JR      NZ,RAMTEST_FAIL
        CALL    RANGE_AT_END
        JR      Z,RAMTEST_PASS
        INC     HL
        JR      RAMTEST_LOOP
RAMTEST_PASS:
        LD      HL,MSG_PASS
        CALL    PRINT_STR
        JP      MONITOR_LOOP
RAMTEST_FAIL:
        LD      A,C
        LD      (HL),A                  ; best effort restore
        PUSH    HL
        LD      HL,MSG_FAIL
        CALL    PRINT_STR
        POP     HL
        CALL    PRINT_HEX16
        JP      MONITOR_LOOP

CMD_MOVE:                               ; M start,end,destination
        CALL    GET_THREE
MOVE_LOOP:
        LD      A,(HL)
        LD      (BC),A
        CALL    RANGE_AT_END
        JP      Z,MONITOR_LOOP
        INC     HL
        INC     BC
        JR      MOVE_LOOP

CMD_TYPE:                               ; T start,end
        CALL    GET_TWO
TYPE_LOOP:
        LD      A,(HL)
        AND     7FH
        CP      SPACE
        JR      C,TYPE_DOT
        CP      7FH
        JR      C,TYPE_GO
TYPE_DOT:
        LD      A,'.'
TYPE_GO:
        CALL    CONOUT
        CALL    RANGE_AT_END
        JP      Z,MONITOR_LOOP
        INC     HL
        JR      TYPE_LOOP

CMD_VERIFY:                             ; V start,end,destination
        CALL    GET_THREE
VERIFY_LOOP:
        LD      A,(BC)
        CP      (HL)
        JR      Z,VERIFY_NEXT
        PUSH    HL
        LD      HL,MSG_MISMATCH
        CALL    PRINT_STR
        POP     HL
        CALL    PRINT_HEX16
        CALL    PRINT_SPACE
        LD      A,(HL)
        CALL    PRINT_HEX8
        LD      A,'/'
        CALL    CONOUT
        LD      A,(BC)
        CALL    PRINT_HEX8
VERIFY_NEXT:
        CALL    RANGE_AT_END
        JP      Z,MONITOR_LOOP
        INC     HL
        INC     BC
        JR      VERIFY_LOOP

CMD_IO:                                 ; Q I,port  or  Q O,port,value
IO_GET_MODE:
        CALL    CONIN
        CALL    TO_UPPER
        CP      SPACE
        JR      Z,IO_GET_MODE
        CP      ','
        JR      Z,IO_GET_MODE
        PUSH    AF
        CALL    CONOUT
        POP     AF
        CP      'I'
        JR      Z,IO_INPUT
        CP      'O'
        JR      Z,IO_OUTPUT
        LD      HL,MSG_ERROR
        CALL    PRINT_STR
        JP      MONITOR_LOOP
IO_INPUT:
        CALL    GET_HEX16
        LD      C,L
        IN      A,(C)
        CALL    PRINT_SPACE
        CALL    PRINT_HEX8
        JP      MONITOR_LOOP
IO_OUTPUT:
        CALL    GET_HEX16
        PUSH    HL
        CALL    GET_HEX16
        LD      E,L
        POP     BC
        OUT     (C),E
        JP      MONITOR_LOOP

;=============================================================================
; BOOT SELECTION / AUTOBOOT
;=============================================================================
CMD_BOOT_MENU:
        CALL    PRINT_CRLF
        LD      HL,MSG_BOOT_MENU
        CALL    PRINT_STR
BOOT_MENU_WAIT:
        CALL    CONIN
        CALL    TO_UPPER
        CP      'I'
        JP      Z,IDE_BOOT
        CP      'F'
        JP      Z,FDC_BOOT
        CP      'M'
        JP      Z,MONITOR_LOOP
        JR      BOOT_MENU_WAIT

FDC_BOOT:
        CALL    PRINT_CRLF
        LD      HL,MSG_FDC_BOOT
        CALL    PRINT_STR
        JP      0FF00H                  ; exact published CDBL 2.05

AUTO_BOOT:
        LD      HL,MSG_AUTOBOOT
        CALL    PRINT_STR
        LD      B,3
AUTO_NUMBER:
        LD      A,B
        ADD     A,'0'
        CALL    CONOUT
        LD      A,SPACE
        CALL    CONOUT
        PUSH    BC
        CALL    AUTO_DELAY
        POP     BC
        JR      NZ,AUTO_CANCEL
        DJNZ    AUTO_NUMBER
        JP      IDE_BOOT
AUTO_CANCEL:
        CALL    CONIN                   ; consume canceling character
        LD      HL,MSG_CANCELLED
        CALL    PRINT_STR
        JP      MONITOR

; Return NZ if console input appears during the delay.
AUTO_DELAY:
        LD      DE,0FFFFH
AUTO_DELAY_LOOP:
        CALL    CONST
        OR      A
        RET     NZ
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,AUTO_DELAY_LOOP
        XOR     A
        RET

;=============================================================================
; DUAL IDE/CF BOOT - cleaned from the proven V5.6 target routines
;=============================================================================
IDE_BOOT:
        LD      SP,STACK_TOP
        CALL    PRINT_CRLF
        LD      HL,MSG_IDE_BOOT
        CALL    PRINT_STR

        CALL    IDE_INIT

        LD      D,0E0H                  ; master device, LBA mode
        LD      E,IDE_REG_SDH
        CALL    IDE_WRITE8

        CALL    IDE_WAIT_NOT_BUSY
        JR      C,IDE_NOT_READY

        LD      D,1                     ; LBA sector 1
        LD      E,IDE_REG_SECTOR
        CALL    IDE_WRITE8
        LD      D,0
        LD      E,IDE_REG_CYL_LO
        CALL    IDE_WRITE8
        LD      D,0
        LD      E,IDE_REG_CYL_HI
        CALL    IDE_WRITE8
        LD      D,CPMLDR_SECTORS
        LD      E,IDE_REG_COUNT
        CALL    IDE_WRITE8
        LD      D,IDE_CMD_READ
        LD      E,IDE_REG_COMMAND
        CALL    IDE_WRITE8

        CALL    IDE_WAIT_DRQ
        JR      C,IDE_READ_ERROR

        LD      HL,CPMLDR_ADDR
        LD      B,0                     ; DJNZ gives 256 words = 512 bytes
        LD      C,CPMLDR_SECTORS
IDE_READ_WORD:
        LD      A,IDE_REG_DATA
        OUT     (IDE_C),A
        OR      IDE_RD_BIT
        OUT     (IDE_C),A
        IN      A,(IDE_A)
        LD      (HL),A
        INC     HL
        IN      A,(IDE_B)
        LD      (HL),A
        INC     HL
        LD      A,IDE_REG_DATA
        OUT     (IDE_C),A
        DJNZ    IDE_READ_WORD
        DEC     C
        JR      NZ,IDE_READ_WORD

        LD      E,IDE_REG_STATUS
        CALL    IDE_READ8
        BIT     0,D
        JR      NZ,IDE_READ_ERROR

        LD      A,(CPMLDR_ADDR)
        CP      31H                     ; proven CPMLDR first opcode: LD SP,nn
        JR      NZ,IDE_BAD_LOADER
        JP      CPMLDR_ADDR

IDE_NOT_READY:
        LD      HL,MSG_IDE_NOT_READY
        JR      IDE_BOOT_ERROR
IDE_READ_ERROR:
        LD      HL,MSG_IDE_READ_ERROR
        JR      IDE_BOOT_ERROR
IDE_BAD_LOADER:
        LD      HL,MSG_IDE_BAD_LOADER
IDE_BOOT_ERROR:
        CALL    PRINT_STR
        JP      MONITOR

IDE_INIT:
        LD      A,IDE_RD_CFG
        OUT     (IDE_CTRL),A
        XOR     A                       ; select first CF device
        OUT     (IDE_DRIVE),A
        LD      A,IDE_RESET_BIT
        OUT     (IDE_C),A
        LD      C,020H
IDE_RESET_DELAY:
        DEC     C
        JR      NZ,IDE_RESET_DELAY
        XOR     A
        OUT     (IDE_C),A
        CALL    IDE_SETTLE_DELAY
        RET

IDE_SETTLE_DELAY:
        LD      A,40
IDE_SETTLE_OUTER:
        LD      B,0
IDE_SETTLE_INNER:
        DJNZ    IDE_SETTLE_INNER
        DEC     A
        JR      NZ,IDE_SETTLE_OUTER
        RET

IDE_WAIT_NOT_BUSY:
        LD      B,0FFH
        LD      C,080H
IDE_NB_LOOP:
        LD      E,IDE_REG_STATUS
        CALL    IDE_READ8
        LD      A,D
        AND     0C0H
        XOR     040H
        JR      Z,IDE_WAIT_OK
        DJNZ    IDE_NB_LOOP
        DEC     C
        JR      NZ,IDE_NB_LOOP
        SCF
        RET

IDE_WAIT_DRQ:
        LD      B,0FFH
        LD      C,0FFH
IDE_DRQ_LOOP:
        LD      E,IDE_REG_STATUS
        CALL    IDE_READ8
        LD      A,D
        AND     088H                   ; busy + DRQ
        CP      008H
        JR      Z,IDE_WAIT_OK
        DJNZ    IDE_DRQ_LOOP
        DEC     C
        JR      NZ,IDE_DRQ_LOOP
        SCF
        RET
IDE_WAIT_OK:
        OR      A                       ; clear carry
        RET

IDE_READ8:                              ; E=register, returns byte in D
        LD      A,E
        OUT     (IDE_C),A
        OR      IDE_RD_BIT
        OUT     (IDE_C),A
        IN      A,(IDE_A)
        LD      D,A
        LD      A,E
        OUT     (IDE_C),A
        XOR     A
        OUT     (IDE_C),A
        RET

IDE_WRITE8:                             ; E=register, D=data
        LD      A,IDE_WR_CFG
        OUT     (IDE_CTRL),A
        LD      A,D
        OUT     (IDE_A),A
        LD      A,E
        OUT     (IDE_C),A
        OR      IDE_WR_BIT
        OUT     (IDE_C),A
        LD      A,E
        OUT     (IDE_C),A
        XOR     A
        OUT     (IDE_C),A
        LD      A,IDE_RD_CFG
        OUT     (IDE_CTRL),A
        RET

;=============================================================================
; BANNER / STRINGS
;=============================================================================
PRINT_BANNER:
        CALL    PRINT_CRLF
        LD      HL,MSG_BANNER
        CALL    PRINT_STR
        LD      HL,MSG_PANEL
        CALL    PRINT_STR
        LD      A,(PANEL_BYTE)
        CALL    PRINT_HEX8
        LD      HL,MSG_CONSOLE
        CALL    PRINT_STR
        LD      A,(CONSOLE_SEL)
        OR      A
        JR      Z,BANNER_CIO
        CP      CONSOLE_SERIAL
        JR      Z,BANNER_SERIAL
        LD      HL,MSG_CON_MIO
        JR      BANNER_CON_PRINT
BANNER_CIO:
        LD      HL,MSG_CON_CIO
        JR      BANNER_CON_PRINT
BANNER_SERIAL:
        LD      HL,MSG_CON_SERIAL
BANNER_CON_PRINT:
        CALL    PRINT_STR
        RET

MSG_BANNER:
        DB      'IMSAI 8080 TARGET MONITOR 4K @ F000H',CR,LF,0
MSG_PANEL:
        DB      'PANEL FFH=',0
MSG_CONSOLE:
        DB      '  CONSOLE=',0
MSG_CON_CIO:
        DB      'CONSOLE I/O 00H/01H',CR,LF,0
MSG_CON_SERIAL:
        DB      'SERIAL I/O A A1H/A3H 38400 8N1',CR,LF,0
MSG_CON_MIO:
        DB      'IMSAI MIO 42H/43H 19200 8N1',CR,LF,0

MSG_AUTOBOOT:
        DB      'IDE/CF AUTO BOOT - PRESS ANY KEY TO CANCEL: ',0
MSG_CANCELLED:
        DB      CR,LF,'AUTO BOOT CANCELLED',0
MSG_PROMPT:
        DB      '-> ',0
MSG_ERROR:
        DB      ' ?',0
MSG_PASS:
        DB      ' PASS',0
MSG_FAIL:
        DB      ' FAIL @ ',0
MSG_MISMATCH:
        DB      CR,LF,'MISMATCH ',0

MSG_MENU1:
        DB      'B=Boot C=FDC+ D=Display F=Fill G=Goto H=Hardware J=RAMtest',CR,LF,0
MSG_MENU2:
        DB      'K=Menu M=Move P=IDE/CF Q=I/O T=Type V=Verify',CR,LF
        DB      'Syntax: D/F/J/T start,end  M/V start,end,dest  Q I,port  Q O,port,byte',0

MSG_BOOT_MENU:
        DB      'BOOT: [I] IDE/CF  [F] ALTAIR FDC+  [M] MONITOR : ',0
MSG_FDC_BOOT:
        DB      'BOOTING ALTAIR FDC+ WITH CDBL...',CR,LF,0
MSG_IDE_BOOT:
        DB      'BOOTING CP/M FROM IDE/CF...',CR,LF,0
MSG_IDE_NOT_READY:
        DB      'IDE/CF NOT READY',CR,LF,0
MSG_IDE_READ_ERROR:
        DB      'IDE/CF READ ERROR',CR,LF,0
MSG_IDE_BAD_LOADER:
        DB      'INVALID CPMLDR IMAGE',CR,LF,0

MSG_HW1:
        DB      'SYSTEM: NORTH STAR ZPB-A2 + FDC+ 60K/4K',CR,LF
        DB      'PANEL FFH=',0
MSG_HW2:
        DB      '  CONSOLE=',0
MSG_HW3:
        DB      'RAM 0000H-EFFFH  ROM F000H-FFFFH',CR,LF
        DB      'IDE/CF 30H-34H  FDC+ 08H-0AH  CDBL FF00H',CR,LF,0

; tools/build_image.py enforces that the assembled body ends before FF00H.
