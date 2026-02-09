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
TIMER0_RATE     EQU 1024    ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD   EQU ((65536-(CLK/TIMER0_RATE)))
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
    
    
; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

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
timeOn:     ds 2
;Variables from keypad
soak_temp:      ds 2      ; mode A 150 +-20
soak_time:      ds 2      ; mode B 60-120
reflow_temp:    ds 2      ; mode C 230 < 240
reflow_time:    ds 2      ; mode D  30 < 45
Timer0Reload:   ds 2

; Each FSM has its own timer
FSM_timer:  ds 2
QuarterSecondsTimeCounter: ds 1
; Each FSM has its own state counter
FSM_state:  ds 1
; Three counters to display.
Count3:     ds 1 ; Incremented every second. Reset to zero when KEY3 is pressed.

bseg
; For each pushbutton we have a flag.  The corresponding FSM will set this
; flags to one when a valid press of the pushbutton is detected.
mf       :  dbit 1
ssr_f    :  dbit 1

$include(math32.asm)
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$include(Read_Keypad.asm)

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
SSR_PIN equ P0.0
START_BUTTON equ P0.2
SOUND_OUT equ P0.4

cseg
;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; 11110000 Clear the bits for timer 0
	orl a, #0x01 ; 00000001 Configure timer 0 as 16-timer
	mov TMOD, a
	
	mov TH0, Timer0Reload+1
	mov TL0, Timer0Reload+0
	
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz wave at pin SOUND_OUT   ;
;---------------------------------;

Timer0_ISR:
	clr TR0
	mov TH0, Timer0Reload+1
	mov TL0, Timer0Reload+0
	setb TR0
	cpl SOUND_OUT ; Connect speaker the pin assigned to 'SOUND_OUT'!
	reti

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
	
	mov a, FSM_timer
	
	cjne a, #250, FSM_timer_done
	inc QuarterSecondsTimeCounter
	mov FSM_timer, #0x00
	
	FSM_timer_done:
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

powerPercent MAC
	;Convert percentage of time into a time it needs to be on %0 is percentage(i.e 20 is 20%) on, %1 is total time, %2 is the time on
	load_x(%0)
	;converts x to a percentage through fractions
	load_y(%1)
	lcall mul32
	
	load_y(100)
	lcall div32
	
	mov %2, x
ENDMAC

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;

main:
	mov P0MOD, #0x01 ;configures P0.0

	; Stops interupts for speaker
	clr TR0
    clr ET0
    
    mov QuarterSecondsTimeCounter, #0x00

	; Speaker frequency
	mov Timer0Reload+1, #high(TIMER0_RELOAD)
	mov Timer0Reload+0, #low(TIMER0_RELOAD)
	
	mov SP, #7FH ; Set the beginning of the stack (more on this later)
	mov LEDRA, #0 ; Turn off all unused LEDs (Too bright!)
	mov LEDRB, #0
	
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
	clr SSR_PIN
	clr mf
	;May have to reset the other vars idk to tbh
	
loop:

	; skips over test code
	sjmp ADCcheck

	; Oven Test code START -------------------------------------
	; ON OFF SWITCH OVEN ON PIN P0.0
		clr a
		mov a, SWA
		
		anl a, #0x01
		cjne a, #0x01, done2
		
		setb LEDRA.0
		setb SSR_PIN
		
		sjmp done3
		
		done2:
		clr SSR_PIN
		clr LEDRA.0
		
		done3:
		sjmp loop
		
	; Oven Test code END  -------------------------------------
	ADCcheck:
	
	
	mov ADC_C, #LM335_ADC
	tempConv_cold ; Macro call
	mov tempCold, bcd

	mov ADC_C, #OP07_ADC
	tempConv_hot ; Macro call
	mov tempHot, bcd

	mov x, tempHot
	mov y, tempCold
	lcall add32
	mov tempFinal, x

	;Keypad Setup
	mov active_param, #0
    lcall Load_Param_Into_BCD

    lcall Configure_Keypad_Pins



	ljmp FSMcheck ; Skips putty straight into FSM for now

; sends to putty
	    mov a, bcd+2
	    lcall Send2DigitBCD
	    mov a, bcd+1
	    lcall Send2DigitBCD
	    mov a, bcd+0
	    lcall Send2DigitBCD
			
		mov a, #'\n'
	    lcall putchar


FSMcheck:
;-------------------------------------------------------------------------------
;FSM
;-------------------------------------------------------------------------------
; non-blocking FSM for the one second counter starts here.
	mov a, FSM_state
	mov LEDRA, #0

FSM_state0:
	;Only moves on to state 1 once start button is pressed
	cjne a, #0, FSM_state1

	lcall Keypad       ; Scan keypad
    lcall Display      ; Update HEX displays (or later, LCD)
    jnc noChange

    lcall Shift_Digits_Left 

	noChange:
	setb LEDRA.0 ; We are using the LEDs to debug in what state is this machine
	clr SSR_PIN

	jb SWA.0, FSM_done_state_0_skip
	
	jb START_BUTTON, FSM_done_state_0_Continue; only moves on when button is high (might be active low)
	sjmp FSM_done_state_0_Skip
	FSM_done_state_0_Continue:
	ljmp FSM_done
	FSM_done_state_0_Skip:
	
	inc FSM_state
	ljmp FSM_done

FSM_state1:	
	;Only move to next stat if temp > 150c
	cjne a, #1, FSM_state2
	setb LEDRA.1

	setb SSR_PIN

	;if temp > 150
	load_x(tempFinal)
	load_y(soak_temp)
	lcall x_gt_y ;returns a mf of 1 if true (i.e x > y)
	
	jb SWA.1, FSM_done_state_1_skip
	
	jnb mf, FSM_done_state_1_Continue 
	sjmp FSM_done_state_1_Skip
	FSM_done_state_1_Continue:
	ljmp FSM_done
	FSM_done_state_1_Skip:
	
	mov QuarterSecondsTimeCounter, #0x00
	inc FSM_state
	ljmp FSM_done

FSM_state2:	
	;state management
	cjne a, #2, FSM_state3_continue_move
	sjmp FSM_state3_skip_move
	FSM_state3_continue_move:
	ljmp FSM_state3
	FSM_state3_skip_move:
	
	
	setb LEDRA.2

	powerPercent(20, soak_time, timeOn)
	;While time is < timeOn ssr remains on, otherwise off
	load_x(QuarterSecondsTimeCounter)
	load_y(4)
	lcall mul32 
	load_y(timeOn)
	jnb mf, ssr_off
	setb SSR_PIN
	sjmp ssr_on

	ssr_off:
		clr SSR_PIN

	ssr_on:

	;If time in this state > soak time then we move on
	load_x(QuarterSecondsTimeCounter)
	load_y(4)
	lcall mul32 
	load_y(soak_time)
	lcall x_gt_y ;returns a mf of 1 if true (i.e x > y)
	
	jb SWA.2, FSM_done_state_2_skip
	
	jb mf, FSM_done_state_2_Continue
	sjmp FSM_done_state_2_Skip
	FSM_done_state_2_Continue:
	ljmp FSM_done
	FSM_done_state_2_Skip:
	
	inc FSM_state
	ljmp FSM_done

FSM_state3:	
	;Only moves on when the temp is > 220c
	cjne a, #3, FSM_state4
	setb LEDRA.3

	setb SSR_PIN

	;if temp > 150
	load_x(reflow_temp)
	load_y(tempFinal)
	lcall x_gt_y ;returns a mf of 1 if true (i.e x > y)
	
	jb SWA.3, FSM_done_state_3_skip
	
	jb mf, FSM_done_state_3_Continue 
	sjmp FSM_done_state_3_Skip
	FSM_done_state_3_Continue:
	ljmp FSM_done
	FSM_done_state_3_Skip:
	
	inc FSM_state
	ljmp FSM_done

FSM_state4:	
	;only moves on after 45s
	cjne a, #4, FSM_state5_continue_move
	sjmp FSM_state5_skip_move
	FSM_state5_continue_move:
	ljmp FSM_state5
	FSM_state5_skip_move:
	
	
	setb LEDRA.4

	powerPercent(20, reflow_time, timeOn)
	;While time is < timeOn ssr remains on, otherwise off
	load_x(QuarterSecondsTimeCounter)
	load_y(4)
	lcall mul32 
	load_y(timeOn)
	jnb mf, ssr_off1
	setb SSR_PIN
	sjmp ssr_on1

	ssr_off1:
		clr SSR_PIN

	ssr_on1:

	;If time in this state > soak time then we move on
	load_x(QuarterSecondsTimeCounter)
	load_y(4)
	lcall mul32 
	load_y(reflow_time)
	lcall x_gt_y ;returns a mf of 1 if true (i.e x > y)
	jnb mf, FSM_done
	inc FSM_state
	ljmp FSM_done

FSM_state5:	
	;only resets when temp is < 60c
	cjne a, #5, FSM_done
	setb LEDRA.5

	clr SSR_PIN

	load_x(tempFinal)
	load_y(60)
	lcall x_lt_y ;returns a mf of 1 when (x < y)
	jnb mf, FSM_done
	mov FSM_state, #0x00

FSM_done:

;-------------------------------------------------------------------------------
ljmp loop
END




























