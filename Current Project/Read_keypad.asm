$NOLIST
$MODMAX10          
$LIST

PUBLIC Keypad
PUBLIC Configure_Keypad_Pins
PUBLIC Shift_Digits_Left
PUBLIC Shift_Digits_Right
PUBLIC Update_Display_Mode
PUBLIC Save_Current_Parameter

; Reset vector
CSEG at 0
    ljmp main_code

; Data Segment – Reflow Parameters

DSEG at 30H
bcd:              ds 5    ; Current input buffer (10 BCD digits)

; Reflow Profile Parameters (stored separately)
soak_temp:        ds 2    ; Soak temperature (°C) - 16 bit
soak_time:        ds 2    ; Soak time (seconds) - 16 bit
reflow_temp:      ds 2    ; Reflow temperature (°C) - 16 bit
reflow_time:      ds 2    ; Reflow time (seconds) - 16 bit

; Current mode and display state
current_mode:     ds 1    ; 0=Soak Temp, 1=Soak Time, 2=Reflow Temp, 3=Reflow Time
parameter_saved:  ds 1    ; Flag: 1 = parameter has been saved
input_active:     ds 1    ; Flag: 1 = user is entering a value

; Code Segment
CSEG

; Lookup table for 7-segment display
myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99        ; 0–4
    DB 0x92, 0x82, 0xF8, 0x80, 0x90        ; 5–9
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E  ; A–F

;---------------------------------------------------------
; Macro: showBCD - Display one byte as two 7-seg digits
;---------------------------------------------------------
showBCD MAC
    mov A, %0
    anl a, #0fh
    movc A, @A+dptr
    mov %1, A

    mov A, %0
    swap a
    anl a, #0fh
    movc A, @A+dptr
    mov %2, A
ENDMAC

;---------------------------------------------------------
; Display routine – Shows current mode and parameter value
;---------------------------------------------------------
Display:
    mov dptr, #myLUT

    ; Check if we're in input mode or display mode
    mov a, input_active
    jz Display_Saved_Value

Display_Input_Value:
    ; Show what user is currently typing
    showBCD(bcd+0, HEX0, HEX1)
    showBCD(bcd+1, HEX2, HEX3)
    showBCD(bcd+2, HEX4, HEX5)
    
    ; Use LEDRA to show current mode
    lcall Display_Mode_Indicator
    sjmp Display_end

Display_Saved_Value:
    ; Show the saved parameter for current mode
    lcall Display_Current_Parameter
    lcall Display_Mode_Indicator

Display_end:
    ret

;---------------------------------------------------------
; Display mode indicator on LEDRA
; A=Soak Temp, B=Soak Time, C=Reflow Temp, D=Reflow Time
;---------------------------------------------------------
Display_Mode_Indicator:
    mov a, current_mode
    
    cjne a, #0, mode_not_0
    ; Mode A - Soak Temperature
    mov LEDRA, #0b10001000  ; Pattern for 'A'
    ret
mode_not_0:
    
    cjne a, #1, mode_not_1
    ; Mode B - Soak Time
    mov LEDRA, #0b10000011  ; Pattern for 'b'
    ret
mode_not_1:
    
    cjne a, #2, mode_not_2
    ; Mode C - Reflow Temperature
    mov LEDRA, #0b11000110  ; Pattern for 'C'
    ret
mode_not_2:
    
    ; Mode D - Reflow Time
    mov LEDRA, #0b10100001  ; Pattern for 'd'
    ret

;---------------------------------------------------------
; Display the current parameter value on 7-segment displays
;---------------------------------------------------------
Display_Current_Parameter:
    push dpl
    push dph
    
    mov a, current_mode
    
    cjne a, #0, disp_param_1
    ; Display Soak Temperature
    lcall BCD_From_Parameter
    mov dptr, #soak_temp
    sjmp disp_param_show
    
disp_param_1:
    cjne a, #1, disp_param_2
    ; Display Soak Time
    mov dptr, #soak_time
    sjmp disp_param_show
    
disp_param_2:
    cjne a, #2, disp_param_3
    ; Display Reflow Temperature
    mov dptr, #reflow_temp
    sjmp disp_param_show
    
disp_param_3:
    ; Display Reflow Time
    mov dptr, #reflow_time

disp_param_show:
    ; Convert 16-bit parameter to BCD and display
    lcall Convert_Word_to_BCD
    
    mov dptr, #myLUT
    showBCD(bcd+0, HEX0, HEX1)
    showBCD(bcd+1, HEX2, HEX3)
    showBCD(bcd+2, HEX4, HEX5)
    
    pop dph
    pop dpl
    ret

;---------------------------------------------------------
; Convert 16-bit word pointed by DPTR to BCD in bcd buffer
;---------------------------------------------------------
Convert_Word_to_BCD:
    push acc
    push b
    push R0
    push R1
    push R2
    push R3
    
    ; Read 16-bit value
    movx a, @dptr
    mov R2, a       ; Low byte
    inc dptr
    movx a, @dptr
    mov R3, a       ; High byte
    
    ; Clear BCD buffer
    clr a
    mov bcd+0, a
    mov bcd+1, a
    mov bcd+2, a
    mov bcd+3, a
    mov bcd+4, a
    
    ; Binary to BCD conversion (double-dabble algorithm)
    mov R0, #16     ; 16 bits to convert
    
convert_loop:
    ; Shift binary left
    clr c
    mov a, R2
    rlc a
    mov R2, a
    mov a, R3
    rlc a
    mov R3, a
    
    ; Shift BCD left and add carry
    mov R1, #3      ; 3 BCD bytes needed for 16-bit (max 65535)
    mov a, bcd+0
    rlc a
    da a
    mov bcd+0, a
    
    mov a, bcd+1
    rlc a
    da a
    mov bcd+1, a
    
    mov a, bcd+2
    rlc a
    da a
    mov bcd+2, a
    
    djnz R0, convert_loop
    
    pop R3
    pop R2
    pop R1
    pop R0
    pop b
    pop acc
    ret

;---------------------------------------------------------
; BCD_From_Parameter - Helper stub
;---------------------------------------------------------
BCD_From_Parameter:
    ret

;---------------------------------------------------------
; Macro: Rotate Left through Carry
;---------------------------------------------------------
MYRLC MAC
    mov a, %0
    rlc a
    mov %0, a
ENDMAC

;---------------------------------------------------------
; Shift BCD digits LEFT (make room for new digit)
;---------------------------------------------------------
Shift_Digits_Left:
    mov R0, #4

Shift_Digits_Left_L0:
    clr c
    MYRLC(bcd+0)
    MYRLC(bcd+1)
    MYRLC(bcd+2)
    MYRLC(bcd+3)
    MYRLC(bcd+4)
    djnz R0, Shift_Digits_Left_L0

    ; Insert new digit from R7
    mov a, R7
    orl a, bcd+0
    mov bcd+0, a
    ret

;---------------------------------------------------------
; Macro: Rotate Right through Carry
;---------------------------------------------------------
MYRRC MAC
    mov a, %0
    rrc a
    mov %0, a
ENDMAC

;---------------------------------------------------------
; Shift digits RIGHT (backspace)
;---------------------------------------------------------
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

;---------------------------------------------------------
; Wait 25ms (debounce delay)
;---------------------------------------------------------
Wait25ms:
    mov R0, #15
L3: mov R1, #74
L2: mov R2, #250
L1: djnz R2, L1
    djnz R1, L2
    djnz R0, L3
    ret

;---------------------------------------------------------
; Macro: Check one keypad column
;---------------------------------------------------------
CHECK_COLUMN MAC
    jb %0, CHECK_COL_%M
    mov R7, %1
    jnb %0, $
    setb c
    ret
CHECK_COL_%M:
ENDMAC

;---------------------------------------------------------
; Configure keypad GPIO pins
;---------------------------------------------------------
Configure_Keypad_Pins:
    orl P1MOD, #0b_01010100
    orl P2MOD, #0b_00000001
    anl P2MOD, #0b_10101011
    anl P3MOD, #0b_11111110
    ret

; Pin definitions
ROW1 EQU P1.2
ROW2 EQU P1.4
ROW3 EQU P1.6
ROW4 EQU P2.0

COL1 EQU P2.2
COL2 EQU P2.4
COL3 EQU P2.6
COL4 EQU P3.0

;---------------------------------------------------------
; Keypad scanning with mode switching support
; Returns: C=1 if key pressed, key code in R7
;---------------------------------------------------------
Keypad:
    ; KEY1 = BACKSPACE
    jb KEY.1, keypad_check_save
    lcall Wait25ms
    jb KEY.1, keypad_check_save
    jnb KEY.1, $
    
    ; Only backspace if in input mode
    mov a, input_active
    jz keypad_check_save
    lcall Shift_Digits_Right
    clr c
    ret

keypad_check_save:
    ; KEY3 = SAVE current parameter
    jb KEY.3, keypad_L0
    lcall Wait25ms
    jb KEY.3, keypad_L0
    jnb KEY.3, $
    
    ; Save current parameter and exit input mode
    lcall Save_Current_Parameter
    mov input_active, #0
    clr c
    ret

keypad_L0:
    ; Check if any key pressed
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
    setb ROW1
    setb ROW2
    setb ROW3
    setb ROW4

    ; Default layout only
    clr ROW1
    CHECK_COLUMN(COL1, #01H)
    CHECK_COLUMN(COL2, #02H)
    CHECK_COLUMN(COL3, #03H)
    CHECK_COLUMN(COL4, #0AH)    ; 'A' key
    setb ROW1

    clr ROW2
    CHECK_COLUMN(COL1, #04H)
    CHECK_COLUMN(COL2, #05H)
    CHECK_COLUMN(COL3, #06H)
    CHECK_COLUMN(COL4, #0BH)    ; 'B' key
    setb ROW2

    clr ROW3
    CHECK_COLUMN(COL1, #07H)
    CHECK_COLUMN(COL2, #08H)
    CHECK_COLUMN(COL3, #09H)
    CHECK_COLUMN(COL4, #0CH)    ; 'C' key
    setb ROW3

    clr ROW4
    CHECK_COLUMN(COL1, #0EH)
    CHECK_COLUMN(COL2, #00H)
    CHECK_COLUMN(COL3, #0FH)
    CHECK_COLUMN(COL4, #0DH)    ; 'D' key
    setb ROW4

    clr c
    ret

;---------------------------------------------------------
; Check if key is a mode switch (A/B/C/D)
; Input: R7 = key code
; Output: C=1 if mode switch, C=0 otherwise
;---------------------------------------------------------
Check_Mode_Switch:
    mov a, R7
    
    cjne a, #0AH, check_mode_B
    ; 'A' pressed - Switch to Soak Temperature mode
    mov current_mode, #0
    clr a
    mov bcd+0, a
    mov bcd+1, a
    mov bcd+2, a
    mov input_active, #1
    setb c
    ret
    
check_mode_B:
    cjne a, #0BH, check_mode_C
    ; 'B' pressed - Switch to Soak Time mode
    mov current_mode, #1
    clr a
    mov bcd+0, a
    mov bcd+1, a
    mov bcd+2, a
    mov input_active, #1
    setb c
    ret
    
check_mode_C:
    cjne a, #0CH, check_mode_D
    ; 'C' pressed - Switch to Reflow Temperature mode
    mov current_mode, #2
    clr a
    mov bcd+0, a
    mov bcd+1, a
    mov bcd+2, a
    mov input_active, #1
    setb c
    ret
    
check_mode_D:
    cjne a, #0DH, not_mode_switch
    ; 'D' pressed - Switch to Reflow Time mode
    mov current_mode, #3
    clr a
    mov bcd+0, a
    mov bcd+1, a
    mov bcd+2, a
    mov input_active, #1
    setb c
    ret
    
not_mode_switch:
    clr c
    ret

;---------------------------------------------------------
; Save current BCD input to appropriate parameter register
;---------------------------------------------------------
Save_Current_Parameter:
    push acc
    push b
    push R0
    push R1
    push dpl
    push dph
    
    ; Convert BCD to 16-bit binary
    lcall BCD_to_Binary_16bit
    ; Result in R0(low), R1(high)
    
    ; Save to appropriate parameter based on mode
    mov a, current_mode
    
    cjne a, #0, save_param_1
    ; Save to Soak Temperature
    mov soak_temp, R0
    mov soak_temp+1, R1
    sjmp save_done
    
save_param_1:
    cjne a, #1, save_param_2
    ; Save to Soak Time
    mov soak_time, R0
    mov soak_time+1, R1
    sjmp save_done
    
save_param_2:
    cjne a, #2, save_param_3
    ; Save to Reflow Temperature
    mov reflow_temp, R0
    mov reflow_temp+1, R1
    sjmp save_done
    
save_param_3:
    ; Save to Reflow Time
    mov reflow_time, R0
    mov reflow_time+1, R1

save_done:
    ; Flash LEDRB to confirm save
    mov LEDRB, #0xFF
    lcall Wait25ms
    mov LEDRB, #0x00
    
    pop dph
    pop dpl
    pop R1
    pop R0
    pop b
    pop acc
    ret

;---------------------------------------------------------
; Convert BCD (in bcd buffer) to 16-bit binary
; Output: R0 = low byte, R1 = high byte
;---------------------------------------------------------
BCD_to_Binary_16bit:
    push acc
    push b
    push R2
    push R3
    
    ; Initialize result to 0
    mov R0, #0
    mov R1, #0
    
    ; Process only first 3 BCD bytes (handles up to 999,999)
    ; But for 16-bit we max at 65,535
    
    ; Start with bcd+2 (ten-thousands and thousands)
    mov a, bcd+2
    anl a, #0F0h
    swap a
    ; a = ten-thousands digit
    mov b, #10
    mul ab          ; a = digit * 10
    mov R2, a       ; R2 = thousands part
    
    mov a, bcd+2
    anl a, #0Fh
    add a, R2       ; Add thousands digit
    ; Now a = total thousands
    
    ; Multiply by 1000
    mov b, #100
    mul ab          ; ab = thousands * 100
    mov R2, a
    mov R3, b       ; R3:R2 = thousands * 100
    
    mov a, R2
    mov b, #10
    mul ab          ; ab = (thousands*100) * 10
    add a, R0
    mov R0, a
    mov a, b
    addc a, R1
    mov R1, a
    
    ; Process bcd+1 (hundreds and tens)
    mov a, bcd+1
    anl a, #0F0h
    swap a
    ; a = hundreds digit
    mov b, #100
    mul ab
    add a, R0
    mov R0, a
    mov a, b
    addc a, R1
    mov R1, a
    
    mov a, bcd+1
    anl a, #0Fh
    ; a = tens digit
    mov b, #10
    mul ab
    add a, R0
    mov R0, a
    mov a, b
    addc a, R1
    mov R1, a
    
    ; Process bcd+0 (ones)
    mov a, bcd+0
    anl a, #0Fh
    add a, R0
    mov R0, a
    mov a, #0
    addc a, R1
    mov R1, a
    
    pop R3
    pop R2
    pop b
    pop acc
    ret

;---------------------------------------------------------
; Update display mode (optional external call)
;---------------------------------------------------------
Update_Display_Mode:
    ret

;---------------------------------------------------------
; MAIN PROGRAM
;---------------------------------------------------------
main_code:
    mov SP, #7FH

    ; Initialize LEDs
    clr a
    mov LEDRA, a
    mov LEDRB, a

    ; Clear BCD buffer
    mov bcd+0, a
    mov bcd+1, a
    mov bcd+2, a
    mov bcd+3, a
    mov bcd+4, a

    ; Initialize parameters to defaults
    ; Soak Temp = 150°C
    mov soak_temp, #150
    mov soak_temp+1, #0
    
    ; Soak Time = 90 seconds
    mov soak_time, #90
    mov soak_time+1, #0
    
    ; Reflow Temp = 220°C
    mov reflow_temp, #220
    mov reflow_temp+1, #0
    
    ; Reflow Time = 40 seconds
    mov reflow_time, #40
    mov reflow_time+1, #0
    
    ; Start in Soak Temperature mode
    mov current_mode, #0
    mov input_active, #0
    mov parameter_saved, #0

    lcall Configure_Keypad_Pins

;---------------------------------------------------------
; Main loop
;---------------------------------------------------------
forever:
    lcall Keypad        ; Scan for keys
    lcall Display       ; Update display
    jnc forever         ; No key? Loop
    
    ; Key was pressed, check if it's a mode switch
    lcall Check_Mode_Switch
    jc forever          ; Was mode switch, don't process as digit
    
    ; Check if it's a valid digit (0-9)
    mov a, R7
    cjne a, #0EH, check_valid_digit  ; 0E is '*', skip it
    sjmp forever
    
check_valid_digit:
    cjne a, #0FH, digit_ok    ; 0F is '#', skip it
    sjmp forever
    
digit_ok:
    ; Valid digit (0-9), only process if in input mode
    mov a, input_active
    jz forever
    
    ; Shift and add digit
    lcall Shift_Digits_Left
    ljmp forever

end