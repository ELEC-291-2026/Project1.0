$MODMAX10

; The Special Function Registers below were added to 'MODMAX10' recently.
; If you are getting an error, uncomment the three lines below.

; ADC_C DATA 0xa1
; ADC_L DATA 0xa2
; ADC_H DATA 0xa3

CSEG at 0
ljmp mycode

dseg at 30h
x: ds 4
y: ds 4
bcd: ds 5
V_tc: ds 4   ; Add this - to store the thermocouple mV
V_cj: ds 4   ; Add this - to store the cold junction temp


bseg

mf: dbit 1

FREQ   EQU 33333333
BAUD   EQU 115200
T2LOAD EQU 65536-(FREQ/(32*BAUD))

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

$include(math32.asm)

cseg
; These 'equ' must match the wiring between the DE10Lite board and the LCD!
; P0 is in connector JPIO.  Check "CV-8052 Soft Processor in the DE10Lite Board: Getting
; Started Guide" for the details.
ELCD_RS equ P1.7
; ELCD_RW equ Px.x ; Not used.  Connected to ground
ELCD_E  equ P1.1
ELCD_D4 equ P0.7
ELCD_D5 equ P0.5
ELCD_D6 equ P0.3
ELCD_D7 equ P0.1
$NOLIST
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$LIST

; Look-up table for 7-seg displays
myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99        ; 0 TO 4
    DB 0x92, 0x82, 0xF8, 0x80, 0x90        ; 4 TO 9
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E  ; A to F

Wait50ms:
;33.33MHz, 1 clk per cycle: 0.03us
mov R0, #30
Wait50ms_L3:
mov R1, #74
Wait50ms_L2:
mov R2, #250
Wait50ms_L1:
djnz R2, Wait50ms_L1 ;3*250*0.03us=22.5us
    djnz R1, Wait50ms_L2 ;74*22.5us=1.665ms
    djnz R0, Wait50ms_L3 ;1.665ms*30=50ms
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
    Set_Cursor(2,1)
    mov a, #'T'
    lcall ?WriteData
    mov a, #'='
    lcall ?WriteData

    ; Hundreds
    mov a, bcd+1
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData

    ; Tens
    mov a, bcd+1
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData

    ; Ones
    mov a, bcd+0
    swap a
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData

    mov a, #'.'           ; Insert the dot
    lcall ?WriteData

    ; Tenths
    mov a, bcd+0
    anl a, #0FH
    orl a, #'0'
    lcall ?WriteData
    ret
    
Display_Voltage_Serial:

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
Initial_Message:  db 'Tmperature Test', 0

mycode:
mov SP, #7FH
clr a
mov LEDRA, a
mov LEDRB, a

lcall InitSerialPort

; COnfigure the pins connected to the LCD as outputs
mov P0MOD, #10101010b ; P0.1, P0.3, P0.5, P0.7 are outputs.  ('1' makes the pin output)
    mov P1MOD, #10000010b ; P1.7 and P1.1 are outputs

    lcall ELCD_4BIT ; Configure LCD in four bit mode
    ; For convenience a few handy macros are included in 'LCD_4bit_DE1Lite.inc':
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)

mov dptr, #Initial_Message
lcall SendString
mov a, #'\r'
lcall putchar
mov a, #'\n'
lcall putchar

mov ADC_C, #0x80 ; Reset ADC
lcall Wait50ms
forever:
    ; ---------------------------------------------------------
    ; 1) Read thermocouple channel and convert to mV
    ; ---------------------------------------------------------
    mov a, SWA
    anl a, #0x07
    mov R7, a             ; Save channel number
    mov ADC_C, a

    mov x+3, #0
    mov x+2, #0
    mov x+1, ADC_H
    mov x+0, ADC_L

    Load_y(5000)
    lcall mul32
    Load_y(4096)
    lcall div32           ; x now holds Vtc in mV
    
    ; Save it
    mov V_tc+0, x+0
    mov V_tc+1, x+1
    mov V_tc+2, x+2
    mov V_tc+3, x+3

    ; ---------------------------------------------------------
    ; 2) Read LM335 (next channel) and convert to Celsius
    ; ---------------------------------------------------------
    mov a, R7
    inc a
    anl a, #0x07
    mov ADC_C, a

    mov x+3, #0
    mov x+2, #0
    mov x+1, ADC_H
    mov x+0, ADC_L

    Load_y(5000)
    lcall mul32
    Load_y(4096)
    lcall div32           ; x = Vlm in mV

    Load_y(10)
    lcall div32           ; x = Kelvin
    Load_y(273)
    lcall sub32           ; x = Celsius
    
    ; Save cold junction temp
    mov V_cj+0, x+0
    mov V_cj+1, x+1
    mov V_cj+2, x+2
    mov V_cj+3, x+3

; ---------------------------------------------------------
    ; 3) Calculate: Temp_x10 = (V_tc * 10000 / 12300) + (V_cj * 10)
    ; ---------------------------------------------------------
    mov x+0, V_tc+0
    mov x+1, V_tc+1
    mov x+2, V_tc+2
    mov x+3, V_tc+3

    Load_y(10000)         ; Was 1000, now 10000 to keep one decimal place
    lcall mul32
    Load_y(12300)
    lcall div32           ; x = scaled TC temperature (e.g., 123 for 12.3C)

    ; Save this intermediate result in y to free up x for CJ scaling
    mov y+0, x+0
    mov y+1, x+1
    mov y+2, x+2
    mov y+3, x+3

    ; Load Cold Junction and scale it by 10 to match units
    mov x+0, V_cj+0
    mov x+1, V_cj+1
    mov x+2, V_cj+2
    mov x+3, V_cj+3
    
    push y+0              ; Save our TC result safely
    push y+1
    push y+2
    push y+3
    
    Load_y(10)
    lcall mul32           ; x = CJ * 10
    
    pop y+3               ; Restore TC result into y
    pop y+2
    pop y+1
    pop y+0
    
    lcall add32           ; Final result: (TC_temp*10) + (CJ_temp*10)

    ; ---------------------------------------------------------
    ; 4) Display
    ; ---------------------------------------------------------
    lcall hex2bcd
    lcall Display_Voltage_7seg
    lcall Display_Voltage_LCD
    lcall Display_Voltage_Serial
    
    mov R7, #20 
delay_loop:     
    lcall Wait50ms     
    djnz R7, delay_loop
    ljmp forever
end
