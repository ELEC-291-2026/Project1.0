; main project file
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

math_space: ds 5

tempHot:	ds 4
tempCold:	ds 4
tempFinal:  ds 4
timeOn:     ds 2
;Variables from keypad
soak_temp:      ds 2      ; mode A 150 +-20
soak_time:      ds 2      ; mode B 60-120
reflow_temp:    ds 2      ; mode C 230 < 240
reflow_time:    ds 2      ; mode D  30 < 45
active_param:   ds 1

Timer0Reload:   ds 2

; Each FSM has its own timer
FSM_timer:  ds 1
QuarterSecondsCounter: ds 1
SecondsCounter: ds 1
SecondsCounterTotal: ds 1
MinutesCounterTotal: ds 1
; Each FSM has its own state counter
FSM_state:  ds 1

bseg
; For each pushbutton we have a flag.  The corresponding FSM will set this
; flags to one when a valid press of the pushbutton is detected.
mf       	: dbit 1
ssr_f    	: dbit 1
state_flag	: dbit 1

$include(math32.asm)
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$include(keypad_lib_2.asm)

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
	
	inc QuarterSecondsCounter
	mov FSM_timer, #0x00
	
	mov a, QuarterSecondsCounter
	cjne a, #4, FSM_timer_done
	
	mov QuarterSecondsCounter, #0x00
	inc SecondsCounter
	inc SecondsCounterTotal ; USE THIS FOR THE TOTAL TIMER. IT NEVER RESETS SO DONT WORRY
	
	mov a, SecondsCounterTotal
	cjne a, #60, FSM_timer_done
	inc MinutesCounterTotal
	mov SecondsCounterTotal, #0x00
	
	FSM_timer_done:
	reti

; Look-up table for the 7-seg displays. (Segments are turn on with zero) 
T_7seg:
    DB 0C0H, 0F9H, 0A4H, 0B0H, 099H, 092H, 082H, 0F8H, 080H, 090H

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


;-------MACROS--------------------;
;Example macro to help with process %0,1,etc represents the input number, this is all pass by reference(i.e it can actually affect the variable)

ADD_16 MAC
    ADD A, %0     ; Add low byte
    MOV R2, A       ; Store result back in low var
    MOV A, R1       ; Move existing high byte to A
    ADDC A, %1     ; Add high byte with carry
    MOV R1, A       ; Store back in R1
ENDMAC

Load_X_Var16 MAC
mov x+0, %0+0
mov x+1, %0+1
mov x+2, #0
mov x+3, #0
ENDMAC

Load_Y_Var16 MAC
mov y+0, %0+0
mov y+1, %0+1
mov y+2, #0
mov y+3, #0
ENDMAC

Load_X_Var8 MAC
    
mov x+0, %0+0
mov x+1, #0
mov x+2, #0
mov x+3, #0
ENDMAC

Load_Y_Var8 MAC
    
mov y+0, %0+0
mov y+1, #0
mov y+2, #0
mov y+3, #0
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

ENDMAC

powerPercent MAC
	;Convert percentage of time into a time it needs to be on %0 is percentage(i.e 20 is 20%) on, %1 is total time, %2 is the time on
	;load_x(%0)
	mov x+0, %0
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0
	;converts x to a percentage through fractions
	Load_Y_Var16(%1)
	lcall mul32
	
	load_y(100)
	lcall div32
	
	mov %2+0, x+0
	mov %2+1, x+1
ENDMAC

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;

Initial_ALL:

   	clr EA ;disables global interupts
   	
   	; Initialization of hardware
    lcall Timer2_Init
    lcall ELCD_4BIT ; Configure LCD in four bit mode
    ; Turn off all the LEDs
   	
   	mov SP, #7FH ; Set the beginning of the stack (more on this later)
	mov LEDRA, #0 ; Turn off all unused LEDs (Too bright!)
	mov LEDRB, #0
	mov SP, #0x7F
   	
   	
   	; Initialize variables
    mov FSM_state, #0x00
	clr SSR_PIN
	clr mf
	clr ssr_f
	setb state_flag ;tells the de10-lite its a new state
	
	mov MinutesCounterTotal, #0x00
	mov SecondsCounterTotal, #0x00
    mov QuarterSecondsCounter, #0x00
    
    
    mov soak_temp+0, 	#150    ; mode A 150 +-20
    mov soak_temp+1, 	#0
	mov soak_time+0, 	#5     ; mode B 60-120
	mov soak_time+1, 	#0
	mov reflow_temp+0,  #130		; mode C 230 < 240
	mov reflow_temp+1,  #0
	mov reflow_time+0,  #5 	; mode D  30 < 45
	mov reflow_time+1,  #0
	
	mov tempFinal+0, #0
	mov tempFinal+1, #0
	mov tempFinal+2, #0
	mov tempFinal+3, #0
	
	mov tempCold+0, #0
	mov tempCold+1, #0
	mov tempCold+2, #0
	mov tempCold+3, #0
	
	mov tempHot+0, #0
	mov tempHot+1, #0
	mov tempHot+2, #0
	mov tempHot+3, #0
	
	mov active_param, #0
		
	clr EA
    lcall Load_Param_Into_BCD
    lcall Configure_Keypad_Pins
    setb EA

	
	; Speaker frequency
	mov Timer0Reload+1, #high(TIMER0_RELOAD)
	mov Timer0Reload+0, #low(TIMER0_RELOAD)
	
	
	; Stops interupts for speaker
	clr TR0
    clr ET0

	setb EA ;enables global interupts
	
	ret
	
	
main:
	mov P0MOD, #0x01 ;configures P0.0
	lcall Initial_ALL
	
loop:
	
	
	ljmp skip_debug_stuff 
	
	clr EA
	Load_X_Var8(SecondsCounter)
	lcall hex2bcd
	mov R0, bcd+0
	lcall Display_BCD_7_Seg_HEX10
	
	
	Load_X_Var8(SecondsCounterTotal)
	lcall hex2bcd
	mov R0, bcd+0
	lcall Display_BCD_7_Seg_HEX32
	
	;load_x(tempFinal)
	
	Load_X_Var8(MinutesCounterTotal)
	lcall hex2bcd
	mov R0, bcd+0
	lcall Display_BCD_7_Seg_HEX54
	
	setb EA
	
	skip_debug_stuff:

	
	; ALL TEMP MATH -------------------------
	clr EA
	mov ADC_C, #LM335_ADC
	tempConv_cold
	mov tempCold+0, x+0
	mov tempCold+1, x+1
	mov tempCold+2, x+2
	mov tempCold+3, x+3
	
	mov ADC_C, #OP07_ADC
	tempConv_hot
	mov tempHot+0, x+0
	mov tempHot+1, x+1
	mov tempHot+2, x+2
	mov tempHot+3, x+3
	
	; Add temperatures
	mov x+0, tempHot+0
	mov x+1, tempHot+1
	mov x+2, tempHot+2
	mov x+3, tempHot+3
	
	mov y+0, tempCold+0
	mov y+1, tempCold+1
	mov y+2, tempCold+2
	mov y+3, tempCold+3
	
	lcall add32
	
	mov tempFinal+0, x+0
	mov tempFinal+1, x+1
	mov tempFinal+2, x+2
	mov tempFinal+3, x+3
	setb EA
    
	
    
;-------------------------------------------------------------------------------
;FSM
;-------------------------------------------------------------------------------

; Clears second counter per state
	jnb state_flag, no_new_state
	
	clr state_flag
	clr EA
	mov SecondsCounter, #0x00
	setb EA
	no_new_state:

; non-blocking FSM for the one second counter starts here.
	mov a, FSM_state
	mov LEDRA, #0

FSM_state0:
	;Only moves on to state 1 once start button is pressed
	cjne a, #0, FSM_state1
	
	clr EA
	lcall Keypad        ; Scan keypad
    lcall Display       ; Update HEX displays (or later, LCD)
    jnc  skip_keypad        ; If C=0 -> no digit to insert (mode/backspace/clear/none)

    lcall Shift_Digits_Left  ; If C=1 -> numeric key; insert new digit from R7
   
   	skip_keypad:
	setb EA
	
	noChange:
	setb LEDRA.0 ; We are using the LEDs to debug in what state is this machine
	clr SSR_PIN

	jb SWA.0, FSM_done_state_0_skip
	
	jnb START_BUTTON, FSM_done_state_0_Continue; only moves on when button is high (might be active low)
	sjmp FSM_done_state_0_Skip
	FSM_done_state_0_Continue:
	ljmp FSM_done
	FSM_done_state_0_Skip:
	
	setb state_flag
	inc FSM_state
	ljmp FSM_done

FSM_state1:	
	;Only move to next stat if temp > 150c
	cjne a, #1, FSM_state2
	setb LEDRA.1

	setb SSR_PIN

	clr EA
	;If it didint reach 50 degrees in 60 seconds
	clear EA
	;If time > 60 check
	load_x(60)
	Load_Y_Var8(SecondsCounter)
	lcall x_gt_y
	jnb mf, emergency_check
	clr mf
	;Only check if time > 60 and if checks if temp is less then 50
	load_x(tempFinal)
	load_y(50)
	lcall x_lt_y
	jnb mf, emergency_check
	;If so it failed and we do an emergency abort
	mov FSM_State, #0x00
	emergency_check:

	clr mf
	
	;if temp > 150
	load_x(tempFinal)
	Load_Y_Var16(soak_temp)
	clr mf
	lcall x_gt_y ;returns a mf of 1 if true (i.e x > y)	
	
	setb EA
	
	jb SWA.1, FSM_done_state_1_skip
	
	jnb mf, FSM_done_state_1_Continue 
	sjmp FSM_done_state_1_Skip
	FSM_done_state_1_Continue:
	ljmp FSM_done
	FSM_done_state_1_Skip:
	
	setb state_flag
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
	
	clr EA
	powerPercent(#20, soak_time, timeOn)
	;While time is < timeOn ssr remains on, otherwise off
	Load_X_Var8(SecondsCounter)	
	Load_Y_Var16(timeOn)
	clr mf
	lcall x_gt_y
	setb EA
	jnb mf, ssr_off
	setb SSR_PIN
	sjmp ssr_on

	ssr_off:
		clr SSR_PIN
	ssr_on:
	

	;If time in this state > soak time then we move on
	clr EA
	Load_X_Var8(SecondsCounter) 
	Load_Y_Var16(soak_time)
	;load_y(10)
	clr mf  
	lcall x_gt_y     ; Use GE (Greater than or equal) for stability
	setb EA
	
	jb SWA.2, FSM_done_state_2_skip
	
	jnb mf, FSM_done_state_2_Continue
	sjmp FSM_done_state_2_Skip
	FSM_done_state_2_Continue:
	ljmp FSM_done
	FSM_done_state_2_Skip:
	
	setb state_flag
	inc FSM_state
	ljmp FSM_done

FSM_state3:	
	;Only moves on when the temp is > 220c
	cjne a, #3, FSM_state4
	setb LEDRA.3

	setb SSR_PIN

	;if temp > 150
	clr EA
	Load_X_Var16(reflow_temp)
	load_y(tempFinal)
	clr mf
	lcall x_gt_y ;returns a mf of 1 if true (i.e x > y)
	setb EA
	
	jb SWA.3, FSM_done_state_3_skip
	
	jb mf, FSM_done_state_3_Continue 
	sjmp FSM_done_state_3_Skip
	FSM_done_state_3_Continue:
	ljmp FSM_done
	FSM_done_state_3_Skip:
	
	setb state_flag
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
	
	clr EA
	powerPercent(#20, reflow_time, timeOn)
	;While time is < timeOn ssr remains on, otherwise off
	Load_X_Var8(SecondsCounter)
	Load_Y_Var16(timeOn)
	clr mf  
	lcall x_gt_y 
	
	setb EA
	jnb mf, ssr_off1
	setb SSR_PIN
	sjmp ssr_on1

	ssr_off1:
		clr SSR_PIN
	ssr_on1:

	;If time in this state > soak time then we move on
	clr EA
	;load_x(10)
	Load_X_Var16(reflow_time)
	Load_Y_Var8(SecondsCounter)
	clr mf
	lcall x_gt_y ;returns a mf of 1 if true (i.e x > y)
	setb EA
	
	
	jb SWA.4, FSM_done_state_4_Skip
	jb mf, FSM_done
	
	FSM_done_state_4_Skip:
	
	setb state_flag
	inc FSM_state
	ljmp FSM_done

FSM_state5:	
	;only resets when temp is < 60
	cjne a, #5, FSM_done
	setb LEDRA.5

	clr SSR_PIN
	
	clr EA
	load_x(tempFinal)
	load_y(60)
	clr mf
	lcall x_lt_y ;returns a mf of 1 when (x < y)
	setb EA
	
	jb SWA.5, FSM_done_state_5_Skip
	jnb mf, FSM_done
	
	FSM_done_state_5_Skip:
	
	setb state_flag
	mov FSM_state, #0x00

FSM_done:

;-------------------------------------------------------------------------------
ljmp loop

END
