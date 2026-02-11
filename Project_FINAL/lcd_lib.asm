;===========================================================
; lcd_lib.inc  - High-level LCD helper routines
;===========================================================
; Provides:
;   LCD_ShowParameter  - Show current active parameter on row 1
;   LCD_ShowTotalTime  - Show "Tot MM:SS" on row 1
;   LCD_ShowStateTime  - Show "St  MM:SS" on row 2
;
; Relies on:
;   - Macros: Set_Cursor, Send_Constant_String, Display_char
;   - Subroutines: ?Display_BCD, Hex_to_bcd_8bit
;   - Global vars (defined in main dseg):
;       soak_temp (2 bytes BCD)
;       soak_time (2 bytes BCD)
;       reflow_temp (2 bytes BCD)
;       reflow_time (2 bytes BCD)
;       active_param (0=A,1=B,2=C,3=D)
;       SecondsCounterTotal, MinutesCounterTotal, SecondsCounter
;===========================================================

cseg
/// LCD show paramters 
LCD_ShowParameter:

    push acc
    push ar0
    push ar1

    ;========================
    ; ROW 1
    ; Soak Temp + Soak Time
    ;========================
    Set_Cursor(1,1)

    ; "ST="
    mov a, #'S'
    lcall ?WriteData
    mov a, #'T'
    lcall ?WriteData
    mov a, #'='
    lcall ?WriteData

    ; soak_temp
    mov r0, soak_temp+1
    lcall ?Display_BCD
    mov r0, soak_temp+0
    lcall ?Display_BCD

    ; space
    mov a, #' '
    lcall ?WriteData

    ; "STm="
    mov a, #'T'
    lcall ?WriteData
    mov a, #'m'
    lcall ?WriteData
    mov a, #'='
    lcall ?WriteData

    ; soak_time
    mov r0, soak_time+1
    lcall ?Display_BCD
    mov r0, soak_time+0
    lcall ?Display_BCD


    ;========================
    ; ROW 2
    ; Reflow Temp + Reflow Time
    ;========================
    Set_Cursor(2,1)

    ; "RT="
    mov a, #'R'
    lcall ?WriteData
    mov a, #'T'
    lcall ?WriteData
    mov a, #'='
    lcall ?WriteData

    ; reflow_temp
    mov r0, reflow_temp+1
    lcall ?Display_BCD
    mov r0, reflow_temp+0
    lcall ?Display_BCD

    ; space
    mov a, #' '
    lcall ?WriteData

    ; "RTm="
    mov a, #'T'
    lcall ?WriteData
    mov a, #'m'
    lcall ?WriteData
    mov a, #'='
    lcall ?WriteData

    ; reflow_time
    mov r0, reflow_time+1
    lcall ?Display_BCD
    mov r0, reflow_time+0
    lcall ?Display_BCD


    pop ar1
    pop ar0
    pop acc
    ret

;-----------------------------------------------------------
; LCD_ShowTotalTime
;   Displays total elapsed time in MM:SS format:
;     Row 1: "Tot MM:SS"
;-----------------------------------------------------------
LCD_ShowTotalTime:
    push acc
    push b
    push ar0

    ; Row 1, col 1: "Tot "
    Set_Cursor(1,1)
    Send_Constant_String(#TotalLbl)

    ; Minutes
    mov a, MinutesCounterTotal
    lcall Hex_to_bcd_8bit      ; result in R0
    lcall ?Display_BCD       ; prints 2 digits

    ; Colon
    Display_char(#':')

    ; Seconds
    mov a, SecondsCounterTotal
    lcall Hex_to_bcd_8bit
    lcall ?Display_BCD

    pop ar0
    pop b
    pop acc
    ret


;-----------------------------------------------------------
; LCD_ShowStateTime
;   Displays per-state timer, based on SecondsCounter.
;   DOES NOT MODIFY SecondsCounter.
;   Converts:
;       minutes = SecondsCounter / 60
;       seconds = SecondsCounter % 60
;
;   Displays on row 2:
;       "St  MM:SS"
;-----------------------------------------------------------
LCD_ShowStateTime:
    push acc
    push b
    push ar0
    push ar1
    push ar7

    ; Row 2, col 1: "St  "
    Set_Cursor(2,1)
    Send_Constant_String(#StateLbl)

    ; A = total seconds in this state
    mov a, SecondsCounter
    mov b, #60
    div ab              ; A = minutes, B = seconds
    mov r7, b           ; save seconds

    ; Minutes
    lcall Hex_to_bcd_8bit   ; A->R0 (packed BCD)
    lcall ?Display_BCD

    ; Colon
    Display_char(#':')

    ; Seconds
    mov a, r7
    lcall Hex_to_bcd_8bit
    lcall ?Display_BCD

    pop ar7
    pop ar1
    pop ar0
    pop b
    pop acc
    ret


;-----------------------------------------------------------
; Label strings
;-----------------------------------------------------------
ParamA_Label: db  'A: ', 0        ; soak_temp
ParamB_Label: db  'B: ', 0        ; soak_time
ParamC_Label: db  'C: ', 0        ; reflow_temp
ParamD_Label: db  'D: ', 0        ; reflow_time
TotalLbl: db  'Tot ', 0
StateLbl: db  'St  ', 0