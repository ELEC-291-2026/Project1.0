$NOLIST
$MODMAX10
$LIST

;--------------------------------------------------
; Reset vector - when MCU starts it jumps to main_code
;--------------------------------------------------
CSEG at 0
    ljmp main_code        ; Jump to main program

;--------------------------------------------------
; Data Segment - reserve RAM for BCD digits & params
;--------------------------------------------------

DSEG at 30H
bcd:            ds 5      ; 5 bytes = 10 BCD digits (2 per byte)

; Reflow parameters, each stored as 4 BCD digits (2 bytes)
; A: Soak temperature
; B: Soak time
; C: Reflow temperature
; D: Reflow time

soak_temp:      ds 2      ; mode A
soak_time:      ds 2      ; mode B
reflow_temp:    ds 2      ; mode C
reflow_time:    ds 2      ; mode D

active_param:   ds 1      ; 0 = A, 1 = B, 2 = C, 3 = D

;--------------------------------------------------
; Code Segment
;--------------------------------------------------

CSEG

;--------------------------------------------------
; Lookup table for 7-segment display patterns (common anode)
; Index 0-F = segment pattern
;--------------------------------------------------

myLUT:
    DB 0C0h, 0F9h, 0A4h, 0B0h, 099h        ; digits 0-4
    DB 092h, 082h, 0F8h, 080h, 090h        ; digits 5-9
    DB 088h, 083h, 0C6h, 0A1h, 086h, 08Eh  ; A-F

;--------------------------------------------------
; Macro: showBCD
; Input : one byte containing two BCD digits
; Output: two 7-seg displays
;   %0 = bcd byte
;   %1 = HEX low
;   %2 = HEX high
;--------------------------------------------------

showBCD MAC
    ; ---- Display lower nibble (LSD) ----
    mov  A, %0           ; Load BCD byte
    anl  A, #0Fh         ; Keep lower 4 bits
    movc A, @A+dptr      ; Convert using LUT
    mov  %1, A           ; Output to first HEX display

    ; ---- Display upper nibble (MSD) ----
    mov  A, %0
    swap A               ; Swap nibbles
    anl  A, #0Fh
    movc A, @A+dptr
    mov  %2, A           ; Output to second HEX display
ENDMAC


;--------------------------------------------------
; Display routine - show BCD number on HEX displays
; KEY3: 0 = show high digits, 1 = show low digits
; LEDRA.7: overflow indicator if bcd+3 or bcd+4 != 0
;--------------------------------------------------

Display:
    mov dptr, #myLUT     ; Point to lookup table

    ; If digits 10-7 (bcd+3 and bcd+4) are NOT zero
    ; turn ON LEDRA.7 as overflow indicator

    mov A, bcd+3
    orl A, bcd+4
    jz  Display_L1
    setb LEDRA.7         ; Alert LED on
    sjmp Display_L2
Display_L1:
    clr LEDRA.7          ; Alert LED off
Display_L2:

    ; If KEY3 pressed (assuming active low) show HIGH digits
    ; Otherwise show LOW digits

    jnb KEY.3, Display_high_digits

    ; Show lower 6 digits
    showBCD (bcd+0, HEX0, HEX1)
    showBCD (bcd+1, HEX2, HEX3)
    showBCD (bcd+2, HEX4, HEX5)
    sjmp Display_end

Display_high_digits:
    ; Show upper 4 digits
    showBCD (bcd+3, HEX0, HEX1)
    showBCD (bcd+4, HEX2, HEX3)

    ; Blank remaining displays
    mov HEX4, #0FFh
    mov HEX5, #0FFh

Display_end:
    ret

;--------------------------------------------------
; Macro: Rotate Left through Carry
;--------------------------------------------------

MYRLC MAC
    mov A, %0
    rlc A
    mov %0, A
ENDMAC

;--------------------------------------------------
; Shift all BCD digits LEFT by 4 bits
; Makes room for new digit in LSD (R7)
;--------------------------------------------------

Shift_Digits_Left:
    mov R0, #4           ; 4 bit shifts (one nibble)

Shift_Digits_Left_L0:
    clr C                ; Clear carry before shift
    MYRLC (bcd+0)
    MYRLC (bcd+1)
    MYRLC (bcd+2)
    MYRLC (bcd+3)
    MYRLC (bcd+4)
    djnz R0, Shift_Digits_Left_L0

    ; Insert new digit from R7 into lowest nibble safely
    ; Keep upper nibble of bcd+0 unchanged
    anl  bcd+0, #0F0h    ; clear lower nibble
    mov  A, R7
    anl  A, #0Fh         ; ensure only 0-F
    orl  bcd+0, A
    ret

;--------------------------------------------------
; Macro: Rotate Right through Carry
;--------------------------------------------------

MYRRC MAC
    mov A, %0
    rrc A
    mov %0, A
ENDMAC

;--------------------------------------------------
; Shift digits RIGHT by 4 bits
; Used for BACKSPACE (delete last digit)
;--------------------------------------------------

Shift_Digits_Right:
    mov R0, #4

Shift_Digits_Right_L0:
    clr C
    MYRRC (bcd+4)
    MYRRC (bcd+3)
    MYRRC (bcd+2)
    MYRRC (bcd+1)
    MYRRC (bcd+0)
    djnz R0, Shift_Digits_Right_L0
    ret


;--------------------------------------------------
; 25 ms delay (software debounce)
;--------------------------------------------------

Wait25ms:
    mov R0, #15
L3: mov R1, #74
L2: mov R2, #250
L1: djnz R2, L1
    djnz R1, L2
    djnz R0, L3
    ret


;--------------------------------------------------
; Helper routines for parameter storage
; Each parameter value lives in bcd+0..bcd+1
; active_param: 0=A, 1=B, 2=C, 3=D
;--------------------------------------------------

; Save current BCD (bcd+0..bcd+1) into active parameter
Save_Current_BCD_Into_Param:
    mov A, active_param
    cjne A, #0, Save_NotA
    ; A: soak_temp
    mov soak_temp,   bcd+0
    mov soak_temp+1, bcd+1
    ret
Save_NotA:
    cjne A, #1, Save_NotB
    ; B: soak_time
    mov soak_time,   bcd+0
    mov soak_time+1, bcd+1
    ret
Save_NotB:
    cjne A, #2, Save_NotC
    ; C: reflow_temp
    mov reflow_temp,   bcd+0
    mov reflow_temp+1, bcd+1
    ret
Save_NotC:
    ; D: reflow_time (default case)
    mov reflow_time,   bcd+0
    mov reflow_time+1, bcd+1
    ret


; Load active parameter into BCD (bcd+0..bcd+1)
; Clear the higher digits.
Load_Param_Into_BCD:
    mov bcd+2, #00h
    mov bcd+3, #00h
    mov bcd+4, #00h

    mov A, active_param
    cjne A, #0, Load_NotA
    ; A: soak_temp
    mov bcd+0, soak_temp
    mov bcd+1, soak_temp+1
    ret
Load_NotA:
    cjne A, #1, Load_NotB
    ; B: soak_time
    mov bcd+0, soak_time
    mov bcd+1, soak_time+1
    ret
Load_NotB:
    cjne A, #2, Load_NotC
    ; C: reflow_temp
    mov bcd+0, reflow_temp
    mov bcd+1, reflow_temp+1
    ret
Load_NotC:
    ; D: reflow_time (default)
    mov bcd+0, reflow_time
    mov bcd+1, reflow_time+1
    ret


;--------------------------------------------------
; Macro: Check one keypad column
; If pressed -> R7 = key value, C=1, jump to Key_Found
; %0 = column bit, %1 = key code (immediate)
;--------------------------------------------------

CHECK_COLUMN MAC
    jb  %0, CHECK_COL_%M     ; if column=1 -> no key here -> skip
    mov R7, %1               ; store key code
    jnb %0, $                ; wait until key is released
    setb C                   ; mark "key found"
    ljmp Key_Found           ; use long jump instead of short
CHECK_COL_%M:
ENDMAC


;--------------------------------------------------
; Configure GPIO directions for keypad
;--------------------------------------------------

Configure_Keypad_Pins:
    orl P1MOD, #01010100b    ; Rows as output on P1
    orl P2MOD, #00000001b
    anl P2MOD, #10101011b    ; Columns as input on P2
    anl P3MOD, #11111110b    ; Column on P3.0 input
    ret

; Pin definitions for keypad
ROW1 EQU P1.2
ROW2 EQU P1.4
ROW3 EQU P1.6
ROW4 EQU P2.0

COL1 EQU P2.2
COL2 EQU P2.4
COL3 EQU P2.6
COL4 EQU P3.0

;--------------------------------------------------
; Keypad scanning routine
; Output:
;   C = 1 -> numeric key pressed, code in R7 (0-9, maybe E/F)
;   C = 0 -> no digit (no key, mode key, or backspace)
;--------------------------------------------------

Keypad:

    ; KEY1 acts as BACKSPACE / ERASE

    jb  KEY.1, keypad_L0     ; if KEY1=1 (not pressed) -> skip
    lcall Wait25ms
    jb  KEY.1, keypad_L0     ; if bounced back high, skip
    jnb KEY.1, $             ; wait for release (KEY1 low while pressed)
    lcall Shift_Digits_Right ; delete LSD for active parameter
    clr C                    ; no digit returned
    ret

keypad_L0:

    ; Drive all rows LOW - check if any column LOW

    clr ROW1
    clr ROW2
    clr ROW3
    clr ROW4

    mov C, COL1
    anl C, COL2
    anl C, COL3
    anl C, COL4
    jnc Keypad_Debounce      ; if any column low -> possible key
    clr C
    ret

Keypad_Debounce:
    ; Wait and check again to avoid bouncing
    lcall Wait25ms

    mov C, COL1
    anl C, COL2
    anl C, COL3
    anl C, COL4
    jnc Keypad_Key_Code
    clr C
    ret

Keypad_Key_Code:
    ; Prepare to scan each row individually
    setb ROW1
    setb ROW2
    setb ROW3
    setb ROW4

    ; SW0 selects layout orientation
    jnb SWA.0, keypad_default
    ljmp keypad_90deg


;--------------------------------------------------
; Default keypad layout
;--------------------------------------------------
; Mapping (default):
;   Row1: 1  2  3  A (0Ah)
;   Row2: 4  5  6  B (0Bh)
;   Row3: 7  8  9  C (0Ch)
;   Row4: *  0  #  D (0Eh,00h,0Fh,0Dh)
;--------------------------------------------------

keypad_default:

    clr ROW1
    CHECK_COLUMN (COL1, #01h)
    CHECK_COLUMN (COL2, #02h)
    CHECK_COLUMN (COL3, #03h)
    CHECK_COLUMN (COL4, #0Ah)
    setb ROW1

    clr ROW2
    CHECK_COLUMN (COL1, #04h)
    CHECK_COLUMN (COL2, #05h)
    CHECK_COLUMN (COL3, #06h)
    CHECK_COLUMN (COL4, #0Bh)
    setb ROW2

    clr ROW3
    CHECK_COLUMN (COL1, #07h)
    CHECK_COLUMN (COL2, #08h)
    CHECK_COLUMN (COL3, #09h)
    CHECK_COLUMN (COL4, #0Ch)
    setb ROW3

    clr ROW4
    CHECK_COLUMN (COL1, #0Eh) ; '*' delete
    CHECK_COLUMN (COL2, #00h) ; '0'
    CHECK_COLUMN (COL3, #0Fh) ; '#' clear
    CHECK_COLUMN (COL4, #0Dh) ; 'D'
    setb ROW4

    ; If we reached here, no key found
    clr C
    ret


;--------------------------------------------------
; Rotated keypad layout (90 degrees CCW)
;--------------------------------------------------

keypad_90deg:
    clr ROW1
    CHECK_COLUMN (COL1, #0Ah)
    CHECK_COLUMN (COL2, #0Bh)
    CHECK_COLUMN (COL3, #0Ch)
    CHECK_COLUMN (COL4, #0Dh)
    setb ROW1

    clr ROW2
    CHECK_COLUMN (COL1, #03h)
    CHECK_COLUMN (COL2, #06h)
    CHECK_COLUMN (COL3, #09h)
    CHECK_COLUMN (COL4, #0Fh)
    setb ROW2

    clr ROW3
    CHECK_COLUMN (COL1, #02h)
    CHECK_COLUMN (COL2, #05h)
    CHECK_COLUMN (COL3, #08h)
    CHECK_COLUMN (COL4, #00h)
    setb ROW3

    clr ROW4
    CHECK_COLUMN (COL1, #01h)
    CHECK_COLUMN (COL2, #04h)
    CHECK_COLUMN (COL3, #07h)
    CHECK_COLUMN (COL4, #0Eh)
    setb ROW4

    ; If we reached here, no key found
    clr C
    ret


;--------------------------------------------------
; Key_Found:
;   R7 = key code (0-F), C = 1 when we get here.
;   A/B/C/D (0Ah-0Dh) -> mode select
;   * (0Eh)           -> delete / backspace one digit
;   # (0Fh)           -> clear all digits
;   others (0-9, maybe E/F) -> digit
;--------------------------------------------------

Key_Found:
    mov A, R7

    ; --- Mode A (soak temperature) ---
    cjne A, #0Ah, KF_CheckB
    lcall Save_Current_BCD_Into_Param
    mov   active_param, #0       ; A: soak_temp
    lcall Load_Param_Into_BCD
    clr C                        ; do not treat as digit
    ret

KF_CheckB:
    ; --- Mode B (soak time) ---
    cjne A, #0Bh, KF_CheckC
    lcall Save_Current_BCD_Into_Param
    mov   active_param, #1       ; B: soak_time
    lcall Load_Param_Into_BCD
    clr C
    ret

KF_CheckC:
    ; --- Mode C (reflow temperature) ---
    cjne A, #0Ch, KF_CheckD
    lcall Save_Current_BCD_Into_Param
    mov   active_param, #2       ; C: reflow_temp
    lcall Load_Param_Into_BCD
    clr C
    ret

KF_CheckD:
    ; --- Mode D (reflow time) ---
    cjne A, #0Dh, KF_CheckStar
    lcall Save_Current_BCD_Into_Param
    mov   active_param, #3       ; D: reflow_time
    lcall Load_Param_Into_BCD
    clr C
    ret

KF_CheckStar:
    ; --- '*' key (code 0Eh) -> delete / backspace ---
    cjne A, #0Eh, KF_CheckHash
    ; Backspace = shift digits right by 1 digit
    lcall Shift_Digits_Right
    clr C                        ; no new digit for main loop
    ret

KF_CheckHash:
    ; --- '#' key (code 0Fh) -> clear ---
    cjne A, #0Fh, KF_Digit
    ; Clear all BCD digits for current parameter
    clr A
    mov bcd+0, A
    mov bcd+1, A
    mov bcd+2, A
    mov bcd+3, A
    mov bcd+4, A
    clr C                        ; no digit to insert
    ret

KF_Digit:
    ; Not A/B/C/D/*/# -> treat as numeric digit key
    ; R7 holds the digit, Carry = 1 -> main loop will append it
    ret


;--------------------------------------------------
; MAIN PROGRAM
;--------------------------------------------------

main_code:
    mov SP, #7Fh        ; Initialize stack pointer

    clr A
    mov LEDRA, A        ; Clear LEDs
    mov LEDRB, A

    ; Clear all BCD digits
    mov bcd+0, A
    mov bcd+1, A
    mov bcd+2, A
    mov bcd+3, A
    mov bcd+4, A

    ; Clear parameter storage
    mov soak_temp,   A
    mov soak_temp+1, A
    mov soak_time,   A
    mov soak_time+1, A
    mov reflow_temp,   A
    mov reflow_temp+1, A
    mov reflow_time,   A
    mov reflow_time+1, A

    ; Start in mode A: soak temperature
    mov active_param, #0
    lcall Load_Param_Into_BCD

    lcall Configure_Keypad_Pins


;--------------------------------------------------
; Main loop
;--------------------------------------------------

forever:
    lcall Keypad        ; Scan keypad
    lcall Display       ; Update HEX displays (or later, LCD)
    jnc  forever        ; If C=0 -> no digit to insert (mode/backspace/clear/none)

    lcall Shift_Digits_Left  ; If C=1 -> numeric key; insert new digit from R7
    ljmp forever

end
