; side project file (keyboard.asm)
; ------------------------------------------------------------------------------
; This is code for a music Keyboard
; In this mode you can press any key and it will play a tone
; ------------------------------------------------------------------------------
; This include_file was made by the following people

;	- Owen Anderson 		 51069375
; ------------------------------------------------------------------------------

Keyboard_Begin:

	; checks if keypad has been pressed
    clr EA
    lcall Keypad
    setb EA
    jnc keyboard_end2      ; if no key, exit immediately
    
    sjmp keyboard_end3
    keyboard_end2:
    ljmp keyboard_end
	keyboard_end3:

    lcall Shift_Digits_Left
    
    ; moves R7 to A
    ; R7 contains the key that was pressed on the keypad
    mov A, R7

	
    setb SpeakerFlag ; sets timer 0 to play speaker
    setb SongFlag	 ; sets timer 0 to play different tones 
    
    ; check which key is pressed and plays the right tone ------------------------
    cjne A, #1, skip_button_1
    mov tone_rh, #high(R_C5)
    mov tone_rl, #low(R_C5)
    Wait_Milli_Seconds(#100)
    skip_button_1:
    
    cjne A, #2, skip_button_2
    mov tone_rh, #high(R_D5)
    mov tone_rl, #low(R_D5)
    Wait_Milli_Seconds(#100)
    skip_button_2:
   
    cjne A, #3, skip_button_3
    mov tone_rh, #high(R_E5)
    mov tone_rl, #low(R_E5)
    Wait_Milli_Seconds(#100)
    skip_button_3:
    
    cjne A, #4, skip_button_4
    mov tone_rh, #high(R_F5)
    mov tone_rl, #low(R_F5)
    Wait_Milli_Seconds(#100)
    skip_button_4:
    
    cjne A, #5, skip_button_5
    mov tone_rh, #high(R_G5)
    mov tone_rl, #low(R_G5)
    Wait_Milli_Seconds(#100)
    skip_button_5:
   
    cjne A, #6, skip_button_6
    mov tone_rh, #high(R_A5)
    mov tone_rl, #low(R_A5)
    Wait_Milli_Seconds(#100)
    skip_button_6:
    
    cjne A, #7, skip_button_7
    mov tone_rh, #high(R_B5)
    mov tone_rl, #low(R_B5)
    Wait_Milli_Seconds(#100)
    skip_button_7:
    
    cjne A, #8, skip_button_8
    mov tone_rh, #high(R_C6)
    mov tone_rl, #low(R_C6)
    Wait_Milli_Seconds(#100)
    skip_button_8:

    cjne A, #9, skip_button_9
    mov tone_rh, #high(R_D6)
    mov tone_rl, #low(R_D6)
    Wait_Milli_Seconds(#100)
    skip_button_9:
    
    cjne A, #0, skip_button_0
    mov tone_rh, #high(R_E6)
    mov tone_rl, #low(R_E6)
    Wait_Milli_Seconds(#100)
    skip_button_0:

	; ----------------------------------------------------------
	
    clr SpeakerFlag
    clr SongFlag
    
    clr EA
    lcall Display
    setb EA

keyboard_end:
    ret
