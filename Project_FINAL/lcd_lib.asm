;==================================================
; lcd_lib.asm  -  High level LCD helper functions
;==================================================
; Assumes:
;   - Included AFTER LCD_4bit_DE10Lite_no_RW.inc
;   - Global variables exist in main:
;       soak_temp, soak_time, reflow_temp, reflow_time (2-byte BCD)
;       tempFinal (32-bit), bcd (5 bytes) if used by future functions
;   - Macros available:
;       Set_Cursor(row, col)
;       Display_char #imm
;       Display_BCD(R0)
;==================================================

CSEG

;--------------------------------------------------
; 1) LCD_Clear
;    - Clears the LCD and waits for the command to complete
;    - Convenience wrapper so main doesn't have to remember 0x01 + delay
;--------------------------------------------------
LCD_Clear:
    WriteCommand(#01h)         ; Clear display command
    Wait_Milli_Seconds(#2)     ; Let LCD finish
    ret

;--------------------------------------------------
; 2) LCD_Show_Params
;    - Shows all four parameters (A/B/C/D) on 2 lines.
;    - Uses 2-byte BCD for each param (soak_*, reflow_*).
;    - Does NOT do any math; assumes values in BCD are valid.
;--------------------------------------------------
LCD_Show_Params:
    ; ----- Line 1: A:XXXX B:XXXX -----
    Set_Cursor(1, 1)

    ; "A:"
    Display_char #'A'
    Display_char #':'

    ; soak_temp (2 bytes BCD -> 4 digits)
    mov R0, soak_temp+1        ; high 2 digits
    Display_BCD(R0)
    mov R0, soak_temp+0        ; low 2 digits
    Display_BCD(R0)

    ; space
    Display_char #' '

    ; "B:"
    Display_char #'B'
    Display_char #':'

    ; soak_time
    mov R0, soak_time+1
    Display_BCD(R0)
    mov R0, soak_time+0
    Display_BCD(R0)

    ; ----- Line 2: C:XXXX D:XXXX -----
    Set_Cursor(2, 1)

    ; "C:"
    Display_char #'C'
    Display_char #':'

    ; reflow_temp
    mov R0, reflow_temp+1
    Display_BCD(R0)
    mov R0, reflow_temp+0
    Display_BCD(R0)

    ; space
    Display_char #' '

    ; "D:"
    Display_char #'D'
    Display_char #':'

    ; reflow_time
    mov R0, reflow_time+1
    Display_BCD(R0)
    mov R0, reflow_time+0
    Display_BCD(R0)

    ret


;--------------------------------------------------
; 3) LCD_Show_StateSimple
;    - Very lightweight state display: "State: X"
;    - Assumes FSM_state is a small integer (0..5 etc.)
;    - Purely cosmetic helper; not wired to main yet.
;--------------------------------------------------
LCD_Show_StateSimple:
    ; You can change cursor position if you want
    Set_Cursor(1, 1)

    ; "State:"
    Display_char #'S'
    Display_char #'t'
    Display_char #'a'
    Display_char #'t'
    Display_char #'e'
    Display_char #':'
    Display_char #' '

    ; For now just show FSM_state low nibble as one hex digit (0–F)
    mov A, FSM_state
    anl A, #0Fh
    orl A, #30h             ; crude 0–9 only, good enough if state <= 9
    lcall ?WriteData        ; use underlying LCD write-data routine

    ret
