$NOLIST
$MODMAX10          
$LIST

PUBLIC Keypad
PUBLIC Configure_Keypad_Pins
PUBLIC Shift_Digits_Left
PUBLIC Shift_Digits_Right

; Reset vector – when MCU starts it jumps to main_code
CSEG at 0
    ljmp main_code        ; Jump to main program

; -------------------------------------------------
; Data Segment – reserve RAM for BCD digits & params
; -------------------------------------------------

DSEG at 30H
bcd:            ds 5      ; Reserve 5 bytes → stores 10 BCD digits (2 per byte)

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

; -------------------------------------------------
; Code Segment
; -------------------------------------------------

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
;   %0 = bcd byte
;   %1 = HEX low
;   %2 = HEX high
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


; -------------------------------------------------
; Display routine – show BCD number on HEX displays
; KEY3: 0 → show high digits, 1 → show low digits
; LEDRA.7: overflow indicator if bcd+3 or bcd+4 != 0
; -------------------------------------------------

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

    ; If KEY3 pressed (assuming active low) → show HIGH digits
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

; -------------------------------------------------
; Macro: Rotate Left through Carry
; -------------------------------------------------

MYRLC MAC
    mov a, %0
    rlc a
    mov %0, a
ENDMAC

; -------------------------------------------------
; Shift all BCD digits LEFT by 4 bits
; → makes room for new digit in LSD (R7)
; -------------------------------------------------

Shift_Digits_Left:
    mov R0, #4         ; Need 4 bit shifts (one nibble)

Shift_Digits_Left_L0:
    clr c              ; Clear carry before shift
    MYRLC(bcd+0)
    MYRLC(bcd+1)
    MYRLC(bcd+2)
    MYRLC(bcd+3)
    MYRLC(bcd+4)
    djnz R0, Shift_Digits_Left_L0

    ; Insert new digit from R7 into lowest nibble safely
    ; Keep upper nibble of bcd+0 unchanged
    anl bcd+0, #0F0h   ; clear lower nibble
    mov a, R7
    anl a, #0Fh        ; ensure only 0–F
    orl bcd+0, a
    ret

; -------------------------------------------------
; Macro: Rotate Right through Carry
; -------------------------------------------------

MYRRC MAC
    mov a, %0
    rrc a
    mov %0, a
ENDMAC

; -------------------------------------------------
; Shift digits RIGHT by 4 bits
; → used for BACKSPACE (delete last digit)
; -------------------------------------------------

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


; -------------------------------------------------
; 25 ms delay (software debounce)
; -------------------------------------------------

Wait25ms:
    mov R0, #15
L3: mov R1, #74
L2: mov R2, #250
L1: djnz R2, L1
    djnz R1, L2
    djnz R0, L3
    ret


; -------------------------------------------------
; Helper routines for parameter storage
; Each parameter value lives in bcd+0..bcd+1
; active_param: 0=A, 1=B, 2=C, 3=D
; -------------------------------------------------

; Save current BCD (bcd+0..bcd+1) into active parameter
Save_Current_BCD_Into_Param:
    mov a, active_param
    cjne a, #0, Save_NotA
    ; A: soak_temp
    mov soak_temp,   bcd+0
    mov soak_temp+1, bcd+1
    ret
Save_NotA:
    cjne a, #1, Save_NotB
    ; B: soak_time
    mov soak_time,   bcd+0
    mov soak_time+1, bcd+1
    ret
Save_NotB:
    cjne a, #2, Save_NotC
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

    mov a, active_param
    cjne a, #0, Load_NotA
    ; A: soak_temp
    mov bcd+0, soak_temp
    mov bcd+1, soak_temp+1
    ret
Load_NotA:
    cjne a, #1, Load_NotB
    ; B: soak_time
    mov bcd+0, soak_time
    mov bcd+1, soak_time+1
    ret
Load_NotB:
    cjne a, #2, Load_NotC
    ; C: reflow_temp
    mov bcd+0, reflow_temp
    mov bcd+1, reflow_temp+1
    ret
Load_NotC:
    ; D: reflow_time (default)
    mov bcd+0, reflow_time
    mov bcd+1, reflow_time+1
    ret


; -------------------------------------------------
; Macro: Check one keypad column
; If pressed → R7 = key value, C=1, jump to Key_Found
; %0 = column bit, %1 = key code (immediate)
; -------------------------------------------------

CHECK_COLUMN MAC
    jb %0, CHECK_COL_%M      ; if column=1 → no key here → skip
    mov R7, %1               ; store key code
    jnb %0, $                ; wait until key is released
    setb c                   ; mark "key found"
    sjmp Key_Found           ; classify key (digit vs mode)
CHECK_COL_%M:
ENDMAC


; -------------------------------------------------
; Configure GPIO directions for keypad
; -------------------------------------------------

Configure_Keypad_Pins:
    orl P1MOD, #0b_01010100  ; Rows as output
    orl P2MOD, #0b_00000001
    anl P2MOD, #0b_10101011  ; Columns as input
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

; -------------------------------------------------
; Keypad scanning routine
; Output:
;   C = 1 → numeric key pressed, code in R7 (0–9, maybe E/F)
;   C = 0 → no digit (no key, mode key, or backspace)
; -------------------------------------------------

Keypad:

    ; KEY1 acts as BACKSPACE / ERASE
    
    jb KEY.1, keypad_L0      ; if KEY1=1 (not pressed) → skip
    lcall Wait25ms
    jb KEY.1, keypad_L0      ; still high? → bounce, skip
    jnb KEY.1, $             ; wait for release (KEY1 low while pressed)
    lcall Shift_Digits_Right ; delete LSD for active parameter
    clr c                    ; no digit returned
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
    jnc Keypad_Debounce      ; if any column low → possible key
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


; -------------------------------------------------
; Default keypad layout
; -------------------------------------------------
; Mapping (default):
;   Row1: 1  2  3  A(0Ah)
;   Row2: 4  5  6  B(0Bh)
;   Row3: 7  8  9  C(0Ch)
;   Row4: E  0  F  D(0Dh)
; -------------------------------------------------

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

    ; If we reached here, no key found
    clr c
    ret


; -------------------------------------------------
; Rotated keypad layout (90° CCW)
; -------------------------------------------------

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

    ; If we reached here, no key found
    clr c
    ret


; -------------------------------------------------
; Key_Found:
;   R7 = key code (0–F), C = 1 when we get here.
;   A/B/C/D (0Ah–0Dh) → mode select, no digit
;   Others → numeric digit, C stays 1
; -------------------------------------------------

Key_Found:
    mov a, R7

    ; --- Mode A (soak temperature) ---
    cjne a, #0AH, Check_Mode_B
    lcall Save_Current_BCD_Into_Param
    mov active_param, #0       ; A: soak_temp
    lcall Load_Param_Into_BCD
    ; Optional: indicate mode with LEDs (e.g., LEDRB = active_param)
    ; mov a, active_param
    ; mov LEDRB, a
    clr c                      ; not a digit
    ret

Check_Mode_B:
    cjne a, #0BH, Check_Mode_C
    lcall Save_Current_BCD_Into_Param
    mov active_param, #1       ; B: soak_time
    lcall Load_Param_Into_BCD
    ; mov a, active_param
    ; mov LEDRB, a
    clr c
    ret

Check_Mode_C:
    cjne a, #0CH, Check_Mode_D
    lcall Save_Current_BCD_Into_Param
    mov active_param, #2       ; C: reflow_temp
    lcall Load_Param_Into_BCD
    ; mov a, active_param
    ; mov LEDRB, a
    clr c
    ret

Check_Mode_D:
    cjne a, #0DH, Not_Mode_Key
    lcall Save_Current_BCD_Into_Param
    mov active_param, #3       ; D: reflow_time
    lcall Load_Param_Into_BCD
    ; mov a, active_param
    ; mov LEDRB, a
    clr c
    ret

Not_Mode_Key:
    ; Not A/B/C/D → treat as numeric digit key
    ; R7 contains the digit code; C remains 1
    ret


; -------------------------------------------------
; MAIN PROGRAM
; -------------------------------------------------

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

    ; Clear parameter storage
    mov soak_temp,   a
    mov soak_temp+1, a
    mov soak_time,   a
    mov soak_time+1, a
    mov reflow_temp,   a
    mov reflow_temp+1, a
    mov reflow_time,   a
    mov reflow_time+1, a

    ; Start in mode A: soak temperature
    mov active_param, #0
    lcall Load_Param_Into_BCD

    lcall Configure_Keypad_Pins


; -------------------------------------------------
; Main loop
; -------------------------------------------------

forever:
    lcall Keypad       ; Scan keypad
    lcall Display      ; Update HEX displays (or later, LCD)
    jnc forever        ; If C=0 → no digit to insert (mode/backspace/none)

    lcall Shift_Digits_Left  ; If C=1 → numeric key; insert new digit from R7
    ljmp forever

end
