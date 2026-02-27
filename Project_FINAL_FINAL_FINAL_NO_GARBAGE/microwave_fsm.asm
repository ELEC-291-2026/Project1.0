; side project file (microwave_fsm.asm)
; ------------------------------------------------------------------------------
; This is code for the mircowave mode
; Allows the user to change to this mode and use the oven like a normal mircowave
; ------------------------------------------------------------------------------
; This include_file was made by the following people

;	- Owen Anderson 		 51069375
;	- Khushaan Virk 		 47290044
; ------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; MICROWAVE FSM MODULE (11-STATE STANDALONE VERSION)
;-------------------------------------------------------------------------------
; This file contains the complete logic for a 11-state Microcontroller Microwave.
; States: 0 (Menu), 1-8 (Food Configs), 9 (Cooking), 10 (Done)
;-------------------------------------------------------------------------------



; --- Entry Point ---
Run_Microwave_Mode:
    mov a, FSM_state_2
    ;mov LEDRA, #0x00
    
    ; Dispatcher: Branches to logic based on current state
    cjne a, #0, User_Not_State0
    lcall Microwave_Menu
    sjmp Microwave_FSM_End

User_Not_State0:
    cjne a, #9, User_Not_State9     ; Is it State 9 (Cooking)?
    lcall Microwave_Cook
    sjmp Microwave_FSM_End

User_Not_State9:
    cjne a, #10, User_Not_States_1_8 ; Is it State 10 (Done)?
    lcall Microwave_Done
    sjmp Microwave_FSM_End

User_Not_States_1_8:
    ; Checks states 1 through 8 (The Food Recipes)
    cjne a, #1, Not_S1
    lcall Microwave_Pizza_Config
    sjmp Microwave_FSM_End
Not_S1:
    cjne a, #2, Not_S2
    setb LEDRA.1
    lcall Microwave_Popcorn_Config
    sjmp Microwave_FSM_End
Not_S2:
    cjne a, #3, Not_S3
    lcall Microwave_Defrost_Config
    sjmp Microwave_FSM_End
Not_S3:
    cjne a, #4, Not_S4
    lcall Microwave_Chicken_Config
    sjmp Microwave_FSM_End
Not_S4:
    cjne a, #5, Not_S5
    lcall Microwave_Potato_Config
    sjmp Microwave_FSM_End
Not_S5:
    cjne a, #6, Not_S6
    lcall Microwave_Beverage_Config
    sjmp Microwave_FSM_End
Not_S6:
    cjne a, #7, Not_S7
    lcall Microwave_Soup_Config
    sjmp Microwave_FSM_End
Not_S7:
    cjne a, #8, Microwave_FSM_End
    lcall Microwave_Veggie_Config

Microwave_FSM_End:
    ret


; --- State 0: Menu Selection ---
Microwave_Menu:

	clr EA
	Set_Cursor(1,10)
	Send_Constant_String(#CLEAR_MICROWAVE)
	Set_Cursor(1,4)
	Display_char(#' ')
	setb EA
	
	
	setb LEDRA.0
	mov R7, #0x00
	lcall Keypad
    jnc Microwave_Menu_Done         ; If no key, exit

    mov a, R7                       ; R7 holds the character (ASCII)
	anl a, #0x0F
    
    ; Map keys 1-8 to FSM_states 1-8
    cjne a, #1, Menu_C2
    setb LEDRA.1
    mov FSM_state_2, #1
    sjmp Microwave_Menu_Done
Menu_C2:
    cjne a, #2, Menu_C3
    setb LEDRA.2
    mov FSM_state_2, #2
    sjmp Microwave_Menu_Done
Menu_C3:
    cjne a, #3, Menu_C4
    mov FSM_state_2, #3
    sjmp Microwave_Menu_Done
Menu_C4:
    cjne a, #4, Menu_C5
    mov FSM_state_2, #4
    sjmp Microwave_Menu_Done
Menu_C5:
    cjne a, #5, Menu_C6
    mov FSM_state_2, #5
    sjmp Microwave_Menu_Done
Menu_C6:
    cjne a, #6, Menu_C7
    mov FSM_state_2, #6
    sjmp Microwave_Menu_Done
Menu_C7:
    cjne a, #7, Menu_C8
    mov FSM_state_2, #7
    sjmp Microwave_Menu_Done
Menu_C8:
    cjne a, #8, Microwave_Menu_Done
    mov FSM_state_2, #8

Microwave_Menu_Done:
    ret


; --- Configuration States (The Recipes) ---
; These set the Temp (T*10) and Time (Seconds), then jump to State 9 (Cook)

Microwave_Pizza_Config:     ; State 1
    mov microwave_temp+0, #low(2000)
    mov microwave_temp+1, #high(2000)
    mov microwave_time+0, #low(45)
    mov microwave_time+1, #high(45)
    mov FSM_state_2, #9
    ret

Microwave_Popcorn_Config:   ; State 2
    mov microwave_temp+0, #low(1500)
    mov microwave_temp+1, #high(1500)
    mov microwave_time+0, #low(30)
    mov microwave_time+1, #high(30)
    mov FSM_state_2, #9
    ret

Microwave_Defrost_Config:   ; State 3
    mov microwave_temp+0, #low(500)
    mov microwave_temp+1, #high(500)
    mov microwave_time+0, #low(120)
    mov microwave_time+1, #high(120)
    mov FSM_state_2, #9
    ret

Microwave_Chicken_Config:   ; State 4
    mov microwave_temp+0, #low(1800)
    mov microwave_temp+1, #high(1800)
    mov microwave_time+0, #low(180)
    mov microwave_time+1, #high(180)
    mov FSM_state_2, #9
    ret

Microwave_Potato_Config:    ; State 5
    mov microwave_temp+0, #low(2100)
    mov microwave_temp+1, #high(2100)
    mov microwave_time+0, #low(240)
    mov microwave_time+1, #high(240)
    mov FSM_state_2, #9
    ret

Microwave_Beverage_Config:  ; State 6
    mov microwave_temp+0, #low(800)
    mov microwave_temp+1, #high(800)
    mov microwave_time+0, #low(60)
    mov microwave_time+1, #high(60)
    mov FSM_state_2, #9
    ret

Microwave_Soup_Config:      ; State 7
    mov microwave_temp+0, #low(900)
    mov microwave_temp+1, #high(900)
    mov microwave_time+0, #low(90)
    mov microwave_time+1, #high(90)
    mov FSM_state_2, #9
    ret

Microwave_Veggie_Config:    ; State 8
    mov microwave_temp+0, #low(1000)
    mov microwave_temp+1, #high(1000)
    mov microwave_time+0, #low(120)
    mov microwave_time+1, #high(120)
    mov FSM_state_2, #9
    ret


; --- State 9: Cooking Logic (Thermostat & Time) ---
Microwave_Cook:
	clr EA
	
	Set_Cursor(1,10)
	Send_Constant_String(#COOK_MICROWAVE)
	setb EA
	
    mov x+0, tempFinal+0
    mov x+1, tempFinal+1
    mov x+2, tempFinal+2
    mov x+3, tempFinal+3
    
    mov y+0, microwave_temp+0
    mov y+1, microwave_temp+1
    mov y+2, #0
    mov y+3, #0
    
    clr EA
    lcall x_lt_y                  ; Is current < target?
    setb EA
    
    jb mf, Heater_On
    clr SSR_PIN                   ; Too hot, turn off heater
    sjmp Tmr_Logic
Heater_On:
    setb SSR_PIN                  ; Too cold, turn on heater

Tmr_Logic:
    jnb QuarterSecondsFlag2, Cook_E
    clr QuarterSecondsFlag2
    
    inc temp_counter
    mov a, temp_counter
    cjne a, #4, Cook_E            ; Has one second passed?
    mov temp_counter, #0
    
    dec microwave_time+0          ; Countdown
    mov a, microwave_time+0
    jnz Cook_E                    ; Keep cooking if time > 0
    
    mov FSM_state_2, #10            ; Go to done state
Cook_E:
    ret


; --- State 10: Completion ---
Microwave_Done:
	Set_Cursor(1,10)
	Send_Constant_String(#DONE_MICROWAVE)
    clr SSR_PIN                   ; Safety first
    ; TODO: Sound buzzer pattern
    mov FSM_state_2, #0             ; Back to menu
    ret
