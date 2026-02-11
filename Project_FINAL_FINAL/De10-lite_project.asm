; main project file
$NOLIST
$MODMAX10
$LIST


CLK           	EQU 33333333 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   	EQU 1024     ; 1000Hz, for a timer tick of 1ms
TIMER0_RELOAD 	EQU ((65536-(CLK/(12*TIMER0_RATE))))
FREQ   			EQU 33333333
BAUD   			EQU 115200
T2LOAD 			EQU 65536-(FREQ/(32*BAUD))

TONE_1024 EQU ((65536-(CLK/1024)))
TONE_4096 EQU ((65536-(CLK/4096)))

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

Profile:  db 'PROFILE,', 0
Comma:    db ',', 0
Clear_Message:  db '                ', 0
DONE:    db 'DONE', 0

S0_TXT: db 'INIT   ', 0
S1_TXT: db 'RAMP1  ', 0
S2_TXT: db 'SOAK   ', 0
S3_TXT: db 'RAMP2  ', 0
S4_TXT: db 'REFLOW ', 0
S5_TXT: db 'COOLS  ', 0


COOK_MICROWAVE: db 'COOKING', 0
DONE_MICROWAVE: db 'DONE   ', 0
CLEAR_MICROWAVE: db '       ', 0


dseg at 0x30
; For math 
x:			ds 4
y:			ds 4
bcd:		ds 5



math_space: ds 5

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

; microwave FSM
changeStateButton: ds 1
microwave_temp: ds 2
microwave_time: ds 2
temp_counter: ds 1

; Each FSM has its own state counter
FSM_state:  ds 1
FSM_state_2: ds 1

bseg
; For each pushbutton we have a flag.  The corresponding FSM will set this
; flags to one when a valid press of the pushbutton is detected.
mf       	: dbit 1
ssr_f    	: dbit 1
state_flag	: dbit 1
QuarterSecondsFlag : dbit 1
State0Flag : dbit 1
SpeakerFlag : dbit 1
SongFlag : dbit 1
screen_flag     : dbit 1  ; 0=PARAMS screen, 1=STATUS screen
print_flag     : dbit 1
QuarterSecondsFlag2 : dbit 1


$include(math32.asm)
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$include(keypad_lib_3.asm)
$include(temperature_lib.asm)
$include(lcd_lib.asm)
$include(song.asm)
$include(microwave_fsm.asm)
$include(macros_lib.asm)
$include(keyboard.asm)


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
CHANGE_BUTTON equ P0.6
TOGGLE_BUTTON  equ P1.5   ; active-low pushbutton on P1.5 (pressed = 0)

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

	jb SongFlag, play_song_timers
	
	clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0
	
	sjmp skip_song_timers
	
	play_song_timers:
	
	clr TR0
	mov TH0, tone_rh
	mov TL0, tone_rl
	setb TR0
	
	skip_song_timers:
	
	
	
	jnb SpeakerFlag, skip_speaker
	cpl SOUND_OUT
	ljmp FSM_timer_done
	skip_speaker:
	
	; Increment the timers for each FSM. That is all we do here!
	
	inc FSM_timer 
	
	mov a, FSM_timer
	cjne a, #250, FSM_timer_done
	
	setb QuarterSecondsFlag
	setb QuarterSecondsFlag2
	
	inc QuarterSecondsCounter
	mov FSM_timer, #0x00
	
	mov a, QuarterSecondsCounter
	cjne a, #4, FSM_timer_done
	
	setb print_flag
	
	mov QuarterSecondsCounter, #0x00
	
	jb State0Flag, FSM_timer_done
	
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
    setb EA

	setb EA ;enables global interupts
	
	ret
	
	
main:
	mov P0MOD, #10111011b
    mov P1MOD, #10000010b
    
	lcall Initial_ALL
	
	mov changeStateButton, #0x00
	
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
	
	jnb QuarterSecondsFlag, skip_ADC_reading
	sjmp continue_ADC_reading
	skip_ADC_reading:
	
	ljmp skip_ADC_reading1
	continue_ADC_reading:
	
		clr QuarterSecondsFlag
		clr EA
		
		; We are already in the QuarterSecondsFlag-triggered block,
	    ; so just render once right here:
		
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
	
	
		push bcd+0
		push bcd+1
		push bcd+2
		push bcd+3
		push bcd+4
	    lcall hex2bcd
	    
	    jb State0Flag, skip_7seg_volt_display
	    lcall Display_Voltage_7seg
	    skip_7seg_volt_display:
	    
		jnb screen_flag, skip_lcd_temp   ; if params screen, don't touch LCD here
		Set_Cursor(2,1)
		lcall Display_Voltage_LCD
		skip_lcd_temp:
		
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
	
	
	jnb State0Flag, skip_change_button
	
	jb  CHANGE_BUTTON, change_button_done
    lcall Wait25ms
    lcall Wait25ms
    jb  CHANGE_BUTTON, change_button_done
    jnb  CHANGE_BUTTON, $
    
    	inc changeStateButton
    	lcall Clear_Display
    	mov LEDRA, #0x00
    	
    	lcall Initial_ALL
    	
    	mov a, changeStateButton
    	cjne a, #0x03, change_button_done
    	mov changeStateButton, #0x00
    	
    	lcall Wait25ms
    	lcall Wait25ms
    
    change_button_done:
    
    skip_change_button:
    
    mov a, changeStateButton
    cjne a, #0x01, keyboard_skip
    sjmp keyboard_skip3
    
    keyboard_skip:
    ljmp keyboard_skip2
    
    keyboard_skip3:
    
		lcall Keyboard_Begin
		
		clr EA	
		Set_Cursor(1, 1)
	    Send_Constant_String(#Clear_Message)
		Set_Cursor(2, 1)
	    Send_Constant_String(#Clear_Message)
	    
	    Set_Cursor(1, 6)
	    Display_char(#0)
	    Set_Cursor(2, 8)
	    Display_char(#0)
	    
	    Set_Cursor(1, 9)
	    Display_char(#1)
	    Set_Cursor(2, 3)
	    Display_char(#1)
	    setb EA
	    
		ljmp loop
	
	keyboard_skip2:
	
	    
    mov a, changeStateButton
    cjne a, #0x02, Microwave_skip
    sjmp Microwave_skip2
    Microwave_skip:
    ljmp Microwave_skip1
    Microwave_skip2:
    
		lcall Run_Microwave_Mode
		
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
	
    jb  TOGGLE_BUTTON, ScreenToggle_Done
    lcall Wait25ms
    jb  TOGGLE_BUTTON, ScreenToggle_Done
    jnb  TOGGLE_BUTTON, $
	    
	    Set_Cursor(1, 1)
	    Send_Constant_String(#Clear_Message)
		Set_Cursor(2, 1)
	    Send_Constant_String(#Clear_Message)
	
	    cpl  screen_flag
	    setb print_flag
	    
	    setb SpeakerFlag
		lcall Wait25ms
		lcall Wait25ms
		clr SpeakerFlag
	
	ScreenToggle_Done:
	
	
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
	
	; Reset button check

	jb State0Flag, skip_button
	jb START_BUTTON, skip_button
	lcall Wait25ms
	jb START_BUTTON, skip_button
	jnb START_BUTTON, $
	
		setb SpeakerFlag
		lcall Wait25ms
		lcall Wait25ms
		clr SpeakerFlag
	
		mov FSM_state, #0x00
	skip_button:
	
	
    
;-------------------------------------------------------------------------------
;FSM
;-------------------------------------------------------------------------------

	jnb state_flag, no_new_state
	
		clr state_flag
		clr EA
		mov SecondsCounter, #0x00
		lcall Update_LCD_State
		setb EA
		
		setb SpeakerFlag
		lcall Wait25ms
		lcall Wait25ms
		clr SpeakerFlag
		
	no_new_state:

	mov LEDRA, #0

FSM_state0:
	mov a, FSM_state
	cjne a, #0, FSM_state1_continue_move
	sjmp FSM_state1_skip_move
	FSM_state1_continue_move:
	ljmp FSM_state1
	FSM_state1_skip_move:
	
	mov MinutesCounterTotal, #0x00
	mov SecondsCounterTotal, #0x00
	
	
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
	
	    lcall Clear_Display
		
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
		
		Set_Cursor(2, 1)
		
		jnb screen_flag, skip_song_1
			lcall Play_song1
		skip_song_1:
		
		jb screen_flag, skip_song_2
			lcall Play_song2
		skip_song_2:
		
		mov a, #'0'
		lcall putchar

	FSM_done:
	;Just added this to fix discrod integration
	mov dptr, #DONE
    lcall SendString

	ljmp loop
	

END

