$MODMAX10              

; Reset vector – when MCU starts it jumps to main_code
CSEG at 0
    ljmp main_code        ; Jump to main program

; Data Segment – reserve RAM for BCD digits

DSEG at 30H
bcd:    ds 5              ; Reserve 5 bytes → stores 10 BCD digits (2 per byte)

; Code Segment

CSEG

; Lookup table for 7-segment display patterns (common anode)
; Index 0–F → segment pattern

myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99        ; digits 0–4
    DB 0x92, 0x82, 0xF8, 0x80, 0x90        ; digits 5–9
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E  ; A–F

;---------------------------------------------------------
; Macro: showBCD
; Input : one byte containing two BCD digits
; Output: two 7-seg displays
;---------------------------------------------------------

showBCD MAC
    ; ---- Display lower nibble (LSD) ----
    mov A, %0          ; Load BCD byte
    anl a, #0fh        ; Keep lower 4 bits
    movc A, @A+dptr    ; Convert using LUT
    mov %1, A          ; Output to first HEX display

    ; ---- Display upper nibble (MSD) ----
    mov A, %0
    swap a             ; Swap nibbles
    anl a, #0fh
    movc A, @A+dptr
    mov %2, A          ; Output to second HEX display
ENDMAC


; Display routine – show BCD number on HEX displays

Display:
    mov dptr, #myLUT   ; Point to lookup table

    ; If digits 10–7 (bcd+3 and bcd+4) are NOT zero
    ; → turn ON LEDR7 as overflow indicator

    mov a, bcd+3
    orl a, bcd+4
    jz Display_L1
    setb LEDRA.7       ; Alert LED on
    sjmp Display_L2
Display_L1:
    clr LEDRA.7        ; Alert LED off
Display_L2:

    ; If KEY3 pressed → show HIGH digits (most significant)
    ; Otherwise show LOW digits

    jnb key.3, Display_high_digits

    ; Show lower 6 digits
    showBCD(bcd+0, HEX0, HEX1)
    showBCD(bcd+1, HEX2, HEX3)
    showBCD(bcd+2, HEX4, HEX5)
    sjmp Display_end

Display_high_digits:
    ; Show upper 4 digits
    showBCD(bcd+3, HEX0, HEX1)
    showBCD(bcd+4, HEX2, HEX3)

    ; Blank remaining displays
    mov HEX4, #0xff
    mov HEX5, #0xff

Display_end:
    ret

; Macro: Rotate Left through Carry
MYRLC MAC
    mov a, %0
    rlc a
    mov %0, a
ENDMAC


; Shift all BCD digits LEFT by 4 bits
; → makes room for new digit in LSD

Shift_Digits_Left:
    mov R0, #4         ; Need 4 bit shifts

Shift_Digits_Left_L0:
    clr c              ; Clear carry before shift
    MYRLC(bcd+0)
    MYRLC(bcd+1)
    MYRLC(bcd+2)
    MYRLC(bcd+3)
    MYRLC(bcd+4)
    djnz R0, Shift_Digits_Left_L0

    ; Insert new digit from R7 into lowest nibble
    mov a, R7
    orl a, bcd+0
    mov bcd+0, a
    ret

; Macro: Rotate Right through Carry

MYRRC MAC
    mov a, %0
    rrc a
    mov %0, a
ENDMAC


; Shift digits RIGHT by 4 bits
; → used for BACKSPACE (delete last digit)

Shift_Digits_Right:
    mov R0, #4

Shift_Digits_Right_L0:
    clr c
    MYRRC(bcd+4)
    MYRRC(bcd+3)
    MYRRC(bcd+2)
    MYRRC(bcd+1)
    MYRRC(bcd+0)
    djnz R0, Shift_Digits_Right_L0
    ret


; 25 ms delay (software debounce)

Wait25ms:
    mov R0, #15
L3: mov R1, #74
L2: mov R2, #250
L1: djnz R2, L1
    djnz R1, L2
    djnz R0, L3
    ret


; Macro: Check one keypad column
; If pressed → return code in R7, set Carry

CHECK_COLUMN MAC
    jb %0, CHECK_COL_%M
    mov R7, %1         ; Key value
    jnb %0, $          ; Wait release
    setb c             ; Indicate key found
    ret
CHECK_COL_%M:
ENDMAC


; Configure GPIO directions for keypad

Configure_Keypad_Pins:
    orl P1MOD, #0b_01010100 ; Rows as output
    orl P2MOD, #0b_00000001
    anl P2MOD, #0b_10101011 ; Columns as input
    anl P3MOD, #0b_11111110
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

; Keypad scanning routine
; Output:
;   C = 1 → key pressed, code in R7
;   C = 0 → no key

Keypad:

    ; KEY1 acts as BACKSPACE / ERASE
    
    jb KEY.1, keypad_L0
    lcall Wait25ms
    jb KEY.1, keypad_L0
    jnb KEY.1, $
    lcall Shift_Digits_Right
    clr c
    ret

keypad_L0:
    
    ; Drive all rows LOW → check if any column LOW
    
    clr ROW1
    clr ROW2
    clr ROW3
    clr ROW4

    mov c, COL1
    anl c, COL2
    anl c, COL3
    anl c, COL4
    jnc Keypad_Debounce
    clr c
    ret

Keypad_Debounce:
    ; Wait and check again to avoid bouncing
    lcall Wait25ms

    mov c, COL1
    anl c, COL2
    anl c, COL3
    anl c, COL4
    jnc Keypad_Key_Code
    clr c
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


; Default keypad layout

keypad_default:

    clr ROW1
    CHECK_COLUMN(COL1, #01H)
    CHECK_COLUMN(COL2, #02H)
    CHECK_COLUMN(COL3, #03H)
    CHECK_COLUMN(COL4, #0AH)
    setb ROW1

    clr ROW2
    CHECK_COLUMN(COL1, #04H)
    CHECK_COLUMN(COL2, #05H)
    CHECK_COLUMN(COL3, #06H)
    CHECK_COLUMN(COL4, #0BH)
    setb ROW2

    clr ROW3
    CHECK_COLUMN(COL1, #07H)
    CHECK_COLUMN(COL2, #08H)
    CHECK_COLUMN(COL3, #09H)
    CHECK_COLUMN(COL4, #0CH)
    setb ROW3

    clr ROW4
    CHECK_COLUMN(COL1, #0EH)
    CHECK_COLUMN(COL2, #00H)
    CHECK_COLUMN(COL3, #0FH)
    CHECK_COLUMN(COL4, #0DH)
    setb ROW4

    clr c
    ret


; Rotated keypad layout (90° CCW)

keypad_90deg:
    clr ROW1
    CHECK_COLUMN(COL1, #0AH)
    CHECK_COLUMN(COL2, #0BH)
    CHECK_COLUMN(COL3, #0CH)
    CHECK_COLUMN(COL4, #0DH)
    setb ROW1

    clr ROW2
    CHECK_COLUMN(COL1, #03H)
    CHECK_COLUMN(COL2, #06H)
    CHECK_COLUMN(COL3, #09H)
    CHECK_COLUMN(COL4, #0FH)
    setb ROW2

    clr ROW3
    CHECK_COLUMN(COL1, #02H)
    CHECK_COLUMN(COL2, #05H)
    CHECK_COLUMN(COL3, #08H)
    CHECK_COLUMN(COL4, #00H)
    setb ROW3

    clr ROW4
    CHECK_COLUMN(COL1, #01H)
    CHECK_COLUMN(COL2, #04H)
    CHECK_COLUMN(COL3, #07H)
    CHECK_COLUMN(COL4, #0EH)
    setb ROW4

    clr c
    ret


; MAIN PROGRAM

main_code:
    mov SP, #7FH       ; Initialize stack pointer

    clr a
    mov LEDRA, a       ; Clear LEDs
    mov LEDRB, a

    ; Clear all BCD digits
    mov bcd+0, a
    mov bcd+1, a
    mov bcd+2, a
    mov bcd+3, a
    mov bcd+4, a

    lcall Configure_Keypad_Pins


; Main loop

forever:
    lcall Keypad       ; Scan keypad
    lcall Display      ; Update HEX displays
    jnc forever        ; If no key → loop

    lcall Shift_Digits_Left  ; Insert new digit
    ljmp forever

end
