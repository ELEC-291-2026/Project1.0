;===========================================================
; lcd_lib.asm - High-level LCD helper routines
;===========================================================
; Provides:
;   LCD_ShowParameter    - Show current active parameter on row 1
;   LCD_ShowTotalTime    - Show "Tot MM:SS" on row 2
;   LCD_ShowStateTime    - Show "St  MM:SS" on row 2 (simple)
;   LCD_ShowStateRunInfo - Show "Sx MM:SS ########" on row 2
;===========================================================

CSEG


;-----------------------------------------------------------
; Write_3digits(var)
; var is a 2-byte packed BCD value:
;   var+0 : low byte  (tens, ones)
;   var+1 : high byte (thousands, hundreds)
; We print exactly 3 digits: H T O
;   H = hundreds  (low nibble of var+1)
;   T = tens      (high nibble of var+0)
;   O = ones      (low nibble of var+0)
;-----------------------------------------------------------
Write_3digits MAC
    ; --- Hundreds digit (from low nibble of var+1) ---
    mov  a, %0+1        ; load high BCD byte
    anl  a, #0FH        ; keep low nibble = hundreds
    orl  a, #'0'        ; convert 0–9 -> ASCII
    lcall ?WriteData

    ; --- Tens digit (from high nibble of var+0) ---
    mov  a, %0+0        ; load low BCD byte
    swap a              ; high nibble -> low nibble
    anl  a, #0FH        ; keep that nibble
    orl  a, #'0'        ; 0–9 -> ASCII
    lcall ?WriteData

    ; --- Ones digit (from low nibble of var+0) ---
    mov  a, %0+0        ; load low BCD byte again
    anl  a, #0FH        ; low nibble = ones
    orl  a, #'0'        ; 0–9 -> ASCII
    lcall ?WriteData
ENDMAC

;-----------------------------------------------------------
; LCD_ShowParamsLine1
;   Writes: ST=xxx  t=yyy
;   Uses: soak_temp (3-digit BCD), soak_time (seconds, 3-digit BCD)
;   Cursor must already be positioned by caller (e.g. Set_Cursor(1,1))
;-----------------------------------------------------------
LCD_ShowParamsLine1:
    push acc

    ; "ST="
    mov  a, #'S'
    lcall ?WriteData
    mov  a, #'T'
    lcall ?WriteData
    mov  a, #'='
    lcall ?WriteData

    ; ST=xxx   (soak_temp)
    Write_3digits(soak_temp)

    ; "  " (two spaces)
    mov  a, #' '
    lcall ?WriteData
    mov  a, #' '
    lcall ?WriteData

    ; "t="
    mov  a, #'t'
    lcall ?WriteData
    mov  a, #'='
    lcall ?WriteData

    ; t=yyy   (soak_time in seconds)
    Write_3digits(soak_time)    

    pop  acc
    ret


;-----------------------------------------------------------
; LCD_ShowParamsLine2
;   Writes: RT=xxx  t=yyy
;   Uses: reflow_temp (3-digit BCD), reflow_time (seconds, 3-digit BCD)
;   Cursor must already be positioned by caller (e.g. Set_Cursor(2,1))
;-----------------------------------------------------------
LCD_ShowParamsLine2:
    push acc

    ; "RT="
    mov  a, #'R'
    lcall ?WriteData
    mov  a, #'T'
    lcall ?WriteData
    mov  a, #'='
    lcall ?WriteData

    ; RT=xxx   (reflow_temp)
    Write_3digits(reflow_temp)

    ; "  " (two spaces)
    mov  a, #' '
    lcall ?WriteData
    mov  a, #' '
    lcall ?WriteData

    ; "t="
    mov  a, #'t'
    lcall ?WriteData
    mov  a, #'='
    lcall ?WriteData

    ; t=yyy   (reflow_time in seconds)
    Write_3digits(reflow_time)

    pop  acc
    ret

;-----------------------------------------------------------
; LCD_ShowTotalTime
;   Displays total elapsed time in MM:SS format:
;     Row 2: "Tot MM:SS"
;-----------------------------------------------------------
  
LCD_ShowTotalTime:
    push acc
    push b
    push ar0

    ; Print label "Tot "
    Send_Constant_String(#TotalLbl)

    ; ----- Minutes (MM) -----
    mov  a, MinutesCounterTotal
    lcall Hex_to_bcd_8bit      ; result packed in R0 (tens/units)
    lcall ?Display_BCD         ; prints 2 digits from R0

    ; Colon separator
    Display_char(#':')

    ; ----- Seconds (SS) -----
    mov  a, SecondsCounterTotal
    lcall Hex_to_bcd_8bit
    lcall ?Display_BCD

    pop  ar0
    pop  b
    pop  acc
    ret


;-----------------------------------------------------------
; LCD_ShowStateTime
;   Prints:  "St  MM:SS"
;   Does NOT move cursor — caller must Set_Cursor first
;-----------------------------------------------------------
LCD_ShowStateTime:
    push acc
    push b
    push ar0
    push ar1
    push ar7

    ; ---- Print "St  " ----
    Send_Constant_String(#StateLbl)

    ; total seconds in this state -> A
    mov a, SecondsCounter
    mov b, #60
    div ab              ; A = minutes, B = seconds
    mov r7, b           ; save seconds

    ; ---- Minutes (MM) ----
    lcall Hex_to_bcd_8bit
    lcall ?Display_BCD

    ; ---- Colon ----
    Display_char(#':')

    ; ---- Seconds (SS) ----
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
TotalLbl:     db  'Tot ', 0
StateLbl:     db  'St  ', 0
