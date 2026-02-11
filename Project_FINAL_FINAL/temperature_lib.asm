; ALL TEMP STUFF---------------------------------------------------------------------------------------


CSEG


InitSerialPort:
	; Configure serial port and baud rate
	clr TR2 ; Disable timer 2
	mov T2CON, #30H ; RCLK=1, TCLK=1
	mov RCAP2H, #high(T2LOAD)  
	mov RCAP2L, #low(T2LOAD)
	setb TR2 ; Enable timer 2
	mov SCON, #52H
	ret
	
putchar:
    JNB TI, putchar
    CLR TI
    MOV SBUF, a
    RET

SendString:
    CLR A
    MOVC A, @A+DPTR
    JZ SSDone
    LCALL putchar
    INC DPTR
    SJMP SendString
SSDone:
    ret
    

Display_Voltage_7seg:
    mov dptr, #myLUT
    
    ; Display Hundreds digit on HEX3
    mov a, bcd+1
    swap a
    anl a, #0FH
    movc a, @a+dptr
    mov HEX3, a
    
    ; Display Tens digit on HEX2
    mov a, bcd+1
    anl a, #0FH
    movc a, @a+dptr
    mov HEX2, a

    ; Display Ones digit on HEX1 and turn on the DOT
    mov a, bcd+0
    swap a
    anl a, #0FH
    movc a, @a+dptr
    anl a, #0x7f          ; Clears bit 7 to turn on the decimal point
    mov HEX1, a

    ; Display Tenths digit on HEX0
    mov a, bcd+0
    anl a, #0FH
    movc a, @a+dptr
    mov HEX0, a
    ret

Display_Voltage_LCD:
    mov a, #'T'
    lcall ?WriteData
    mov a, #'='
    lcall ?WriteData

    ; Convert x to BCD first
    push x+0
    push x+1
    push x+2
    push x+3
    
    lcall hex2bcd
    
    ; Display thousands digit (if non-zero)
    mov a, bcd+1
    swap a
    anl a, #0FH
    jz skip_thousands    ; Skip if zero (no leading zeros)
    orl a, #'0'
    lcall ?WriteData
    sjmp show_hundreds

skip_thousands:
    ; Check if hundreds is non-zero
    mov a, bcd+1
    anl a, #0FH
    jz skip_hundreds

show_hundreds:
    ; Display hundreds digit
    mov a, bcd+1
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData
    sjmp show_tens

skip_hundreds:
    ; Always show tens if we got here, even if zero
    mov a, bcd+0
    swap a
    anl a, #0FH
    jz skip_tens

show_tens:
    ; Display tens digit
    mov a, bcd+0
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData
    
    
    mov a, #'.'           ; Insert the decimal point
    lcall ?WriteData

skip_tens:
    ; Display ones digit (always shown)
    mov a, bcd+0
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData



    ; Display tenths digit (from bcd-1 if needed, or just show '0')
    ; Since hex2bcd gives us the full conversion, check if there are more digits
    ; For simplicity with your temperature format (tenths), just show '0'
    
    ; Restore x
    pop x+3
    pop x+2
    pop x+1
    pop x+0
    
    ret
    
Display_Voltage_Serial:
    ;Format: PROFILE,soak_temp,soak_time,reflow_temp,reflow_time[,peak_temp][,heating_rate][,cooling_rate]
    ; 1. Display Hundreds Digit (from bcd+1 high nibble)
    mov a, bcd+1
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 2. Display Tens Digit (from bcd+1 low nibble)
    mov a, bcd+1
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 3. Display Ones Digit (from bcd+0 high nibble)
    mov a, bcd+0
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 4. Display the actual Decimal Point
    mov a, #'.'
    lcall putchar

    ; 5. Display Tenths Digit (from bcd+0 low nibble)
    mov a, bcd+0
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 6. New line formatting
    mov a, #'\r'
    lcall putchar
    mov a, #'\n'
    lcall putchar
    ret    
    
    
Display_Voltage_LCD_Hex:
    mov a, #'0'
    lcall ?WriteData
    mov a, #'x'
    lcall ?WriteData

    ; Display x+3 (MSB)
    mov a, x+3
    swap a
    anl a, #0FH
    add a, #0x90
    da a
    addc a, #0x40
    da a
    lcall ?WriteData
    
    mov a, x+3
    anl a, #0FH
    add a, #0x90
    da a
    addc a, #0x40
    da a
    lcall ?WriteData

    ; Display x+2
    mov a, x+2
    swap a
    anl a, #0FH
    add a, #0x90
    da a
    addc a, #0x40
    da a
    lcall ?WriteData
    
    mov a, x+2
    anl a, #0FH
    add a, #0x90
    da a
    addc a, #0x40
    da a
    lcall ?WriteData

    ; Display x+1
    mov a, x+1
    swap a
    anl a, #0FH
    add a, #0x90
    da a
    addc a, #0x40
    da a
    lcall ?WriteData
    
    mov a, x+1
    anl a, #0FH
    add a, #0x90
    da a
    addc a, #0x40
    da a
    lcall ?WriteData

    ; Display x+0 (LSB)
    mov a, x+0
    swap a
    anl a, #0FH
    add a, #0x90
    da a
    addc a, #0x40
    da a
    lcall ?WriteData
    
    mov a, x+0
    anl a, #0FH
    add a, #0x90
    da a
    addc a, #0x40
    da a
    lcall ?WriteData
    
    ret
    
    
WriteInitialVals:
    ;Format: PROFILE,soak_temp,soak_time,reflow_temp,reflow_time[,peak_temp][,heating_rate][,cooling_rate]
    mov dptr, #Profile
    lcall SendString

    ;--------------------------------SOAK TEMP-------------------------------
    ; 1. Display Hundreds Digit (from bcd+1 high nibble)
    mov a, soak_temp+1
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 2. Display Tens Digit (from bcd+1 low nibble)
    mov a, soak_temp+1
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 3. Display Ones Digit (from bcd+0 high nibble)
    mov a, soak_temp+0
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 5. Display Tenths Digit (from bcd+0 low nibble)
    mov a, soak_temp+0
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    mov a, #','
    lcall putchar

    ;----------------------- SOAK TIME------------------------
    mov a, soak_time+1
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 2. Display Tens Digit (from bcd+1 low nibble)
    mov a, soak_time+1
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 3. Display Ones Digit (from bcd+0 high nibble)
    mov a, soak_time+0
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 5. Display Tenths Digit (from bcd+0 low nibble)
    mov a, soak_time+0
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    mov a, #','
    lcall putchar

    ;----------------------------- REFLOW TEMP---------------------------------------
    mov a, reflow_temp+1
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 2. Display Tens Digit (from bcd+1 low nibble)
    mov a, reflow_temp+1
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 3. Display Ones Digit (from bcd+0 high nibble)
    mov a, reflow_temp+0
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 5. Display Tenths Digit (from bcd+0 low nibble)
    mov a, reflow_temp+0
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    mov a, #','
    lcall putchar

    ;----------------------------------- REFLOW TIME------------------------
    mov a, reflow_time+1
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 2. Display Tens Digit (from bcd+1 low nibble)
    mov a, reflow_time+1
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 3. Display Ones Digit (from bcd+0 high nibble)
    mov a, reflow_time+0
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall putchar

    ; 5. Display Tenths Digit (from bcd+0 low nibble)
    mov a, reflow_time+0
    anl a, #0FH
    orl a, #'0'
    lcall putchar
    
    mov a, #'\r'
    lcall putchar
    mov a, #'\n'
    lcall putchar

    ret
END
