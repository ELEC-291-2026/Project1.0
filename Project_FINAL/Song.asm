

; Variables
dseg at 0x30
tone_rh:      ds 1   ; Timer0 reload high byte for current note
tone_rl:      ds 1   ; Timer0 reload low byte for current note
songCounter:  ds 1
secondsWait:  ds 1

bseg
song_playing: dbit 1 ; Flag: is song currently playing?

cseg

; -------- Note reload values (CLK = 33,333,333 Hz, prescaler = 12) --------
; Timer0 overflow rate = 2*freq (because we toggle pin each overflow)

R_C5  EQU 0F5A2h   ; 523.25 Hz (Do)
R_Cs5 EQU 0F63Fh   ; 622.25 Hz (Do Sharp)
R_D5  EQU 0F6C3h   ; 587.33 Hz (Re)
R_Ds5 EQU 0F74Dh   ; 739.99 Hz (Dsharp)
R_E5  EQU 0F7C5h   ; 659.26 Hz (Mi)
R_F5  EQU 0F83Bh   ; 698.46 Hz (Fa)
R_Fs5 EQU 0F8ACh   ; 739.99 Hz (Fa Sharp)
R_G5  EQU 0F914h   ; 783.99 Hz (Sol)
R_Gs5 EQU 0F97Bh   ; 830.61 Hz (Sol Sharp)
R_A5  EQU 0F9D6h   ; 880.00 Hz (La)
R_As5 EQU 0FA31h   ; 932.33 Hz (La Sharp)
R_B5  EQU 0FA82h   ; 987.77 Hz (Si)
R_C6  EQU 0FAD0h   ; 1046.50 Hz (Do - higher octave)
R_Cs6 EQU 0FB1Fh   ; 1108.73 Hz
R_D6  EQU 0FB61h   ; 1174.66 Hz
R_Ds6 EQU 0FBA7h   ; 1244.51 Hz
R_E6  EQU 0FBE3h   ; 1318.51 Hz
R_F6  EQU 0FC1Dh   ; 1396.91 Hz
R_Fs6 EQU 0FC56h   ; 1479.98 Hz
R_G6  EQU 0FC8Ah   ; 1567.98 Hz
R_Gs6 EQU 0FCBDh   ; 1661.22 Hz
R_A6  EQU 0FCEBh   ; 1760.00 Hz
R_As6 EQU 0FD19h   ; 1864.66 Hz
R_B6  EQU 0FD41h   ; 1975.53 Hz
R_C7  EQU 0FD68h   ; 2093.00 Hz
No_Note  EQU 0000h   ; 000 Hz


; Simple rhythm: C D E F G A B C
; Each note plays for 400ms
SIMPLE_RHYTHM:

    DB low(R_C5),  high(R_C5),  250    
    DB low(R_Cs5), high(R_Cs5), 250   
    DB low(R_D5),  high(R_D5),  250   
    DB low(R_Ds5), high(R_Ds5), 250  
    DB low(R_E5),  high(R_E5),  250  
    DB low(R_F5),  high(R_F5),  250    
    DB low(R_Fs5), high(R_Fs5), 250  
    DB low(R_G5),  high(R_G5),  250     
    DB low(R_Gs5), high(R_Gs5), 250   
    DB low(R_A5),  high(R_A5),  250    
    DB low(R_As5), high(R_As5), 250 
    DB low(R_B5),  high(R_B5),  250 
    DB low(No_Note), high(No_Note), 250
    DB low(No_Note), high(No_Note), 250
    DB low(R_C6),  high(R_C6),  250  
    DB low(R_Cs6), high(R_Cs6), 250  
    DB low(R_D6),  high(R_D6),  250    
    DB low(R_Ds6), high(R_Ds6), 250     
    DB low(R_E6),  high(R_E6),  250   
    DB low(R_F6),  high(R_F6),  250    
    DB low(R_Fs6), high(R_Fs6), 250 
    DB low(R_G6),  high(R_G6),  250    
    DB low(R_Gs6), high(R_Gs6), 250  
    DB low(R_A6),  high(R_A6),  250    
    DB low(R_As6), high(R_As6), 250 
    DB low(R_B6),  high(R_B6),  250 

    

SONG_LEN EQU 26    ; number of notes
	
	
	
Play_song:


	setb SpeakerFlag
	setb SongFlag
	mov songCounter, #0x00
	mov DPTR, #SIMPLE_RHYTHM
	mov secondsWait, #0x00
	
	forever_song:
		
		movc a,@a+DPTR
		mov tone_rl, a
		inc DPTR
		
		movc a,@a+DPTR
		mov tone_rh, a
		inc DPTR
		
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
