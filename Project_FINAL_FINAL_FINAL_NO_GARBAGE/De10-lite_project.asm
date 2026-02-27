; main project file
; ------------------------------------------------------------------------------
; This is code for a PCB Oven
; This oven will be used to cook EFM8 board
; ------------------------------------------------------------------------------
; This Project was made for our UBC class ELEC 291
; This is Project 1 out of 2
; ------------------------------------------------------------------------------
; This project was made by the following people

;	- Owen Anderson 		 51069375
;	- Matthieu Moisan 		 68684836
;	- Guanyu Zhu 			 84606888
;	- Mouhsin Hussein 		 22297808
;	- Minh Cat Trieu Truong  41437583
;	- Khushaan Virk 		 47290044

; ------------------------------------------------------------------------------
; Date: FEB 4, 2026 to FEB 27, 2026
; ------------------------------------------------------------------------------


$NOLIST
$MODMAX10
$LIST


CLK           	EQU 33333333 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   	EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER0_RELOAD 	EQU ((65536-(CLK/(12*TIMER0_RATE))))
FREQ   			EQU 33333333
BAUD   			EQU 115200
T2LOAD 			EQU 65536-(FREQ/(32*BAUD)) ; For serial port

;PIN Assignemet
LM335_ADC 		EQU 0
OP07_ADC 		EQU 1


; Reset vector
org 0x0000
    ljmp main
    
; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; All messages 
Profile:  			db 'PROFILE,', 0
Comma:    			db ',', 0
Clear_Message:  	db '                ', 0
DONE:    			db 'DONE', 0

; State messages
S0_TXT: 			db 'INIT   ', 0
S1_TXT: 			db 'RAMP1  ', 0
S2_TXT: 			db 'SOAK   ', 0
S3_TXT: 			db 'RAMP2  ', 0
S4_TXT: 			db 'REFLOW ', 0
S5_TXT: 			db 'COOLS  ', 0

; Microwave mode messages
COOK_MICROWAVE: 	db 'COOKING', 0
DONE_MICROWAVE: 	db 'DONE   ', 0
CLEAR_MICROWAVE: 	db '       ', 0


dseg at 0x30
; For math 
x:						ds 4
y:						ds 4
bcd:					ds 5

; Memory space for the math functions
math_space: 			ds 5

; Temperature ADC reading
V_tc:       			ds 4 ; temperature reading of thermal wire
V_cj:       			ds 4 ; temperautre reading of LM335
tempFinal:  			ds 4 ; Final reading temp of both

; Time of when the SSR should be on for a fraction of the total time
; ie. SSR should be on for 20% of 60 seconds then this variable holds the 20% of 60 seconds
timeOn:     			ds 2

;Variables from keypad
soak_temp:       		ds 2 ; mode A 150 +-20
soak_time:       		ds 2 ; mode B 60-120
soak_time_hex: 	 		ds 2 ; used for math calculations
reflow_temp:     		ds 2 ; mode C 230 < 240
reflow_time:     		ds 2 ; mode D  30 < 45
reflow_time_hex: 		ds 2 ; used for math calculations
active_param:    		ds 1 ; what keyboard variable it's currently writing to

; Each FSM has its own timer
FSM_timer:  			ds 1 ; total ms that passed		
QuarterSecondsCounter: 	ds 1 ; total 250 ms that passed
SecondsCounter: 		ds 1 ; total seconds in a single state that passed
SecondsCounterTotal: 	ds 1 ; total time that passed throughout the whole FSM: seconds part
MinutesCounterTotal: 	ds 1 ; total time that passed throughout the whole FSM: minutes part

; CHANGE BUTTON mode tracker 
changeStateButton: 		ds 1 ; goes from mode 0-2

; microwave FSM
microwave_temp: 		ds 2 ; tells the temp it should hit
microwave_time: 		ds 2 ; tells the time the it should be on
temp_counter: 			ds 1 ; tells how long it should be at a temp

; Each FSM has its own state counter
FSM_state:   			ds 1	; what state the main FSM is at
FSM_state_2: 			ds 1   ; what state the microwave FSM is at

bseg
; For each pushbutton we have a flag.  The corresponding FSM will set this
; flags to one when a valid press of the pushbutton is detected.
mf: 					dbit 1 ; math function that tells which of two numbers are bigger or smaller
ssr_f: 					dbit 1 ; SSR flag
state_flag: 			dbit 1 ; flag that gets set when state is changed
QuarterSecondsFlag: 	dbit 1 ; tells us when a quarter second has passed for the ADC
State0Flag: 			dbit 1 ; tells us when in state 0
SpeakerFlag: 			dbit 1 ; set to have the speaker go off using timer 0
SongFlag: 				dbit 1 ; set to have a song go off
screen_flag: 			dbit 1  ; 0=PARAMS screen, 1=STATUS screen
print_flag: 			dbit 1 ; tells us when to print on the LCD
QuarterSecondsFlag2: 	dbit 1 ; tells us when a quarter second has passed for the LCD printing to save processing power


; Include files for all the included files that we used
$include(math32.asm) ; A library of math functions for us to use
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$include(lcd_lib.asm) ; a library with more various LCD functions 
$include(macros_lib.asm) ; a library that includes all the macros we use
$include(keypad_lib.asm) ; A library to use to read the keyboard
$include(temperature_lib.asm) ; a library to use to read the temperature and write it to the serial port
$include(song.asm) ; a library that includes the two songs that are played when the oven ends
$include(microwave_fsm.asm) ; a library that includes the mircowave mode
$include(keyboard.asm) ; a library that includes the music keybaord mode


cseg
; These 'equ' must match the wiring between the DE10Lite board and the LCD!
ELCD_RS 		equ P1.7
ELCD_E  		equ P1.1
ELCD_D4 		equ P0.7
ELCD_D5 		equ P0.5
ELCD_D6 		equ P0.3
ELCD_D7 		equ P0.1
SSR_PIN 		equ P0.0
START_BUTTON 	equ P0.2 ; Button that starts or stops the program
SOUND_OUT 		equ P0.4 ; Speaker port
CHANGE_BUTTON 	equ P0.6  ; Toggles the different modes (normal mode, mircowave mode, music keyboard mode)
TOGGLE_BUTTON  	equ P1.5  ; Toggles the display to see all the parametres

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

	; if song is playing, skip to this and use timer0 to play the songs with different frequencies
	jb SongFlag, play_song_timers
	
	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0
	
	sjmp skip_song_timers
	
	; plays songs
	play_song_timers:
	
	clr TR0
	mov TH0, tone_rh
	mov TL0, tone_rl
	setb TR0
	
	skip_song_timers:
	
	
	; uses timer0 to play the speaker
	jnb SpeakerFlag, skip_speaker
	cpl SOUND_OUT
	ljmp FSM_timer_done
	skip_speaker:
	
	; Increment the timers for each FSM. That is all we do here!
	inc FSM_timer 
	
	mov a, FSM_timer
	cjne a, #250, FSM_timer_done
	
	; uses these "QuarterSecondsFlag" to update the ADC reading every quarter second
	setb QuarterSecondsFlag
	setb QuarterSecondsFlag2
	
	; counts every quarter second and adds it to a counter
	inc QuarterSecondsCounter
	mov FSM_timer, #0x00
	
	mov a, QuarterSecondsCounter
	cjne a, #4, FSM_timer_done
	
	setb print_flag
	
	mov QuarterSecondsCounter, #0x00
	
	jb State0Flag, FSM_timer_done
	
	; every 4 quarter seconds increment the the SecondsCounter
	inc SecondsCounter ; USE THIS FOR THE CURRENT STATE TIMER. RESETS EVERY STATE
	inc SecondsCounterTotal ; USE THIS FOR THE TOTAL TIMER. IT NEVER RESETS SO DONT WORRY
	
	; increments the "MinutesCounterTotal" every 60 seconds
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
	
Clear_Display:
    mov HEX0, #0FFh
    mov HEX1, #0FFh
    mov HEX2, #0FFh
    mov HEX3, #0FFh
    mov HEX4, #0FFh
    mov HEX5, #0FFh
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
		load_y(100) ; Our min temp 130C
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_soaktemp_check
		load_x(100) ;130C
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
		load_y(180) ; Our min temp for reflux 230c
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_reflowtemp_check
		load_x(180) ; 230c
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


;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;

Initial_ALL:

   	clr EA ;disables global interupts
   	
    ; Initialization of hardware
    lcall Timer0_Init    ; Changed from Timer2_Init to Timer0_Init
    lcall InitSerialPort ; Initialize serial port on Timer 2
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
	setb QuarterSecondsFlag
	setb QuarterSecondsFlag2
	setb State0Flag
	clr SpeakerFlag
	clr SongFlag
	setb screen_flag
	clr print_flag
	
	mov MinutesCounterTotal, #0x00
	mov SecondsCounterTotal, #0x00
    mov QuarterSecondsCounter, #0x00
    
    mov soak_temp+0, 	#0
    mov soak_temp+1, 	#0

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
	
	mov active_param, #0
	
	mov microwave_temp+0,  #0
	mov microwave_temp+1,  #0
	
	
	mov microwave_time+0,  #0x00
	mov microwave_time+1,  #0x00
	mov temp_counter, #0x00
	mov FSM_state_2, #0x00
		
	clr EA
    lcall Load_Param_Into_BCD
    lcall Configure_Keypad_Pins
	setb EA ;enables global interupts
	
	ret
	
	
main:
	; sets pin assignment for in/out functionality 
	mov P0MOD, #10111011b
    mov P1MOD, #10000010b
    
    ; calls the Initial_ALL function above to Initial all
	lcall Initial_ALL
	
	; makes sure the change mode button is outside the initial_all and sets it to zero to start
	mov changeStateButton, #0x00
	
	; configures the ADC ports
	mov ADC_C, #0x80
	lcall Wait25ms
	
	WriteCommand(#0x40)
	; music note char(#0)
	WriteData(#00000B)
	WriteData(#00100B)
	WriteData(#00110B)
	WriteData(#00100B)
	WriteData(#00100B)
	WriteData(#01100B)
	WriteData(#01100B)
	WriteData(#00000B)

	; music note char(#1)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#01111B)
	WriteData(#01001B)
	WriteData(#01001B)
	WriteData(#11011B)
	WriteData(#11011B)
	WriteData(#00000B)
	
	Set_Cursor(1, 1)
    Send_Constant_String(#Clear_Message)
	Set_Cursor(2, 1)
    Send_Constant_String(#Clear_Message)
	
	
	
loop:


	;------------------------------------------------------------
	; ADC READING
	;------------------------------------------------------------
	
	; skips if it isnt on a quarter second flag
	jnb QuarterSecondsFlag, skip_ADC_reading
	sjmp continue_ADC_reading
	skip_ADC_reading:
	
	ljmp skip_ADC_reading1
	continue_ADC_reading:
	
		clr QuarterSecondsFlag
		clr EA
		
		; We are already in the QuarterSecondsFlag-triggered block,
	    ; so just render once right here:
		
		; reads adc from the low and high temps and converts it to temperature -----------------
		
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
	
		
		; allows 
		push bcd+0
		push bcd+1
		push bcd+2
		push bcd+3
		push bcd+4
	    lcall hex2bcd
	    
	    ; ------------------------------------------------------------------------------------
	    
	    ; displays voltage on 7 seg only on states other than zero
	    jb State0Flag, skip_7seg_volt_display
	    lcall Display_Voltage_7seg
	    skip_7seg_volt_display:
	    
	    ; Displays voltage only when the change button is toggled to one of the two states
		jnb screen_flag, skip_lcd_temp   ; if params screen, don't touch LCD here
		Set_Cursor(2,1)
		lcall Display_Voltage_LCD
		skip_lcd_temp:
		
		; sends the voltage to the serial port
	    lcall Display_Voltage_Serial
	    
	    pop bcd+4
		pop bcd+3
		pop bcd+2
		pop bcd+1
		pop bcd+0
	    
		setb EA
	
	skip_ADC_reading1:
	
;------------------------------------------------------------
; BUTTON TOGGLE 
;------------------------------------------------------------
	
	; doesnt allow changes when not in state zero
	jnb State0Flag, skip_change_button
	
	; switches the modes to the 2 additional modes the oven has
	jb  CHANGE_BUTTON, change_button_done
    lcall Wait25ms
    lcall Wait25ms
    jb  CHANGE_BUTTON, change_button_done
    jnb  CHANGE_BUTTON, $
    
    	; Mode indicator var
    	inc changeStateButton
    	lcall Clear_Display
    	mov LEDRA, #0x00
    	
    	lcall Initial_ALL
    	
    	; changeStateButton goes up to 2 and repeats down to 0 in a loop
    	mov a, changeStateButton
    	cjne a, #0x03, change_button_done
    	mov changeStateButton, #0x00
    	
    	lcall Wait25ms
    	lcall Wait25ms
    
    change_button_done:
    
    skip_change_button:
    
    
    ; if changeStateButton is 1 go to the music keyboard mode. if not skip
    mov a, changeStateButton
    cjne a, #0x01, keyboard_skip
    sjmp keyboard_skip3
    
    keyboard_skip:
    ljmp keyboard_skip2
    
    keyboard_skip3:
    
    	; start the music keyboard mode in the include file for it
		lcall Keyboard_Begin
		
		clr EA	
	    
	    Set_Cursor(1, 1)
	    
	    
	    ; display a few custom music notes on the LCD display
	    Set_Cursor(1, 6)
	    Display_char(#0)
	    Set_Cursor(2, 8)
	    Display_char(#0)
	    
	    Set_Cursor(1, 9)
	    Display_char(#1)
	    Set_Cursor(2, 3)
	    Display_char(#1)
	    setb EA
	    
	    ; loop to the top so it doesn't go the FSM below
		ljmp loop
	
	keyboard_skip2:
	
	 
	; if changeStateButton is 2 go to the mircowave mode. otherwise skip  
    mov a, changeStateButton
    cjne a, #0x02, Microwave_skip
    sjmp Microwave_skip2
    Microwave_skip:
    ljmp Microwave_skip1
    Microwave_skip2:
    
    	; start the mircowave mode in the include file for it
		lcall Run_Microwave_Mode
		
		; when the start button is pressed in mircowave mode, 
		; start the countdown timer and display it on the LCD
		jb START_BUTTON, skip_button2
		lcall Wait25ms
		jb START_BUTTON, skip_button2
		jnb START_BUTTON, $
		
			setb SpeakerFlag
			lcall Wait25ms
			lcall Wait25ms
			clr SpeakerFlag
			
			mov microwave_time+0,  #0x00
			mov microwave_time+1,  #0x00
			clr EA
			Set_Cursor(1,3)
			Display_char(#'0')
			Display_char(#' ')
			Display_char(#' ')
			Display_char(#' ')
			setb EA
			
			mov temp_counter, #0x00
		
			mov FSM_state_2, #0x00
		skip_button2:
		
		
		; prints all the information for the mircowave mode on the LCD
		jnb print_flag, skip_printing2
		
			mov x+0, microwave_temp+0
			mov x+1, microwave_temp+1
			mov x+2, #0
			mov x+3, #0
			
			clr EA
			lcall hex2bcd
			Set_Cursor(1,1)
			lcall Display_Voltage_LCD
			
			mov x+0, microwave_time+0
			mov x+1, microwave_time+1
			mov x+2, #0
			mov x+3, #0
	
			lcall hex2bcd
			Set_Cursor(2,10)
			Display_char(#'t')
			Display_char(#'=')
			Write_3digits(bcd)
			setb EA
		
		skip_printing2:
		
		ljmp loop
	
	Microwave_skip1:
	
	; switches the LCD display to switch between the parametres and the current time and voltage
    jb  TOGGLE_BUTTON, ScreenToggle_Done
    lcall Wait25ms
    jb  TOGGLE_BUTTON, ScreenToggle_Done
    jnb  TOGGLE_BUTTON, $
	    
	    ; clears screen
	    Set_Cursor(1, 1)
	    Send_Constant_String(#Clear_Message)
		Set_Cursor(2, 1)
	    Send_Constant_String(#Clear_Message)
	
		; sets the required flags
	    cpl  screen_flag
	    setb print_flag
	    
	    ; makes beep sound with the speaker
	    setb SpeakerFlag
		lcall Wait25ms
		lcall Wait25ms
		clr SpeakerFlag
	
	ScreenToggle_Done:
	
	; prints the LCD display information for the main FSM. 
	; only prints every second as print_flag only gets set by the 
	; timer interupts or the TOGGLE_BUTTON press
	jnb print_flag, skip_printing
	
		clr print_flag
		jnb screen_flag, skip_show_temp
		clr EA
			lcall LCD_ShowTotalTime
			lcall LCD_ShowStateTime
			lcall Update_LCD_State
		setb EA
		skip_show_temp:
		
		jb screen_flag, skip_show_para
		clr EA
			lcall LCD_ShowParamsLine1
			lcall LCD_ShowParamsLine2
		setb EA
		skip_show_para:
	
	skip_printing:
	
	; Reset button check. uses the START_BUTTON as a way to reset the main FSM
	jb State0Flag, skip_button
	jb START_BUTTON, skip_button
	lcall Wait25ms
	jb START_BUTTON, skip_button
	jnb START_BUTTON, $
	
		; makes beep sound with the speaker
		setb SpeakerFlag
		lcall Wait25ms
		lcall Wait25ms
		clr SpeakerFlag
		
		; resets state to zero 
		mov FSM_state, #0x00
	skip_button:
	
	
    
;-------------------------------------------------------------------------------
;FSM
;-------------------------------------------------------------------------------

	; everytime theres a new state, state_flag is set and do all these things
	jnb state_flag, no_new_state
	
		clr state_flag
		clr EA
		; resets state timer
		mov SecondsCounter, #0x00
		lcall Update_LCD_State
		setb EA
		
		; makes beep sound with the speaker
		setb SpeakerFlag
		lcall Wait25ms
		lcall Wait25ms
		clr SpeakerFlag
		
	no_new_state:

	; resets LEDR
	mov LEDRA, #0

	; Begining state before the oven starts
	FSM_state0:
		; checks if in state and skips if not in that state
		mov a, FSM_state
		cjne a, #0, FSM_state1_continue_move
		sjmp FSM_state1_skip_move
		FSM_state1_continue_move:
		ljmp FSM_state1
		FSM_state1_skip_move:
		
		; resets total time counters to zero 
		mov MinutesCounterTotal, #0x00
		mov SecondsCounterTotal, #0x00
		
		
		setb LEDRA.0
		clr SSR_PIN ; turns off oven during state
		setb State0Flag ; tells us we are in state0
		
		; starts keyboard reading functions
		clr EA ; turns off global timers to stop glicthes during functions
		lcall Keypad
	    lcall Display
	    jnc  skip_keypad ; only shifts when keyboard is pressed
	    lcall Shift_Digits_Left
		skip_keypad:
		setb EA
		
		; skips state if switch 0 is active
		jb SWA.0, FSM_done_state_0_skip
		
		; goes to next state when START_BUTTON is pressed
		jb START_BUTTON, FSM_done_state_0_Continue
		lcall Wait25ms
		jb START_BUTTON, FSM_done_state_0_Continue
		jnb START_BUTTON, $
			sjmp FSM_done_state_0_Skip
			
		FSM_done_state_0_Continue:
			ljmp FSM_done
			
		FSM_done_state_0_Skip:
		
			; clears hex display
		    lcall Clear_Display
			
			; fixes the inital vals
			clr EA
			lcall Over_Under_Check_Rewrite ; changes the variables to stay in the bounds given in the lab
			lcall WriteInitialVals
			setb EA
		
			; resets keyboard active param
			mov active_param, #0
		
			setb state_flag ; tells us that there is a new state
			clr State0Flag
			inc FSM_state ; changes to next state
		ljmp FSM_done
	
	FSM_state1:	
		; checks if in state and skips if not in that state
		mov a, FSM_state
		cjne a, #1, FSM_state2_continue_move
		sjmp FSM_state2_skip_move
		FSM_state2_continue_move:
		ljmp FSM_state2
		FSM_state2_skip_move:
		
		setb LEDRA.1
	
		; sets oven on
		setb SSR_PIN
	
		clr EA
		
		; checks if the state timer has exceeded 60 seconds
		Load_X_Var8(SecondsCounter)
		load_y(60)
		lcall x_gt_y
		jnb mf, emergency_check
		clr mf
		
		; if temperature is not above 50 C by 60 seconds
		; go back to state 0 after speaker goes off a bunch of times
		Load_X_Var32(tempFinal)
		load_y(500)
		lcall x_lt_y
		jnb mf, emergency_check
			mov FSM_State, #0x00
			lcall Wait25ms
			lcall Wait25ms
			setb SpeakerFlag
			lcall Wait25ms
			lcall Wait25ms
			clr SpeakerFlag
			lcall Wait25ms
			lcall Wait25ms
			setb SpeakerFlag
			lcall Wait25ms
			lcall Wait25ms
			clr SpeakerFlag
			lcall Wait25ms
			lcall Wait25ms
			setb SpeakerFlag
			lcall Wait25ms
			lcall Wait25ms
			clr SpeakerFlag
		emergency_check:
		
	
		; heats up until the temp read (tempFinal) is equal to the soak_temp
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
		
		
		; skips state if switch 1 is active
		jb SWA.1, FSM_done_state_1_skip
		
		jnb mf, FSM_done_state_1_Continue 
		sjmp FSM_done_state_1_Skip
		FSM_done_state_1_Continue:
		ljmp FSM_done
		FSM_done_state_1_Skip:
		
			setb state_flag ; tells us that there is a new state
			inc FSM_state  ; changes to next state
		ljmp FSM_done
	
	FSM_state2:	
		; checks if in state and skips if not in that state
		mov a, FSM_state
		cjne a, #2, FSM_state3_continue_move
		sjmp FSM_state3_skip_move
		FSM_state3_continue_move:
		ljmp FSM_state3
		FSM_state3_skip_move:
		
		setb LEDRA.2
		
		
		; keeps SSR oven on for 20% of the time to mimic the 20% power 
		clr EA
		
		mov bcd+0, soak_time+0
	    mov bcd+1, soak_time+1
	    mov bcd+2, #0
	    mov bcd+3, #0
	    mov bcd+4, #0
	    lcall bcd2hex
	        
	    mov soak_time_hex+0, x+0
	    mov soak_time_hex+1, x+1
	    
		powerPercent(#12, soak_time, timeOn) ; calculates how long it needs to be on for 20% power
		
		; turns on SSR until its done at least 20% then turns off
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
		
		; checks if the state timer has exceeded soak_time
		; then goes to next state if true
		clr EA
		Load_X_Var8(SecondsCounter) 
		Load_Y_Var16(soak_time_hex)
		clr mf  
		lcall x_gt_y
		setb EA
		
		; skips state if switch 2 is active
		jb SWA.2, FSM_done_state_2_skip
		
		jnb mf, FSM_done_state_2_Continue
		sjmp FSM_done_state_2_Skip
		FSM_done_state_2_Continue:
		ljmp FSM_done
		FSM_done_state_2_Skip:
			
			setb state_flag ; tells us that there is a new state
			inc FSM_state  ; changes to next state
		ljmp FSM_done
	
	FSM_state3:
		; checks if in state and skips if not in that state	
		mov a, FSM_state
		cjne a, #3, FSM_state4
		setb LEDRA.3
	
		; turns on oven 100%
		setb SSR_PIN
	
		; Checks if the temp read (tempFinal) is bigger than reflow_temp 
		; and if so move to next state
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
		
		; skips state if switch 3 is active
		jb SWA.3, FSM_done_state_3_skip
		
		jb mf, FSM_done_state_3_Continue 
		sjmp FSM_done_state_3_Skip
		FSM_done_state_3_Continue:
		ljmp FSM_done
		FSM_done_state_3_Skip:
		
			setb state_flag ; tells us that there is a new state
			inc FSM_state  ; changes to next state
		ljmp FSM_done
	
	FSM_state4:	
		; checks if in state and skips if not in that state
		mov a, FSM_state
		cjne a, #4, FSM_state5_continue_move
		sjmp FSM_state5_skip_move
		FSM_state5_continue_move:
		ljmp FSM_state5
		FSM_state5_skip_move:
		
		setb LEDRA.4
	
		; keeps SSR oven on for 20% of the time to mimic the 20% power 	
		clr EA
		mov bcd+0, reflow_time+0
	    mov bcd+1, reflow_time+1
	    mov bcd+2, #0
	    mov bcd+3, #0
		mov bcd+4, #0
	    lcall bcd2hex
	        
	    mov reflow_time_hex+0, x+0
	    mov reflow_time_hex+1, x+1
	    
		powerPercent(#20, reflow_time_hex, timeOn)  ; calculates how long it needs to be on for 20% power
		Load_X_Var8(SecondsCounter)
		Load_Y_Var16(timeOn) 
		clr mf  
		lcall x_gt_y 
		
		; turns on SSR until its done at least 20% then turns off
		setb EA
		jnb mf, ssr_off1
		clr SSR_PIN
		sjmp ssr_on1
	
		ssr_off1:
			setb SSR_PIN
		ssr_on1:
	
		; checks if the state timer has exceeded reflow_time
		; then goes to next state if true
		clr EA
		Load_X_Var16(reflow_time_hex)
		Load_Y_Var8(SecondsCounter)
		clr mf
		lcall x_gt_y
		setb EA
		
		; skips state if switch 4 is active
		jb SWA.4, FSM_done_state_4_Skip
		
		jb mf, FSM_done
		FSM_done_state_4_Skip:
		
			setb state_flag ; tells us that there is a new state
			inc FSM_state  ; changes to next state
		ljmp FSM_done
	
	FSM_state5:	
		; checks if in state and skips if not in that state
		mov a, FSM_state
		cjne a, #5, FSM_done
		setb LEDRA.5
	
		; turns off oven to 0%
		clr SSR_PIN
		
		; Only moves states when the temperature goes under 60 C
		clr EA
		Load_X_Var32(tempFinal)
		load_y(600) ; Not already multiplied by 10
		clr mf
		lcall x_lt_y
		setb EA
		
		; skips state if switch 5 is active
		jb SWA.5, FSM_done_state_5_Skip
		
		jnb mf, FSM_done
		FSM_done_state_5_Skip:
		
			; resets FSM
			setb state_flag
			mov FSM_state, #0x00
			
			;Just added this to fix discrod integration
			mov dptr, #DONE
	    	lcall SendString
	
			mov a, #'\r'
	  		lcall putchar
	    	mov a, #'\n'
	   		lcall putchar
			
			; Plays song 1 based on the TOGGLE_BUTTON configuration when the FSM is finished
			jnb screen_flag, skip_song_1
				lcall Play_song1
			skip_song_1:
			
			; Plays song 2 based on the TOGGLE_BUTTON configuration when the FSM is finished
			jb screen_flag, skip_song_2
				lcall Play_song2
			skip_song_2:
	
			
	
	
		FSM_done:
	ljmp loop
		
	
END
	
	
	
