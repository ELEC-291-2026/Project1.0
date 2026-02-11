; main project file
$NOLIST
$MODMAX10
$LIST


CLK           	EQU 33333333 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   	EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER0_RELOAD 	EQU ((65536-(CLK/(12*TIMER0_RATE))))
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

Profile:  db 'Profile,', 0
Comma:    db ',', 0

dseg at 0x30
; For math 
x:			ds 4
y:			ds 4
bcd:		ds 5

math_space: ds 5

tempHot:	ds 4
tempCold:	ds 4

V_tc: ds 4
V_cj: ds 4
tempFinal:  ds 4
timeOn:     ds 2
;Variables from keypad
soak_temp:      ds 2      ; mode A 150 +-20
soak_time:      ds 2      ; mode B 60-120
soak_time_hex: 	ds 2
reflow_temp:    ds 2      ; mode C 230 < 240
reflow_time:    ds 2      ; mode D  30 < 45
reflow_time_hex: ds 2
active_param:   ds 1

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
QuarterSecondsFlag : dbit 1
State0Flag : dbit 1

$include(math32.asm)
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$include(keypad_lib_3.asm)
$include(temperature_lib.asm)

cseg
; These 'equ' must match the wiring between the DE10Lite board and the LCD!
ELCD_RS equ P1.7
ELCD_E  equ P1.1
ELCD_D4 equ P0.7
ELCD_D5 equ P0.5
ELCD_D6 equ P0.3
ELCD_D7 equ P0.1
SSR_PIN equ P0.0
START_BUTTON equ P0.2
SOUND_OUT equ P0.4


Initial_Message:  db 'Tmperature Test', 0

cseg
;----------------------FUNCTIONS----------------
;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; 11110000 Clear the bits for timer 0
	orl a, #0x01 ; 00000001 Configure timer 0 as 16-timer
	mov TMOD, a
	
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.  Runs every ms ;
;---------------------------------;
Timer0_ISR:
	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0
	
	; Increment the timers for each FSM. That is all we do here!
	inc FSM_timer 
	
	mov a, FSM_timer
	cjne a, #250, FSM_timer_done
	
	setb QuarterSecondsFlag
	
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

;---------------------------------;
; Initialize Serial Port          ;
;---------------------------------;
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
	
	
;We should probably start using this from now on oh well live laugh love
Mov_A_to_B MAC
;%0 is A, %1 is B
	mov %1+0, %0+0
	mov %1+1, %0+1
	mov %1+2, #0
	mov %1+3, #0
ENDMAC
	
Over_Under_Check_Rewrite:

	underflow_soaktemp:
		Mov_A_to_B(soak_temp, bcd)
		lcall bcd2hex
		load_y(130) ; Our min temp
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_soaktemp_check
		load_x(130)
	    lcall hex2bcd
	    mov soak_temp+0, 	bcd+0    ; mode A 150 +-20
	    mov soak_temp+1, 	bcd+1
	underflow_soaktemp_check:

	overflow_soaktemp:
		;Max temp check for 
		Mov_A_to_B(soak_temp,bcd)
		lcall bcd2hex
		load_y(170) ; Our max temp
		lcall x_gt_y ;mf 1 if true
		jnb mf, overflow_soaktemp_check
		load_x(170)
	    lcall hex2bcd
	    mov soak_temp+0, 	bcd+0    ; mode A 150 +-20
	    mov soak_temp+1, 	bcd+1
	overflow_soaktemp_check:

	underflow_soaktime:
		;Max temp check for 
		Mov_A_to_B(soak_time,bcd)
		lcall bcd2hex
		load_y(60) ; Our min time
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_soaktime_check
		load_x(60)
		lcall hex2bcd
	    mov soak_time+0, 	bcd+0    ;mode B 60 < t < 120
	    mov soak_time+1, 	bcd+1
	underflow_soaktime_check:

	overflow_soaktime:
		;Max temp check for 
		Mov_A_to_B(soak_time,bcd)
		lcall bcd2hex
		load_y(120) ; Our max time
		lcall x_gt_y ;mf 1 if true
		jnb mf, overflow_soaktime_check
		load_x(120)
		lcall hex2bcd
	    mov soak_time+0, 	bcd+0    ;mode B 60 < t < 120
	    mov soak_time+1, 	bcd+1
	overflow_soaktime_check:

	;----Reflux Checks-----------------------
	underflow_reflowtemp:
		;Min temp check for 
		Mov_A_to_B(reflow_temp, bcd)
		lcall bcd2hex
		load_y(230) ; Our min temp for reflux
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_reflowtemp_check
		load_x(230)
	    lcall hex2bcd
	    mov reflow_temp+0, 	bcd+0    ;  mode C 230 < t < 240
	    mov reflow_temp+1, 	bcd+1
	underflow_reflowtemp_check:

	overflow_reflowtemp:
		;Max temp check for 
		Mov_A_to_B(reflow_temp,bcd)
		lcall bcd2hex
		load_y(240) ; Our max temp
		lcall x_gt_y ;mf 1 if true
		jnb mf, overflow_reflowtemp_check
		load_x(240)
	    lcall hex2bcd
	    mov reflow_temp+0, 	bcd+0    ; mode C 230 < t < 240
	    mov reflow_temp+1, 	bcd+1
	overflow_reflowtemp_check:

	underflow_reflowtime:
		;Max temp check for 
		Mov_A_to_B(reflow_time,bcd)
		lcall bcd2hex
		load_y(30) ; Our max temp
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_reflowtime_check
		load_x(30)
		lcall hex2bcd
	    mov reflow_time+0, 	bcd+0    ; mode D  30 < 45
	    mov reflow_time+1, 	bcd+1
	underflow_reflowtime_check:

	overflow_reflowtime:
		;Max temp check for 
		Mov_A_to_B(reflow_time,bcd)
		lcall bcd2hex
		load_y(45) ; Our max temp
		lcall x_gt_y ;mf 1 if true
		jnb mf, overflow_reflowtime_check
		load_x(45)
		lcall hex2bcd
	    mov reflow_time+0, 	bcd+0    ; mode D  30 < 45
	    mov reflow_time+1, 	bcd+1
	overflow_reflowtime_check:

	ret



;-------MACROS--------------------;
Load_X_Var32 MAC
mov x+0, %0+0
mov x+1, %0+1
mov x+2, %0+2
mov x+3, %0+3
ENDMAC

Load_Y_Var32 MAC
mov y+0, %0+0
mov y+1, %0+1
mov y+2, %0+2
mov y+3, %0+3
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

powerPercent MAC
	mov x+0, %0
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0
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
    lcall Timer0_Init    ; Changed from Timer2_Init to Timer0_Init
    lcall InitSerialPort ; Initialize serial port on Timer 1
    lcall ELCD_4BIT ; Configure LCD in four bit mode
    
   	mov SP, #7FH
	mov LEDRA, #0
	mov LEDRB, #0
   	
   	; Initialize variables
    mov FSM_state, #0x00
	clr SSR_PIN
	clr mf
	clr ssr_f
	setb state_flag
	clr QuarterSecondsFlag
	setb State0Flag
	
	mov MinutesCounterTotal, #0x00
	mov SecondsCounterTotal, #0x00
    mov QuarterSecondsCounter, #0x00
    
    load_x(300)
    lcall hex2bcd
    mov soak_temp+0, 	bcd+0
    mov soak_temp+1, 	bcd+1

	mov soak_time+0, 	#0
	mov soak_time+1, 	#0
	
	mov reflow_temp+0,  #0
	mov reflow_temp+1,  #0
	
	mov reflow_time+0,  #0
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

	setb EA ;enables global interupts
	
	ret
	
	
main:
	mov P0MOD, #10101011b
    mov P1MOD, #10000010b
	lcall Initial_ALL
	
	mov P0MOD, #10101010b
    mov P1MOD, #10000010b

    lcall ELCD_4BIT
	
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
	
	mov dptr, #Initial_Message
	lcall SendString
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	
	mov ADC_C, #0x80
	lcall Wait25ms
	
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
		
		Load_X_Var8(MinutesCounterTotal)
		lcall hex2bcd
		mov R0, bcd+0
		lcall Display_BCD_7_Seg_HEX54
		
		setb EA
	
	skip_debug_stuff:


	jb State0Flag, skiptemptemptemp
	jnb QuarterSecondsFlag, skiptemptemptemp
	sjmp skiptemoteteipj
	skiptemptemptemp:
	
	ljmp skiptemptemptemptemp
	skiptemoteteipj:
	
	clr QuarterSecondsFlag
	clr EA
    mov ADC_C, #LM335_ADC

    mov x+3, #0
    mov x+2, #0
    mov x+1, ADC_H
    mov x+0, ADC_L

    Load_y(5000)
    lcall mul32
    Load_y(4096)
    lcall div32
    
    mov V_tc+0, x+0
    mov V_tc+1, x+1
    mov V_tc+2, x+2
    mov V_tc+3, x+3

    mov ADC_C, #OP07_ADC

    mov x+3, #0
    mov x+2, #0
    mov x+1, ADC_H
    mov x+0, ADC_L

    Load_y(5000)
    lcall mul32
    Load_y(4096)
    lcall div32

    Load_y(10)
    lcall div32
    Load_y(273)
    lcall sub32
    
    mov V_cj+0, x+0
    mov V_cj+1, x+1
    mov V_cj+2, x+2
    mov V_cj+3, x+3

    mov x+0, V_tc+0
    mov x+1, V_tc+1
    mov x+2, V_tc+2
    mov x+3, V_tc+3

    Load_y(10000)
    lcall mul32
    Load_y(12300)
    lcall div32

    mov y+0, x+0
    mov y+1, x+1
    mov y+2, x+2
    mov y+3, x+3

    mov x+0, V_cj+0
    mov x+1, V_cj+1
    mov x+2, V_cj+2
    mov x+3, V_cj+3
    
    push y+0
    push y+1
    push y+2
    push y+3
    
    Load_y(10)
    lcall mul32
    
    pop y+3
    pop y+2
    pop y+1
    pop y+0
    
    lcall add32
    
    mov tempFinal+0, x+0
    mov tempFinal+1, x+1
    mov tempFinal+2, x+2
    mov tempFinal+3, x+3

    lcall hex2bcd
    lcall Display_Voltage_7seg
    lcall Display_Voltage_LCD
    lcall Display_Voltage_Serial
    
	setb EA
	
	skiptemptemptemptemp:
    

	jb State0Flag, skip_button
	jb START_BUTTON, skip_button
	lcall Wait25ms
	jb START_BUTTON, skip_button
	jnb START_BUTTON, $
	
		mov FSM_state, #0x00
	skip_button:

    
;-------------------------------------------------------------------------------
;FSM
;-------------------------------------------------------------------------------

	jnb state_flag, no_new_state
	
	clr state_flag
	clr EA
	mov SecondsCounter, #0x00
	setb EA
	no_new_state:

	mov LEDRA, #0

FSM_state0:
	mov a, FSM_state
	cjne a, #0, FSM_state1_continue_move
	sjmp FSM_state1_skip_move
	
	FSM_state1_continue_move:
	ljmp FSM_state1
	
	FSM_state1_skip_move:
	setb LEDRA.0
	clr SSR_PIN
	setb State0Flag
	
	clr EA
	lcall Keypad
    lcall Display
    jnc  skip_keypad
    lcall Shift_Digits_Left
   
	skip_keypad:
		setb EA
	
	jb SWA.0, FSM_done_state_0_skip
	
	jb START_BUTTON, FSM_done_state_0_Continue
	lcall Wait25ms
	jb START_BUTTON, FSM_done_state_0_Continue
	jnb START_BUTTON, $
		sjmp FSM_done_state_0_Skip
		
	FSM_done_state_0_Continue:
		ljmp FSM_done
		
	FSM_done_state_0_Skip:
		
		clr EA
		lcall Over_Under_Check_Rewrite
		lcall WriteInitialVals
		setb EA
	
		mov active_param, #0
	
		setb state_flag
		clr State0Flag
		inc FSM_state
	ljmp FSM_done

FSM_state1:	
	mov a, FSM_state
	cjne a, #1, FSM_state2_continue_move
	sjmp FSM_state2_skip_move
	
	FSM_state2_continue_move:
	ljmp FSM_state2
	
	FSM_state2_skip_move:
	
	setb LEDRA.1

	setb SSR_PIN

	clr EA
	
	load_x(60)
	Load_Y_Var8(SecondsCounter)
	lcall x_gt_y
	jnb mf, emergency_check
	clr mf
	
	Load_X_Var32(tempFinal)
	load_y(50)
	lcall x_lt_y
	jnb mf, emergency_check
	mov FSM_State, #0x00
	emergency_check:

	clr mf
	
	mov bcd+0, soak_temp+0
    mov bcd+1, soak_temp+1
    mov bcd+2, #0
    mov bcd+3, #0
    mov bcd+4, #0
    lcall bcd2hex
    
    load_y(10)
    
    lcall mul32
        
    mov y+0, x+0
    mov y+1, x+1
    mov y+2, x+2
    mov y+3, x+3
    
    Load_X_Var32(tempFinal)

	clr mf
	lcall x_gt_y
	
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
	mov a, FSM_state
	cjne a, #2, FSM_state3_continue_move
	sjmp FSM_state3_skip_move
	
	FSM_state3_continue_move:
	ljmp FSM_state3
	
	FSM_state3_skip_move:
	setb LEDRA.2
	
	clr EA
	
	mov bcd+0, soak_time+0
    mov bcd+1, soak_time+1
    mov bcd+2, #0
    mov bcd+3, #0
    mov bcd+4, #0
    lcall bcd2hex
        
    mov soak_time_hex+0, x+0
    mov soak_time_hex+1, x+1
    
	powerPercent(#20, soak_time, timeOn)
	
	Load_X_Var8(SecondsCounter)	
	Load_Y_Var16(timeOn)
	clr mf
	lcall x_gt_y
	setb EA
	jnb mf, ssr_off
	clr SSR_PIN
	sjmp ssr_on

	ssr_off:
		setb SSR_PIN
	ssr_on:
	
	clr EA
	Load_X_Var8(SecondsCounter) 
	Load_Y_Var16(soak_time_hex)
	clr mf  
	lcall x_gt_y
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
	mov a, FSM_state
	cjne a, #3, FSM_state4
	setb LEDRA.3

	setb SSR_PIN

	clr EA
	
	mov bcd+0, reflow_temp+0
    mov bcd+1, reflow_temp+1
    mov bcd+2, #0
    mov bcd+3, #0
    mov bcd+4, #0
    lcall bcd2hex
    
    load_y(10)
    
    lcall mul32
        
    mov y+0, x+0
    mov y+1, x+1
    mov y+2, x+2
    mov y+3, x+3
	
	Load_Y_Var32(tempFinal)
	clr mf
	lcall x_gt_y
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

	mov a, FSM_state
	cjne a, #4, FSM_state5_continue_move
	sjmp FSM_state5_skip_move
	FSM_state5_continue_move:
	ljmp FSM_state5
	FSM_state5_skip_move:
	
	setb LEDRA.4
	
	clr EA
	mov bcd+0, reflow_time+0
    mov bcd+1, reflow_time+1
    mov bcd+2, #0
    mov bcd+3, #0
	mov bcd+4, #0
    lcall bcd2hex
        
    mov reflow_time_hex+0, x+0
    mov reflow_time_hex+1, x+1
    
	powerPercent(#20, reflow_time_hex, timeOn)
	Load_X_Var8(SecondsCounter)
	Load_Y_Var16(timeOn) 
	clr mf  
	lcall x_gt_y 
	
	setb EA
	jnb mf, ssr_off1
	clr SSR_PIN
	sjmp ssr_on1

	ssr_off1:
		setb SSR_PIN
	ssr_on1:

	clr EA

	Load_X_Var16(reflow_time_hex)
	Load_Y_Var8(SecondsCounter)
	clr mf
	lcall x_gt_y
	setb EA
	
	jb SWA.4, FSM_done_state_4_Skip
	jb mf, FSM_done
	
	FSM_done_state_4_Skip:
	
		setb state_flag
		inc FSM_state
	ljmp FSM_done

FSM_state5:	
	
	mov a, FSM_state
	cjne a, #5, FSM_done
	setb LEDRA.5

	clr SSR_PIN
	
	clr EA
	Load_X_Var32(tempFinal)
	load_y(600) ; Not already multiplied by 10
	clr mf
	lcall x_lt_y
	setb EA
	
	jb SWA.5, FSM_done_state_5_Skip
	jnb mf, FSM_done
	
	FSM_done_state_5_Skip:
	
		setb state_flag
		mov FSM_state, #0x00

	FSM_done:

	ljmp loop

END
