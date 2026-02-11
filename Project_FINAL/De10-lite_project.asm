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
T1LOAD 			EQU 256-(FREQ/(32*12*BAUD))
T2LOAD          EQU 65536-(FREQ/(32*BAUD)) 

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

Timer0Reload:   ds 2

; Each FSM has its own timer
FSM_timer:  ds 1
QuarterSecondsCounter: ds 1
SecondsCounter: ds 1
SecondsCounterTotal: ds 1
MinutesCounterTotal: ds 1
; Each FSM has its own state counter
FSM_state:  ds 1
Profile:    db 0 

bseg
; For each pushbutton we have a flag.  The corresponding FSM will set this
; flags to one when a valid press of the pushbutton is detected.
mf       	: dbit 1
ssr_f    	: dbit 1
state_flag	: dbit 1
QuarterSecondsFlag : dbit 1
State0Flag : dbit 1
ScreenSelect      : dbit 1   ; 0 = parameter screen, 1 = run screen


$include(math32.asm)
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$include(keypad_lib_3.asm)
$include(temperature_lib.asm)
$include(lcd_lib.asm)

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
lcd_button equ P1.5

Initial_Message:  db 'Tmperature Test', 0

cseg
;-------MACROS--------------------;
;Example macro to help with process %0,1,etc represents the input number, this is all pass by reference(i.e it can actually affect the variable)
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

;We should probably start using this from now on oh well live laugh love
Mov_A_to_B16Bit MAC
;%0 is A, %1 is B
	mov %1+0, %0+0
	mov %1+1, %0+1
	mov %1+2, #0
	mov %1+3, #0
ENDMAC

Mov_A_to_B32Bit MAC
	mov %1+0, %0+0
	mov %1+1, %0+1
	mov %1+2, %0+2
	mov %1+3, %0+3
ENDMAC


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

;------------------------------------------------------
; TempAndLCD_Update
;   - Reads sensors
;   - Updates tempFinal
;   - Updates 7-seg (if not in state 0)
;   - Updates LCD according to FSM_state + ScreenSelect
;   Assumes:
;      - Called with interrupts enabled
;------------------------------------------------------
TempAndLCD_Update:
    ; ALL TEMP MATH -------------------------
    clr EA
; ---------------------------------------------------------
    ; 1) Read thermocouple channel and convert to mV
    ; ---------------------------------------------------------
    mov ADC_C, #LM335_ADC

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
    mov ADC_C, #OP07_ADC

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

    Load_y(10000)         ; keep one decimal place
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
    
    mov tempFinal+0, x+0
    mov tempFinal+1, x+1
    mov tempFinal+2, x+2
    mov tempFinal+3, x+3

    ; ---------------------------------------------------------
    ; 4) Display
    ; ---------------------------------------------------------
    lcall hex2bcd          ; tempFinal in x -> BCD in bcd[]

    ; 7-seg: show oven temperature in states 1–5
    jb State0Flag, TLU_skip_7seg
    lcall Display_Voltage_7seg
TLU_skip_7seg:

    ;------------------------------------------------------
    ; LCD screens for states 1–5 controlled by ScreenSelect
    ;------------------------------------------------------
    mov a, FSM_state
    jz  TLU_lcd_done           ; state 0: leave LCD alone
    cjne a, #6, TLU_lcd_state_ok
    sjmp TLU_lcd_done          ; FSM_state >= 6: ignore

TLU_lcd_state_ok:
    jnb ScreenSelect, TLU_lcd_param_screen   ; ScreenSelect = 0 -> parameter screen

    ; -------- Run screen (ScreenSelect = 1) --------
    lcall Display_Voltage_LCD         ; Row 1: oven temperature
    lcall LCD_ShowStateRunInfo        ; Row 2: S MM:SS
    sjmp TLU_lcd_done

TLU_lcd_param_screen:
    ; -------- Parameter screen (ScreenSelect = 0) --------
    lcall LCD_ShowParameter           ; Row 1: param
    lcall LCD_ShowTotalTime           ; Row 2: Tot MM:SS

TLU_lcd_done:
    setb EA
    ret


Over_Under_Check_Rewrite:
	;-------SoakStageStuff-----------------
	underflow_soaktemp:
		Mov_A_to_B16Bit(soak_temp, bcd)
		lcall bcd2hex
		load_y(130) ; Our min temp
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_soaktemp_check
		load_x(130)
	    lcall hex2bcd
		Mov_A_to_B16Bit(bcd, soak_temp)
	underflow_soaktemp_check:

	overflow_soaktemp:
		;Max temp check for 
		Mov_A_to_B16Bit(soak_temp,bcd)
		lcall bcd2hex
		load_y(170) ; Our max temp
		lcall x_gt_y ;mf 1 if true
		jnb mf, overflow_soaktemp_check
		load_x(170)
	    lcall hex2bcd
		Mov_A_to_B16Bit(bcd, soak_temp)
	overflow_soaktemp_check:

	underflow_soaktime:
		;Max temp check for 
		Mov_A_to_B16Bit(soak_time,bcd)
		lcall bcd2hex
		load_y(60) ; Our min time
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_soaktime_check
		load_x(60)
		lcall hex2bcd
		Mov_A_to_B16Bit(bcd, soak_time)
	underflow_soaktime_check:

	overflow_soaktime:
		;Max temp check for 
		Mov_A_to_B16Bit(soak_time,bcd)
		lcall bcd2hex
		load_y(120) ; Our max time
		lcall x_gt_y ;mf 1 if true
		jnb mf, overflow_soaktime_check
		load_x(120)
		lcall hex2bcd
		Mov_A_to_B16Bit(bcd, soak_time)
	overflow_soaktime_check:

	;----Reflux Checks-----------------------
	underflow_reflowtemp:
		;Min temp check for 
		Mov_A_to_B16Bit(reflow_temp, bcd)
		lcall bcd2hex
		load_y(230) ; Our min temp for reflux
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_reflowtemp_check
		load_x(230)
	    lcall hex2bcd
		Mov_A_to_B16Bit(bcd, reflow_temp)
	underflow_reflowtemp_check:

	overflow_reflowtemp:
		;Max temp check for 
		Mov_A_to_B16Bit(reflow_temp,bcd)
		lcall bcd2hex
		load_y(240) ; Our max temp
		lcall x_gt_y ;mf 1 if true
		jnb mf, overflow_reflowtemp_check
		load_x(240)
	    lcall hex2bcd
		Mov_A_to_B16Bit(bcd, reflow_temp)
	overflow_reflowtemp_check:

	underflow_reflowtime:
		;Max temp check for 
		Mov_A_to_B16Bit(reflow_time,bcd)
		lcall bcd2hex
		load_y(30) ; Our max temp
		lcall x_lt_y ;mf 1 if true
		jnb mf, underflow_reflowtime_check
		load_x(30)
		lcall hex2bcd
		Mov_A_to_B16Bit(bcd, reflow_time)
	underflow_reflowtime_check:

	overflow_reflowtime:
		;Max temp check for 
		Mov_A_to_B16Bit(reflow_time,bcd)
		lcall bcd2hex
		load_y(45) ; Our max temp
		lcall x_gt_y ;mf 1 if true
		jnb mf, overflow_reflowtime_check
		load_x(45)
		lcall hex2bcd
		Mov_A_to_B16Bit(bcd, reflow_time)
	overflow_reflowtime_check:

	ret
;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;

Initial_ALL:

   	clr EA ;disables global interupts
   	
   	;lcall InitSerialPort
   	
   	; Initialization of hardware
    lcall Timer2_Init
    lcall ELCD_4BIT ; Configure LCD in four bit mode
    ; Turn off all the LEDs
   	
   	mov SP, #7FH ; Set the beginning of the stack (more on this later)
	mov LEDRA, #0 ; Turn off all unused LEDs (Too bright!)
	mov LEDRB, #0
   	
   	
   	; Initialize variables
    mov FSM_state, #0x00
	clr SSR_PIN
	clr mf
	clr ssr_f
	setb state_flag ;tells the de10-lite its a new state
	clr QuarterSecondsFlag
	setb State0Flag
	clr ScreenSelect       ; start with parameter screen

	mov MinutesCounterTotal, #0x00
	mov SecondsCounterTotal, #0x00
    mov QuarterSecondsCounter, #0x00
    
    
    load_x(300)
    lcall hex2bcd
    mov soak_temp+0, 	bcd+0    ; mode A 150 +-20
    mov soak_temp+1, 	bcd+1

	mov soak_time+0, 	#0     ; mode B 60-120
	mov soak_time+1, 	#0
	
	mov reflow_temp+0,  #0		; mode C 230 < 240
	mov reflow_temp+1,  #0
	
	mov reflow_time+0,  #0 	; mode D  30 < 45
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
	mov P0MOD, #10101011b ; P0.1, P0.3, P0.5, P0.7 are outputs.  ('1' makes the pin output)
    mov P1MOD, #10000010b ; P1.7 and P1.1 are outputs
	lcall Initial_ALL
	
	; Configure the pins connected to the LCD as outputs
	mov P0MOD, #10101010b ; P0.1, P0.3, P0.5, P0.7 are outputs.  ('1' makes the pin output)
    mov P1MOD, #10000010b ; P1.7 and P1.1 are outputs

    lcall ELCD_4BIT ; Configure LCD in four bit mode
	
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
	
	mov dptr, #Initial_Message
	lcall SendString
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	
	mov ADC_C, #0x80 ; Reset ADC
	lcall Wait25ms

	;testing lcd_lib
	lcall LCD_ShowTotalTime
	
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

    ;------------------------------------------------------
    ; Temperature + LCD update every QuarterSecondsFlag
    ;------------------------------------------------------
    jnb QuarterSecondsFlag, skip_temp_update   ; if flag = 0 ? skip
    clr QuarterSecondsFlag

    ; call subroutine that does the heavy work
    lcall TempAndLCD_Update


skip_temp_update:

    

	jb State0Flag, skip_button
	jb START_BUTTON, skip_button
	lcall Wait25ms ;Debouncing
	jb START_BUTTON, skip_button
	jnb START_BUTTON, $
	
		mov FSM_state, #0x00
	skip_button:

    
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
	mov LEDRA, #0

    ;-------------------------------------------------------
    ; LCD screen toggle using lcd_button (P1.5) in states 1â€“5
    ;   ScreenSelect = 0 -> parameter screen
    ;   ScreenSelect = 1 -> run screen
    ;-------------------------------------------------------
    mov a, FSM_state
    jz  SkipScreenToggle          ; state 0 -> ignore
    cjne a, #6, ScreenToggleOK
    sjmp SkipScreenToggle         ; FSM_state >= 6 -> ignore

ScreenToggleOK:
    ; lcd_button assumed active-low (0 when pressed)
    jb lcd_button, SkipScreenToggle    ; if 1 -> not pressed
    lcall Wait25ms                     ; debounce
    jb lcd_button, SkipScreenToggle    ; if bounced back high, ignore

WaitRelease_Screen:
    jnb lcd_button, WaitRelease_Screen ; wait until button released (back to 1)

    cpl ScreenSelect                   ; toggle 0<->1

SkipScreenToggle:

FSM_state0:
	;Only moves on to state 1 once start button is pressed
	mov a, FSM_state
	cjne a, #0, FSM_state1_continue_move
	sjmp FSM_state1_skip_move
	
	FSM_state1_continue_move:
	ljmp FSM_state1
	
	FSM_state1_skip_move:
	
	
	
	setb State0Flag
	
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
	
	jb START_BUTTON, FSM_done_state_0_Continue; only moves on when button is high
	lcall Wait25ms ;Debouncing
	jb START_BUTTON, FSM_done_state_0_Continue
	jnb START_BUTTON, $
		sjmp FSM_done_state_0_Skip
		
	FSM_done_state_0_Continue:
		ljmp FSM_done
		
	FSM_done_state_0_Skip:
		
		clr EA
		lcall Over_Under_Check_Rewrite
		setb EA
	
		mov active_param, #0
	
		setb state_flag
		clr State0Flag
		inc FSM_state
	ljmp FSM_done

;Restarts if not in state 0 and start button is pressed
FSM_state1:	
	;Only move to next stat if temp > 150c
	mov a, FSM_state
	cjne a, #1, FSM_state2_continue_move
	sjmp FSM_state2_skip_move
	
	FSM_state2_continue_move:
	ljmp FSM_state2
	
	FSM_state2_skip_move:
	
	setb LEDRA.1

	setb SSR_PIN

	clr EA
	
	;If it didint reach 50 degrees in 60 seconds
	;If time > 60 check
	load_x(60)
	Load_Y_Var8(SecondsCounter)
	lcall x_gt_y
	jnb mf, emergency_check
	clr mf
	
	
	;Only check if time > 60 and if checks if temp is less then 50
	Load_X_Var32(tempFinal)
	load_y(50)
	lcall x_lt_y
	jnb mf, emergency_check
	;If so it failed and we do an emergency abort
	mov FSM_State, #0x00
	emergency_check:

	clr mf

	
	;if temp > 150 
	
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
	Load_Y_Var16(soak_time_hex)
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
	mov a, FSM_state
	;Only moves on when the temp is > 220c
	cjne a, #3, FSM_state4
	setb LEDRA.3

	setb SSR_PIN

	;if temp > 150
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
	Load_X_Var16(reflow_time_hex)
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
	
	mov a, FSM_state
	cjne a, #5, FSM_done
	setb LEDRA.5

	clr SSR_PIN
	
	clr EA
	Load_X_Var32(tempFinal)
	load_y(220)
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
