; Non_Blocking_FSM_example.asm:  Four FSMs are run in the forever loop.
; Three FSMs are used to detect (with debounce) when either KEY1, KEY2, or
; KEY3 are pressed.  The fourth FSM keeps a counter (Count3) that is incremented
; every second.  When KEY1 is detected the program increments/decrements Count1,
; depending on the position of SW0. When KEY2 is detected the program
; increments/decrements Count2, also base on the position of SW0.  When KEY3
; is detected, the program resets Count3 to zero.  
;
$NOLIST
$MODMAX10
$LIST

CLK           	EQU 33333333 ; Microcontroller system crystal frequency in Hz
TIMER2_RATE   	EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD 	EQU ((65536-(CLK/(12*TIMER2_RATE))))
FREQ   			EQU 33333333
BAUD   			EQU 115200
T2LOAD 			EQU 65536-(FREQ/(32*BAUD))

;PIN Assignemet
;Need to figure out wich ADC pins the LM335 and OP07 are on 
LM335_ADC equ 0
OP07_ADC equ 1


; Reset vector
org 0x0000
    ljmp main

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

dseg at 0x30
; For math 
x:			ds 4
y:			ds 4
bcd:		ds 5
tempHot:	ds 5
tempCold:	ds 5
tempFinal:  ds 5


; Each FSM has its own timer
FSM_timer:  ds 1
; Each FSM has its own state counter
FSM_state:  ds 1
; Three counters to display.
Count3:     ds 1 ; Incremented every second. Reset to zero when KEY3 is pressed.

bseg
; For each pushbutton we have a flag.  The corresponding FSM will set this
; flags to one when a valid press of the pushbutton is detected.
mf       :  dbit 1

$include(math32.asm)
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros

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

cseg
;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2.  Runs every ms ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	; Increment the timers for each FSM. That is all we do here!
	inc FSM_timer 
	reti

; Look-up table for the 7-seg displays. (Segments are turn on with zero) 
T_7seg:
    DB 40H, 79H, 24H, 30H, 19H, 12H, 02H, 78H, 00H, 10H

; Displays a BCD number pased in R0 in HEX1-HEX0
Display_BCD_7_Seg_HEX10:
	mov dptr, #T_7seg

	mov a, R0
	swap a
	anl a, #0FH
	movc a, @a+dptr
	mov HEX1, a
	
	mov a, R0
	anl a, #0FH
	movc a, @a+dptr
	mov HEX0, a
	
	ret

; Displays a BCD number pased in R0 in HEX3-HEX2
Display_BCD_7_Seg_HEX32:
	mov dptr, #T_7seg

	mov a, R0
	swap a
	anl a, #0FH
	movc a, @a+dptr
	mov HEX3, a
	
	mov a, R0
	anl a, #0FH
	movc a, @a+dptr
	mov HEX2, a
	
	ret

; Displays a BCD number pased in R0 in HEX5-HEX4
Display_BCD_7_Seg_HEX54:
	mov dptr, #T_7seg

	mov a, R0
	swap a
	anl a, #0FH
	movc a, @a+dptr
	mov HEX5, a
	
	mov a, R0
	anl a, #0FH
	movc a, @a+dptr
	mov HEX4, a
	
	ret

; The 8-bit hex number passed in the accumulator is converted to
; BCD and stored in [R1, R0]
Hex_to_bcd_8bit:
	mov b, #100
	div ab
	mov R1, a   ; After dividing, a has the 100s
	mov a, b    ; Remainder is in register b
	mov b, #10
	div ab ; The tens are stored in a, the units are stored in b 
	swap a
	anl a, #0xf0
	orl a, b
	mov R0, a
	ret

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

Send2DigitBCD:
    mov R0, a

    anl a, #0F0H        ; upper
    swap a
    add a, #'0'
    lcall putchar

    mov a, R0
    anl a, #0FH         ; lower
    add a, #'0'
    lcall putchar

    ret

;-------MACROS--------------------;
;Example macro to help with process %0,1,etc represents the input number, this is all pass by reference(i.e it can actually affect the variable)

ADD_16 MAC
    ADD A, %0     ; Add low byte
    MOV R2, A       ; Store result back in low var
    MOV A, R1       ; Move existing high byte to A
    ADDC A, %1     ; Add high byte with carry
    MOV R1, A       ; Store back in R1
ENDMAC


tempConv_cold MAC
	; Load 32-bit 'x' with 12-bit adc result
	mov x+3, #0
	mov x+2, #0
	mov x+1, ADC_H
	mov x+0, ADC_L

	Load_y(50300) ; VCC voltage measured
	lcall mul32
	Load_y(4096)
	lcall div32
	Load_y(27300)
	lcall sub32
	Load_y(100)
	lcall mul32

	lcall hex2bcd
ENDMAC

tempConv_hot MAC
	; Load 32-bit 'x' with 12-bit adc result
	mov x+3, #0
	mov x+2, #0
	mov x+1, ADC_H
	mov x+0, ADC_L

	Load_y(12288)   ; gain constant
	lcall mul32
	
	Load_y(4096)
	lcall div32

	lcall hex2bcd
ENDMAC

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;

main:
	; Initialization of hardware
    mov SP, #0x7F
    lcall Timer2_Init
    lcall ELCD_4BIT ; Configure LCD in four bit mode
    ; Turn off all the LEDs
    mov LEDRA, #0 ; LEDRA is bit addressable
    mov LEDRB, #0 ; LEDRB is NOT bit addresable
    setb EA   ; Enable Global interrupts
    
    ; Initialize variables
    mov FSM_state, #0

	;;Testing;;
    ADD_16(#1, #2) ; This "expands" into the 5 lines above
	; After initialization the program stays in this 'forever' loop
loop:
	
	mov ADC_C, #LM335_ADC
	tempConv_cold
	mov tempCold, bcd

	mov ADC_C, #OP07_ADC
	tempConv_hot
	mov tempHOT, bcd

	mov x, tempHot
	mov y, tempCold
	lcall add32
	mov tempFinal, x




; sends to putty
    mov a, bcd+2
    lcall Send2DigitBCD
    mov a, bcd+1
    lcall Send2DigitBCD
    mov a, bcd+0
    lcall Send2DigitBCD
		
	mov a, #'\n'
    lcall putchar

;-------------------------------------------------------------------------------
;FSM
;-------------------------------------------------------------------------------
; non-blocking FSM for the one second counter starts here.
	mov a, FSM_state
	mov LEDRA, #0

FSM_state0:
	cjne a, #0, FSM_state1
	setb LEDRA.0 ; We are using the LEDs to debug in what state is this machine
	mov a, FSM_timer
	cjne a, #250, FSM_done ; 250 ms passed? (Since we are usend an 8-bit variable, we need to count 250 ms four times)
	mov FSM_timer, #0
	inc FSM_state
	sjmp FSM_done

FSM_state1:	
	cjne a, #1, FSM_state2
	setb LEDRA.1
	mov a, FSM_timer
	cjne a, #250, FSM_done ; 250 ms passed?
	mov FSM_timer, #0
	inc FSM_state
	sjmp FSM_done

FSM_state2:	
	cjne a, #2, FSM_state3
	setb LEDRA.2
	mov a, FSM_timer
	cjne a, #250, FSM_done ; 250 ms passed?
	mov FSM_timer, #0
	inc FSM_state
	sjmp FSM_done

FSM_state3:	
	cjne a, #3, FSM_done
	setb LEDRA.3
	mov a, FSM_timer
	cjne a, #250, FSM_done ; 250 ms passed?
	mov FSM_timer, #0
	mov FSM_state, #0
	mov a, Count3
	cjne a, #59, IncCount3 ; Don't let the seconds counter pass 59
	mov Count3, #0
	sjmp DisplayCount3
IncCount3:
	inc Count3
DisplayCount3:
    mov a, Count3
    lcall Hex_to_bcd_8bit
	lcall Display_BCD_7_Seg_HEX54
	mov FSM_state, #0
FSM_done:
;-------------------------------------------------------------------------------
ljmp loop
END







