

; Variables
dseg at 0x30
tone_rh:      ds 1   ; Timer0 reload high byte for current note
tone_rl:      ds 1   ; Timer0 reload low byte for current note
songCounter:  ds 1
secondsWait:  ds 1

cseg

; -------- Note reload values (CLK = 33,333,333 Hz, prescaler = 12) --------
; Timer0 overflow rate = 2*freq (because we toggle pin each overflow)

R_C5  EQU 0xF5A2   ; 523.25 Hz (Do)
R_Cs5 EQU 0xF63F   ; 622.25 Hz (Do Sharp)
R_D5  EQU 0xF6C3   ; 587.33 Hz (Re)
R_Ds5 EQU 0xF74D   ; 739.99 Hz (Dsharp)
R_E5  EQU 0xF7C5   ; 659.26 Hz (Mi)
R_F5  EQU 0xF83B   ; 698.46 Hz (Fa)
R_Fs5 EQU 0xF8AC   ; 739.99 Hz (Fa Sharp)
R_G5  EQU 0xF914   ; 783.99 Hz (Sol)
R_Gs5 EQU 0xF97B   ; 830.61 Hz (Sol Sharp)
R_A5  EQU 0xF9D6   ; 880.00 Hz (La)
R_As5 EQU 0xFA31   ; 932.33 Hz (La Sharp)
R_B5  EQU 0xFA82   ; 987.77 Hz (Si)
R_C6  EQU 0xFAD0   ; 1046.50 Hz (Do - higher octave)
R_Cs6 EQU 0xFB1F   ; 1108.73 Hz
R_D6  EQU 0xFB61   ; 1174.66 Hz
R_Ds6 EQU 0xFBA7   ; 1244.51 Hz
R_E6  EQU 0xFBE3   ; 1318.51 Hz
R_F6  EQU 0xFC1D   ; 1396.91 Hz
R_Fs6 EQU 0xFC56   ; 1479.98 Hz
R_G6  EQU 0xFC8A   ; 1567.98 Hz
R_Gs6 EQU 0xFCBD   ; 1661.22 Hz
R_A6  EQU 0xFCEB   ; 1760.00 Hz
R_As6 EQU 0xFD19   ; 1864.66 Hz
R_B6  EQU 0xFD41   ; 1975.53 Hz
R_C7  EQU 0xFD68   ; 2093.00 Hz
No_Note  EQU 0x0000   ; 000 Hz


; Simple rhythm: C D E F G A B C
; Each note plays for 400ms
SIMPLE_RHYTHM:

    DB low(R_Gs5),  high(R_Gs5),  250  
    DB low(R_A5),  high(R_A5),  250   
    DB low(R_E6),  high(R_E6),  250  
	DB low(No_Note),  high(No_Note),  250    
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
    DB low(No_Note),  high(No_Note),  250 
    DB low(R_A5),  high(R_A5),  250   
    DB low(R_E6),  high(R_E6),  250  
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
    
    
    
    
    
	SONG_LEN EQU 76    ; number of notes

	
	
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
