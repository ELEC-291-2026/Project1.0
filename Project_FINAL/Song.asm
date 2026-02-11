

; Variables
dseg at 0x30
tone_rh:      ds 1   ; Timer0 reload high byte for current note
tone_rl:      ds 1   ; Timer0 reload low byte for current note
songCounter:  ds 1
secondsWait:  ds 1

cseg

; -------- Note reload values (CLK = 33,333,333 Hz, prescaler = 12) --------
; Timer0 overflow rate = 2*freq (because we toggle pin each overflow)



; Simple rhythm: C D E F G A B C
; Each note plays for 400ms
SIMPLE_RHYTHM:

    DB low(R_Gs5),  high(R_Gs5),  250  
    DB low(R_A5),  high(R_A5),  250   
    DB low(R_E6),  high(R_E6),  250  
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
	DB low(No_Note),  high(No_Note),  250    
    DB low(R_A5),  high(R_A5),  250   
    DB low(R_E6),  high(R_E6),  250  
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
    DB low(R_E6),  high(R_E6),  250
    DB low(R_D6),  high(R_D6),  250  
    DB low(R_C6),  high(R_C6),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_D6),  high(R_D6),  250  
    DB low(R_C6),  high(R_C6),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_A5),  high(R_A5),  250  
    DB low(R_E6),  high(R_E6),  250  
	DB low(No_Note),  high(No_Note),  250 
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
    DB low(R_A5),  high(R_A5),  250   
    DB low(R_E6),  high(R_E6),  250 
	DB low(No_Note),  high(No_Note),  250 
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
    DB low(No_Note),  high(No_Note),  250 
	DB low(R_E6),  high(R_E6),  250
    DB low(R_D6),  high(R_D6),  250  
    DB low(R_C6),  high(R_C6),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_D6),  high(R_D6),  250  
    DB low(R_C6),  high(R_C6),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_A5),  high(R_A5),  250  
    DB low(R_A5),  high(R_A5),  250  
    DB low(No_Note),  high(No_Note),  250 
    DB low(No_Note),  high(No_Note),  250 
    DB low(R_A6),  high(R_A6),  250 
	DB low(No_Note),  high(No_Note),  250 
    DB low(No_Note),  high(No_Note),  250  
    DB low(R_G6),  high(R_G6),  250 
	DB low(No_Note),  high(No_Note),  250 
    DB low(No_Note),  high(No_Note),  250  
    DB low(R_E6),  high(R_E6),  250 
    DB low(R_F6),  high(R_F6),  250 
    DB low(R_G6),  high(R_G6),  250 
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
    DB low(R_D6),  high(R_D6),  250 
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
    DB low(R_Cs6),  high(R_Cs6),  250 
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
	DB low(R_E6),  high(R_E6),  250
    DB low(R_D6),  high(R_D6),  250  
    DB low(R_C6),  high(R_C6),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_D6),  high(R_D6),  250  
    DB low(R_C6),  high(R_C6),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_A5),  high(R_A5),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_C6),  high(R_C6),  250
	DB low(R_D6),  high(R_D6),  250  

	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 

    DB low(R_E6),  high(R_E6),  250  
	DB low(R_Ds6), high(R_Ds6), 250  
    DB low(R_E6),  high(R_E6),  250  
	DB low(R_Ds6), high(R_Ds6), 250  
    DB low(R_E6),  high(R_E6),  250  
    DB low(R_B6),  high(R_B6),  250 
	DB low(R_D6), high(R_D6), 250  
    DB low(R_C6),  high(R_C6),  250    
    DB low(R_A5),  high(R_A5),  250    
    DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250    
    DB low(R_C5),  high(R_C5),  250  
	DB low(R_E5),  high(R_E5),  250  
	DB low(R_A5),  high(R_A5),  250  
	DB low(R_B5),  high(R_B5),  250  
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250    
    DB low(R_E5),  high(R_E5),  250  
    DB low(R_Gs5),  high(R_Gs5),  250  
    DB low(R_B5),  high(R_B5),  250  
    DB low(R_C6),  high(R_C6),  250  
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250    
	DB low(R_E5),  high(R_E5),  250
    DB low(R_E6),  high(R_E6),  250  
	DB low(R_Ds6), high(R_Ds6), 250  
    DB low(R_E6),  high(R_E6),  250  
	DB low(R_Ds6), high(R_Ds6), 250  
    DB low(R_E6),  high(R_E6),  250  
    DB low(R_B6),  high(R_B6),  250 
	DB low(R_Ds6), high(R_Ds6), 250  
    DB low(R_C6),  high(R_C6),  250    
    DB low(R_A5),  high(R_A5),  250    
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
	DB low(R_C5),  high(R_C5),  250  
	DB low(R_E5),  high(R_E5),  250  
	DB low(R_A5),  high(R_A5),  250  
	DB low(R_B5),  high(R_B5),  250  
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
	DB low(R_E5),  high(R_E5),  250  
	DB low(R_C6),  high(R_C6),  250 
	DB low(R_B5),  high(R_B5),  250 
	DB low(R_A5),  high(R_A5),  250 
	DB low(No_Note),  high(No_Note),  250    
    DB low(No_Note),  high(No_Note),  250 
    
	SONG_LEN EQU 117    ; number of notes

	
	
Play_song:


	setb SpeakerFlag
	setb SongFlag
	mov songCounter, #0x00
	mov DPTR, #SIMPLE_RHYTHM
	mov secondsWait, #0x00
	
	forever_song:
		
		
		clr a
		movc a,@a+DPTR
		mov tone_rl, a
		inc DPTR
		
		clr a
		movc a,@a+DPTR
		mov tone_rh, a
		inc DPTR
		
		clr a
		movc a,@a+DPTR
		mov secondsWait, a
		inc DPTR

		
		Wait_Milli_Seconds(secondsWait)
		
		inc songCounter
		
		mov a, songCounter
		
	cjne a, #SONG_LEN, forever_song
	
	clr SpeakerFlag
	clr SongFlag
	ret
END
