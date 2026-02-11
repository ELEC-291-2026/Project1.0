; Simple_Rhythm_DE10Lite.asm:
; Plays C D E F G A B C once (no loop)
; Press KEY.1 to play again
;
$NOLIST
$MODMAX10
$LIST

CLK           EQU 33333333 ; Microcontroller system crystal frequency in Hz
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/(12*TIMER2_RATE))))

SOUND_OUT     equ P0.4

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; Variables
dseg at 0x30
Count1ms:     ds 2   ; 1ms counter for Timer2
song_idx:     ds 1   ; which note we're on (0-7)
note_ms:      ds 2   ; how long current note has played (ms)
tone_rh:      ds 1   ; Timer0 reload high byte for current note
tone_rl:      ds 1   ; Timer0 reload low byte for current note
note_dur_l:   ds 1   ; Current note duration low byte
note_dur_h:   ds 1   ; Current note duration high byte

bseg
song_playing: dbit 1 ; Flag: is song currently playing?

cseg

; -------- Note reload values (CLK = 33,333,333 Hz, prescaler = 12) --------
; Timer0 overflow rate = 2*freq (because we toggle pin each overflow)

R_C5  EQU 0F5A2h   ; 523.25 Hz (Do)
R_D5  EQU 0F6C3h   ; 587.33 Hz (Re)
R_E5  EQU 0F7C5h   ; 659.26 Hz (Mi)
R_F5  EQU 0F83Bh   ; 698.46 Hz (Fa)
R_G5  EQU 0F914h   ; 783.99 Hz (Sol)
R_A5  EQU 0F9D6h
R_B5  EQU 0FA82h
R_C6  EQU 0FAD0h   ; 1046.50 Hz (Do - higher octave)

; Simple rhythm: C D E F G A B C
; Each note plays for 400ms
SIMPLE_RHYTHM:
    DW R_C5, 400    ; Do
    DW R_C5, 400    ; Do
    DW R_G5, 400    ; Sol
    DW R_G5, 400    ; Sol
    DW R_A5, 400    ; La
    DW R_A5, 400    ; La
    DW R_G5, 600    ; Sol
    DW R_F5, 400    ; Fa
    DW R_F5, 400    ; Fa
    DW R_E5, 400    ; Sol
    DW R_E5, 400    ; La
    DW R_D5, 400    ; Si
    DW R_D5, 400    ; Do (longer final note)
    DW R_C5, 600    ; Do (longer final note)
    

SONG_LEN EQU 14    ; number of notes

;---------------------------------;
; Load current note from song     ;
; Input: song_idx (0-7)          ;
;---------------------------------;
Load_Song_Note:
    push acc
    push dph
    push dpl
    
    ; Each note is 4 bytes: 2 for reload, 2 for duration
    ; Offset = song_idx * 4
    mov a, song_idx
    rl a              ; *2
    rl a              ; *4
    anl a, #0FCh      ; Ensure it's a multiple of 4
    
    mov dptr, #SIMPLE_RHYTHM
    
    ; Get reload high byte
    movc a, @a+dptr
    mov tone_rh, a
    
    ; Get reload low byte
    mov a, song_idx
    rl a
    rl a
    anl a, #0FCh
    inc a
    movc a, @a+dptr
    mov tone_rl, a
    
    ; Get duration low byte
    mov a, song_idx
    rl a
    rl a
    anl a, #0FCh
    add a, #2
    movc a, @a+dptr
    mov note_dur_h, a
    
    ; Get duration high byte
    mov a, song_idx
    rl a
    rl a
    anl a, #0FCh
    add a, #3
    movc a, @a+dptr
    mov note_dur_l, a
    
    ; Reset note timing counter
    clr a
    mov note_ms+0, a
    mov note_ms+1, a
    
    ; Load timer and start
    mov TH0, tone_rh
    mov TL0, tone_rl
    setb TR0              ; Start Timer0
    
    pop dpl
    pop dph
    pop acc
    ret

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	
	; Don't start timer yet - Load_Song_Note will do it
    setb ET0  ; Enable timer 0 interrupt
	ret

;---------------------------------;
; ISR for timer 0.                ;
; Generates square wave for tone  ;
;---------------------------------;
Timer0_ISR:
	; Reload timer with current note's value
	mov TH0, tone_rh
	mov TL0, tone_rl
	cpl SOUND_OUT ; Toggle speaker
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
	; Init One millisecond interrupt counter
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2 (1ms tick)      ;
; Handles note timing             ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically
	cpl P1.1 ; Debug: Check interrupt rate with oscilloscope
	
	push acc
	push psw
	
	; Only process if song is playing
	jnb song_playing, Timer2_ISR_done
	
	; Increment note duration counter
	inc note_ms+0
	mov a, note_ms+0
	jnz Check_Note_Duration
	inc note_ms+1
	
Check_Note_Duration:
	; Check if note duration has elapsed
	mov a, note_ms+0
	cjne a, note_dur_l, Timer2_ISR_done
	mov a, note_ms+1
	cjne a, note_dur_h, Timer2_ISR_done
	
	; Note duration elapsed - advance to next note
	mov a, song_idx
	inc a
	
	; Check if song is finished
	cjne a, #SONG_LEN, Next_Note_OK
	
	; *** SONG FINISHED - STOP PLAYING ***
	clr song_playing
	clr TR0               ; Stop Timer0
	clr SOUND_OUT         ; Turn off speaker
	setb LEDRA.0          ; Turn on LED to show song finished
	sjmp Timer2_ISR_done
	
Next_Note_OK:
	mov song_idx, a
	lcall Load_Song_Note
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
    mov SP, #0x7F
    
    ; Configure I/O pins
    mov P0MOD, #00010000b ; P0.4 (SOUND_OUT) is output
    mov P1MOD, #00000010b ; P1.1 is output (debug)
    
    ; Turn off all the LEDs
    mov LEDRA, #0
    mov LEDRB, #0
    
    ; Initialize timers
    lcall Timer0_Init
    lcall Timer2_Init
    
    ; Initialize song (but don't play yet)
    mov song_idx, #0
    clr song_playing      ; Wait for button press
    
    setb EA   ; Enable Global interrupts
	
	; Main loop - wait for button to play
loop:
	; Press KEY.1 to play the rhythm
	jb KEY.1, loop
	jnb KEY.1, $          ; Wait for release
	
	; Only play if not already playing
	jb song_playing, loop
	
	; Start playing from beginning
	clr LEDRA.0           ; Turn off LED
	mov song_idx, #0
	lcall Load_Song_Note
	setb song_playing
	
	sjmp loop

END