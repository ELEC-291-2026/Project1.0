///higher level library for LCD display

CSEG

;--------------------------------------------------
; Macro: LCD_PrintConst
; %0 = row, %1 = col, %2 = address of 0-terminated string
; Example: LCD_PrintConst(1, 1, #Initial_Message)
;--------------------------------------------------
LCD_PrintConst MAC
    Set_Cursor(%0, %1)
    Send_Constant_String(%2)
ENDMAC

;--------------------------------------------------
; Function: Display_Active_Param_LCD
; Shows the currently selected parameter (A/B/C/D)
; and its value from bcd[0..1] on line 2:
;   e.g. "A: 0150"
; Assumes:
;   - active_param: 0=A, 1=B, 2=C, 3=D
;   - packed BCD in bcd+1/bcd+0
;--------------------------------------------------

Display_Active_Param_LCD:
    ; Go to line 2, column 1
    Set_Cursor(2, 1)

    ; Decide label based on active_param
    mov A, active_param
    cjne A, #0, DAPL_notA
    ; Label "A: "
    mov A, #'A'
    lcall ?WriteData
    mov A, #':'
    lcall ?WriteData
    mov A, #' '
    lcall ?WriteData
    sjmp DAPL_show_digits

DAPL_notA:
    cjne A, #1, DAPL_notB
    ; Label "B: "
    mov A, #'B'
    lcall ?WriteData
    mov A, #':'
    lcall ?WriteData
    mov A, #' '
    lcall ?WriteData
    sjmp DAPL_show_digits

DAPL_notB:
    cjne A, #2, DAPL_notC
    ; Label "C: "
    mov A, #'C'
    lcall ?WriteData
    mov A, #':'
    lcall ?WriteData
    mov A, #' '
    lcall ?WriteData
    sjmp DAPL_show_digits

DAPL_notC:
    ; Default: D
    mov A, #'D'
    lcall ?WriteData
    mov A, #':'
    lcall ?WriteData
    mov A, #' '
    lcall ?WriteData

DAPL_show_digits:
    ; We assume:
    ;   bcd+1 = [thousands | hundreds]
    ;   bcd+0 = [tens      | ones]
    ; and each nibble is a BCD digit 0–9.

    ; Thousands digit (upper nibble of bcd+1)
    mov A, bcd+1
    swap A
    anl  A, #0Fh
    add A, #'0'
    lcall ?WriteData

    ; Hundreds digit (lower nibble of bcd+1)
    mov A, bcd+1
    anl  A, #0Fh
    add A, #'0'
    lcall ?WriteData

    ; Tens digit (upper nibble of bcd+0)
    mov A, bcd+0
    swap A
    anl  A, #0Fh
    add A, #'0'
    lcall ?WriteData

    ; Ones digit (lower nibble of bcd+0)
    mov A, bcd+0
    anl  A, #0Fh
    add A, #'0'
    lcall ?WriteData

    ; Optional padding
    mov A, #' '
    lcall ?WriteData
    lcall ?WriteData

    ret
