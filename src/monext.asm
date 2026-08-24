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
; The approved 80-column panel artwork is too large to store literally in the
; remaining 4K ROM space, so it uses a tiny target-specific packing format:
;   00H       end of artwork
;   01H-1EH   output that many spaces
;   1FH       output CR/LF
;   20H-7EH   literal printable ASCII
;   80H-FFH   output '-' (token AND 7FH) times
;
; This keeps the docs/ ASCII template human-readable while preserving the exact
; 80-column display in ROM.
EXT_HEADER:
        LD      HL,IMSAI_HEADER_PACKED
HDR_NEXT:
        LD      A,(HL)
        INC     HL
        OR      A
        RET     Z
        CP      01FH
        JR      Z,HDR_NEWLINE
        BIT     7,A
        JR      NZ,HDR_DASH_RUN
        CP      SPACE
        JR      NC,HDR_LITERAL
        LD      B,A
        LD      A,SPACE
HDR_RUN:
        CALL    MON_CONOUT
        DJNZ    HDR_RUN
        JR      HDR_NEXT
HDR_DASH_RUN:
        AND     07FH
        LD      B,A
        LD      A,'-'
        JR      HDR_RUN
HDR_NEWLINE:
        CALL    PRINT_CRLF
        JR      HDR_NEXT
HDR_LITERAL:
        CALL    MON_CONOUT
        JR      HDR_NEXT

; Canonical artwork is docs/IMSAI_FRONT_PANEL_ASCII_TEMPLATE.md.
; Decompressed output is eleven 80-column lines plus CR/LF after each line.
IMSAI_HEADER_PACKED:
        DB      '+',0CEH,'+',01FH
        DB      '|',01H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'PROGRAMMED',018H,'I',01H,'M',01H,'S',01H,'A',01H,'I',03H,'8',01H,'0',01H,'8',01H,'0|',01FH
        DB      '|',01H,'7',02H,'6',02H,'5',02H,'4',02H,'3',02H,'2',02H,'1',02H,'0',02H,'OUTPUT',01BH,094H,'|',01FH
        DB      '|',01H,'MR',01H,'IN',01H,'M1',01H,'OT',01H,'HL',01H,'ST',01H,'WO',01H,'IA',0AH,'7',02H,'6',02H,'5',02H,'4',02H,'3',02H,'2',02H,'1',02H,'0',016H,'|',01FH
        DB      '|',01H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'STATUS',03H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'DATA',010H,'|',01FH
        DB      '|',019H,'BYTE',01DH,'BUS',011H,'|',01FH
        DB      '|',01H,'15',01H,'14',01H,'13',01H,'12',01H,'11',01H,'10',01H,'9',02H,'8',02H,'ADDRESS',02H,'7',02H,'6',02H,'5',02H,'4',02H,'3',02H,'2',02H,'1',02H,'0',01H,'ENABLED',01H,'RUN',01H,'WAIT',01H,'HOLD|',01FH
        DB      '|',01H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'BUS',06H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',02H,'o',06H,'o',04H,'o',04H,'o',04H,'o|',01FH
        DB      '|',01H,'ADDRESS',01H,'+',01H,'PROGRAM',01H,'INPUT',0AH,'ADDRESS',01H,'+',01H,'DATA',06H,'EXA',01H,'DEP',01H,'RST',01H,'RUN',01H,'STP',01H,'PWR',01H,'|',01FH
        DB      '|',01H,'[_][_][_][_][_][_][_][_]',04H,'[_][_][_][_][_][_][_][_]',02H,'[_]',01H,'[_]',01H,'[_]',01H,'[_]',01H,'[_]',01H,'[_]|',01FH
        DB      '+',0CEH,'+',01FH
        DB      00H

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
;
; This target has a fixed ROM window at F000H-FFFFH.  Never perform the
; complement/write RAM probe there: even though the FDC+ ROM socket normally
; holds /WE inactive, the monitor should not depend on that electrical detail.
CLASSIFY_PAGE:
        LD      L,0
        LD      A,H
        CP      0F0H
        JR      NC,CLASS_SCAN_START

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
        LD      (HL),A                  ; restore if possible
CLASS_SCAN_START:
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
