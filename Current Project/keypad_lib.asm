
$NOLIST
$LIST

IFNDEF _KEYPAD_LIB_
_KEYPAD_LIB_ EQU 1
CSEG
; -----------------------------
; Lookup table for 7-seg digits
; -----------------------------
myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99        ; digits 0â€“4
    DB 0x92, 0x82, 0xF8, 0x80, 0x90        ; digits 5â€“9
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E  ; Aâ€“F

;---------------------------------------------------------
; Macro: showBCD
; %0 = bcd byte
; %1 = HEX low
; %2 = HEX high
;---------------------------------------------------------
showBCD MAC
    mov A, %0          ; Load BCD byte
    anl a, #0fh        ; Keep lower 4 bits
    movc A, @A+dptr    ; Convert using LUT
    mov %1, A          ; Output to first HEX display

    mov A, %0
    swap a             ; Swap nibbles
    anl a, #0fh
    movc A, @A+dptr
    mov %2, A          ; Output to second HEX display
ENDMAC


; -------------------------------------------------
; Display routine â€“ show BCD number on HEX displays
; Uses global: bcd[0..4]
; KEY3: 0 â†’ show high digits, 1 â†’ show low digits
; LEDRA.7: overflow indicator if bcd+3 or bcd+4 != 0
; -------------------------------------------------

Display:
    mov dptr, #myLUT   ; Point to lookup table

    ; Overflow check on high digits
    mov a, bcd+3
    orl a, bcd+4
    jz Display_L1
    setb LEDRA.7
    sjmp Display_L2
Display_L1:
    clr LEDRA.7
Display_L2:

    ; If KEY3 pressed (active low) â†’ show HIGH digits
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
    mov HEX4, #0xff
    mov HEX5, #0xff

Display_end:
    ret

; -------------------------------------------------
; Rotate Left through Carry macro
; -------------------------------------------------
MYRLC MAC
    mov a, %0
    rlc a
    mov %0, a
ENDMAC

; -------------------------------------------------
; Shift all BCD digits LEFT by 4 bits
; â†’ makes room for new digit in LSD (R7)
; Uses global: bcd[0..4]
; -------------------------------------------------

Shift_Digits_Left:
    mov R0, #4         ; Need 4 bit shifts (one nibble)

Shift_Digits_Left_L0:
    clr c
    MYRLC(bcd+0)
    MYRLC(bcd+1)
    MYRLC(bcd+2)
    MYRLC(bcd+3)
    MYRLC(bcd+4)
    djnz R0, Shift_Digits_Left_L0

    ; Insert new digit from R7 into lowest nibble
    anl  bcd+0, #0F0h   ; clear lower nibble
    mov  a, R7
    anl  a, #0Fh        ; ensure only 0â€“F
    orl  bcd+0, a
    ret

; -------------------------------------------------
; Rotate Right through Carry macro
; -------------------------------------------------
MYRRC MAC
    mov a, %0
    rrc a
    mov %0, a
ENDMAC

; -------------------------------------------------
; Shift digits RIGHT by 4 bits â†’ BACKSPACE
; Uses global: bcd[0..4]
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
L6: mov R1, #74
L5: mov R2, #250
L4: djnz R2, L4
    djnz R1, L5
    djnz R0, L6
    ret


; -------------------------------------------------
; Helper routines for parameter storage
; Globals:
;   bcd[0..1], soak_temp, soak_time, reflow_temp, reflow_time, active_param
; -------------------------------------------------

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
    ; D: reflow_time
    mov reflow_time,   bcd+0
    mov reflow_time+1, bcd+1
    ret


Load_Param_Into_BCD:
    mov bcd+2, #00h
    mov bcd+3, #00h
    mov bcd+4, #00h

    mov a, active_param
    cjne a, #0, Load_NotA
    mov bcd+0, soak_temp
    mov bcd+1, soak_temp+1
    ret
Load_NotA:
    cjne a, #1, Load_NotB
    mov bcd+0, soak_time
    mov bcd+1, soak_time+1
    ret
Load_NotB:
    cjne a, #2, Load_NotC
    mov bcd+0, reflow_temp
    mov bcd+1, reflow_temp+1
    ret
Load_NotC:
    mov bcd+0, reflow_time
    mov bcd+1, reflow_time+1
    ret


; -------------------------------------------------
; Macro: Check one keypad column
; %0 = column bit, %1 = key code (immediate)
; Uses: R7, C
; -------------------------------------------------
CHECK_COLUMN MAC
    jb %0, CHECK_COL_%M      ; column=1 â†’ no key
    mov R7, %1               ; store key code
    jnb %0, $                ; wait for release
    setb c                   ; mark "key found"
    ljmp Key_Found
CHECK_COL_%M:
ENDMAC


; -------------------------------------------------
; Configure GPIO directions for keypad
; Assumes global P1MOD/P2MOD/P3MOD, row/col pins
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
;   C = 1 â†’ numeric key pressed, digit code in R7
;   C = 0 â†’ no digit (no key, mode key, or backspace)
; Side effects:
;   Can call Shift_Digits_Right for KEY1
;   Uses bcd/soak_*/active_param via Key_Found
; -------------------------------------------------

Keypad:

    ; KEY1 = backspace
    jb KEY.1, keypad_L0      ; if KEY1=1 (not pressed) â†’ skip
    lcall Wait25ms
    jb KEY.1, keypad_L0      ; if released, bounce â†’ skip
    jnb KEY.1, $             ; wait until released
    lcall Shift_Digits_Right
    clr c
    ret

keypad_L0:
    ; Drive all rows LOW, check if any column LOW
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
    lcall Wait25ms
    mov c, COL1
    anl c, COL2
    anl c, COL3
    anl c, COL4
    jnc Keypad_Key_Code
    clr c
    ret

Keypad_Key_Code:
    ; Prepare to scan rows
    setb ROW1
    setb ROW2
    setb ROW3
    setb ROW4

    ; SW0 chooses rotation
    jnb SWA.0, keypad_default
    ljmp keypad_90deg


; ---------------- Default keypad layout ----------------
; Row1: 1  2  3  A(0Ah)
; Row2: 4  5  6  B(0Bh)
; Row3: 7  8  9  C(0Ch)
; Row4: E  0  F  D(0Dh)
; -------------------------------------------------------

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


; ---------------- Rotated keypad layout (90Â° CCW) ------

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


; -------------------------------------------------
; Key_Found:
;   R7 = key code (0â€“F), C = 1 when we get here.
;   A/B/C/D â†’ mode select (no digit to caller)
;   Others â†’ numeric digit, C stays 1
; -------------------------------------------------

Key_Found:
    mov a, R7

    ; --- Mode A (soak temperature) ---
    cjne a, #0AH, Check_Mode_B
    lcall Save_Current_BCD_Into_Param
    mov active_param, #0       ; A: soak_temp
    lcall Load_Param_Into_BCD
    clr c                      ; not a digit
    ret

Check_Mode_B:
    cjne a, #0BH, Check_Mode_C
    lcall Save_Current_BCD_Into_Param
    mov active_param, #1       ; B: soak_time
    lcall Load_Param_Into_BCD
    clr c
    ret

Check_Mode_C:
    cjne a, #0CH, Check_Mode_D
    lcall Save_Current_BCD_Into_Param
    mov active_param, #2       ; C: reflow_temp
    lcall Load_Param_Into_BCD
    clr c
    ret

Check_Mode_D:
    cjne a, #0DH, Not_Mode_Key
    lcall Save_Current_BCD_Into_Param
    mov active_param, #3       ; D: reflow_time
    lcall Load_Param_Into_BCD
    clr c
    ret

Not_Mode_Key:
    ; numeric digit, C stays 1
    ret


ENDIF