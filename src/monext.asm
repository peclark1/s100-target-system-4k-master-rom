;=============================================================================
; IMSAI 8080 TARGET SYSTEM - MONITOR EXTENSION
;
; Logical address: FBA0H
;
; Uses otherwise-free ROM above the native FDC+3712 module.  The first two
; entries are fixed so the compact core monitor can dispatch unknown commands
; here and print the IMSAI front-panel header without consuming F000H-F7FFH.
;
; Added/restored commands from John's monitor:
;   A  memory map (R=RAM, P=ROM/non-writable, .=empty FF page)
;   E  console echo test (^C/^Z exits)
;   S  interactive examine/substitute memory
;   Z  find highest writable RAM
;=============================================================================

        ORG     0FBA0H

MON_CONIN       EQU     0F003H
MON_CONOUT      EQU     0F006H
MONITOR         EQU     0F00CH

CR              EQU     0DH
LF              EQU     0AH
SPACE           EQU     20H
ESC             EQU     1BH
CTRL_C          EQU     03H
CTRL_Z          EQU     1AH

; Fixed extension entry points.
        JP      EXT_DISPATCH            ; FBA0H
        JP      EXT_HEADER              ; FBA3H

;=============================================================================
; Extension command dispatcher
;=============================================================================
EXT_DISPATCH:
        CP      'A'
        JP      Z,CMD_MEMMAP
        CP      'E'
        JP      Z,CMD_ECHO
        CP      'S'
        JP      Z,CMD_SUBSTITUTE
        CP      'Z'
        JP      Z,CMD_RAMTOP

        LD      A,SPACE
        CALL    MON_CONOUT
        LD      A,'?'
        CALL    MON_CONOUT
        JP      MONITOR

;=============================================================================
; IMSAI front-panel sign-on header
;=============================================================================
EXT_HEADER:
        LD      HL,IMSAI_HEADER
        JP      PRINT_STR

; Every line is exactly 66 columns wide, including the two border characters.
IMSAI_HEADER:
        DB      '+----------------------------------------------------------------+',CR,LF
        DB      '|  o o o o o o o o       I M S A I   8 0 8 0                     |',CR,LF
        DB      '|  o o o o o o o o    o o o o o o o o o o o o o o o o            |',CR,LF
        DB      '|  / / / / / / / /    / / / / / / / /    [ RUN ] [ STOP ]        |',CR,LF
        DB      '+----------------------------------------------------------------+',CR,LF,0

;=============================================================================
; A - memory map
;
; One character represents each 256-byte page.  Sixteen characters therefore
; represent 4K, giving sixteen compact lines for the full 64K address space.
; The RAM test is nondestructive: the original first byte is restored.
;=============================================================================
CMD_MEMMAP:
        CALL    PRINT_CRLF
        LD      HL,MSG_MAP_KEY
        CALL    PRINT_STR
        LD      HL,0000H

MAP_LINE:
        LD      L,0
        CALL    PRINT_CRLF
        CALL    PRINT_HEX16
        LD      A,':'
        CALL    MON_CONOUT
        LD      A,SPACE
        CALL    MON_CONOUT
        LD      B,16
MAP_PAGE:
        PUSH    BC
        CALL    CLASSIFY_PAGE
        CALL    MON_CONOUT
        POP     BC
        INC     H
        DJNZ    MAP_PAGE
        LD      A,H
        OR      A
        JR      NZ,MAP_LINE
        JP      MONITOR

; Return A='R' for writable RAM, A='P' for non-writable data (ROM/PROM),
; or A='.' when all 256 bytes read FFH.  H (page number) is preserved.
CLASSIFY_PAGE:
        LD      L,0
        LD      A,(HL)
        LD      E,A                     ; save original first byte
        CPL
        LD      (HL),A
        CP      (HL)
        JR      NZ,CLASS_NOT_RAM
        LD      A,E
        LD      (HL),A                  ; restore original
        CP      (HL)
        JR      NZ,CLASS_NOT_RAM
        LD      A,'R'
        RET

CLASS_NOT_RAM:
        LD      A,E
        LD      (HL),A                  ; harmless for ROM; restore if possible
        LD      L,0
CLASS_SCAN:
        LD      A,(HL)
        CP      0FFH
        JR      NZ,CLASS_PROM
        INC     L
        JR      NZ,CLASS_SCAN
        LD      A,'.'
        RET
CLASS_PROM:
        LD      A,'P'
        RET

;=============================================================================
; Z - find highest writable RAM
;=============================================================================
CMD_RAMTOP:
        LD      H,0FFH
RAMTOP_SCAN:
        CALL    CLASSIFY_PAGE
        CP      'R'
        JR      Z,RAMTOP_FOUND
        LD      A,H
        OR      A
        JR      Z,RAMTOP_NONE
        DEC     H
        JR      RAMTOP_SCAN

RAMTOP_FOUND:
        LD      A,H
        LD      D,A                     ; preserve page across message pointer
        CALL    PRINT_CRLF
        LD      HL,MSG_RAMTOP
        CALL    PRINT_STR
        LD      H,D
        LD      L,0FFH
        CALL    PRINT_HEX16
        LD      A,'H'
        CALL    MON_CONOUT
        JP      MONITOR

RAMTOP_NONE:
        CALL    PRINT_CRLF
        LD      HL,MSG_NO_RAM
        CALL    PRINT_STR
        JP      MONITOR

;=============================================================================
; E - console echo test
;=============================================================================
CMD_ECHO:
        CALL    PRINT_CRLF
        LD      HL,MSG_ECHO
        CALL    PRINT_STR
ECHO_LOOP:
        CALL    MON_CONIN
        CP      CTRL_C
        JP      Z,MONITOR
        CP      CTRL_Z
        JP      Z,MONITOR
        CALL    MON_CONOUT
        JR      ECHO_LOOP

;=============================================================================
; S - interactive memory examine/substitute
;
; Syntax: S address
; Each line shows "ADDR: old >".  Enter a hex byte then SPACE/comma/CR to
; replace and advance.  A bare delimiter advances without changing memory.
; '-' backs up one byte.  ESC, ^C, or ^Z exits to the monitor.
;=============================================================================
CMD_SUBSTITUTE:
        CALL    GET_HEX16
SUB_LOOP:
        CALL    PRINT_CRLF
        CALL    PRINT_HEX16
        LD      A,':'
        CALL    MON_CONOUT
        LD      A,SPACE
        CALL    MON_CONOUT
        LD      A,(HL)
        CALL    PRINT_HEX8
        LD      A,SPACE
        CALL    MON_CONOUT
        LD      A,'>'
        CALL    MON_CONOUT
        LD      A,SPACE
        CALL    MON_CONOUT

        LD      B,0                     ; replacement digit count
        LD      D,0                     ; replacement value
SUB_INPUT:
        CALL    MON_CONIN
        CP      CTRL_C
        JP      Z,MONITOR
        CP      CTRL_Z
        JP      Z,MONITOR
        CP      ESC
        JP      Z,MONITOR
        CP      '-'
        JR      Z,SUB_PREV
        CP      SPACE
        JR      Z,SUB_DELIM_ECHO
        CP      ','
        JR      Z,SUB_DELIM_ECHO
        CP      CR
        JR      Z,SUB_DELIM
        CALL    TO_UPPER
        PUSH    AF
        CALL    MON_CONOUT
        POP     AF
        CALL    HEX_VALUE
        JR      C,SUB_INPUT
        LD      E,A
        LD      A,D
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        OR      E
        LD      D,A
        INC     B
        JR      SUB_INPUT

SUB_PREV:
        CALL    MON_CONOUT              ; echo '-'
        DEC     HL
        JR      SUB_LOOP

SUB_DELIM_ECHO:
        PUSH    AF
        CALL    MON_CONOUT
        POP     AF
SUB_DELIM:
        LD      A,B
        OR      A
        JR      Z,SUB_NEXT
        LD      A,D
        LD      (HL),A
SUB_NEXT:
        INC     HL
        JR      SUB_LOOP

;=============================================================================
; Compact local console/hex helpers
;=============================================================================
PRINT_STR:
        LD      A,(HL)
        OR      A
        RET     Z
        INC     HL
        CALL    MON_CONOUT
        JR      PRINT_STR

PRINT_CRLF:
        LD      A,CR
        CALL    MON_CONOUT
        LD      A,LF
        JP      MON_CONOUT

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
        JP      MON_CONOUT

PRINT_HEX16:
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

HEX_VALUE:
        SUB     '0'
        JR      C,HEX_BAD
        CP      10
        JR      C,HEX_GOOD
        SUB     7
        CP      10
        JR      C,HEX_BAD
        CP      16
        JR      NC,HEX_BAD
HEX_GOOD:
        OR      A
        RET
HEX_BAD:
        SCF
        RET

GET_HEX16:
        LD      HL,0
        LD      B,0
GH_LOOP:
        CALL    MON_CONIN
        CP      CTRL_C
        JP      Z,MONITOR
        CP      CTRL_Z
        JP      Z,MONITOR
        CP      ESC
        JP      Z,MONITOR
        CALL    TO_UPPER
        CP      SPACE
        JR      Z,GH_DELIM_ECHO
        CP      ','
        JR      Z,GH_DELIM_ECHO
        CP      CR
        JR      Z,GH_DELIM
        PUSH    AF
        CALL    MON_CONOUT
        POP     AF
        CALL    HEX_VALUE
        JR      C,GH_LOOP
        LD      C,A
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      A,L
        OR      C
        LD      L,A
        INC     B
        JR      GH_LOOP
GH_DELIM_ECHO:
        PUSH    AF
        CALL    MON_CONOUT
        POP     AF
GH_DELIM:
        LD      A,B
        OR      A
        JR      Z,GH_LOOP
        RET

MSG_MAP_KEY:
        DB      'MAP: R=RAM P=ROM .=EMPTY',0
MSG_ECHO:
        DB      'ECHO - ^C OR ^Z TO EXIT',CR,LF,0
MSG_RAMTOP:
        DB      'RAM TOP: ',0
MSG_NO_RAM:
        DB      'NO WRITABLE RAM FOUND',0

        END
