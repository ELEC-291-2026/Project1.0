$NOLIST
$MODMAX10
$LIST

; ============================================================
; 8052 / CV_8052 (DE10-Lite) - "Done Song" Full Example
; Clock: 33.333333 MHz
; Timer2: 1ms tick
; Timer0: tone generator (toggle SPEAKER each overflow)
; ============================================================

CLK            EQU 33333333
TIMER2_RATE    EQU 1000
TIMER2_RELOAD  EQU (65536-(CLK/(12*TIMER2_RATE)))  ; 1ms tick

; -------------------------
; Pick your speaker pin here
; -------------------------
SPEAKER        BIT P1.0    

; ============================================================
; Interrupt vectors
; ============================================================
CSEG at 0x0000
    ljmp main

CSEG at 0x000B               ; Timer0 overflow vector
    ljmp Timer0_ISR

CSEG at 0x002B               ; Timer2 overflow vector (8052)
    ljmp Timer2_ISR

; ============================================================
; RAM variables
; ============================================================
DSEG at 0x40
ms_ticks:   ds 2             ; 16-bit millisecond counter
tone_rl:    ds 1             ; Timer0 reload low byte
tone_rh:    ds 1             ; Timer0 reload high byte
tone_on:    ds 1             ; 0=silent, 1=toggle SPEAKER

; ============================================================
; Code
; ============================================================
CSEG

; ------------------------------------------------------------
; InitTimers: sets up Timer0 (tone) + Timer2 (1ms tick)
; ------------------------------------------------------------
InitTimers:
    ; Timer0: Mode 1 (16-bit)
    anl TMOD, #0F0h
    orl TMOD, #01h

    ; Timer2: auto-reload 1ms tick
    mov T2CON, #00h           ; Timer2 as timer, auto-reload
    mov RCAP2H, #HIGH(TIMER2_RELOAD)
    mov RCAP2L, #LOW(TIMER2_RELOAD)
    mov TH2,    #HIGH(TIMER2_RELOAD)
    mov TL2,    #LOW(TIMER2_RELOAD)

    ; Clear counters / flags
    mov ms_ticks,   #00h
    mov ms_ticks+1, #00h
    mov tone_on,    #00h
    clr SPEAKER

    ; Enable interrupts
    setb ET0                  ; Timer0 interrupt enable
    setb ET2                  ; Timer2 interrupt enable
    setb EA                   ; global enable

    ; Start Timer2 (1ms tick). Timer0 starts only when playing.
    setb TR2

    ret

; ------------------------------------------------------------
; Timer2 ISR: runs every 1ms -> increments ms_ticks
; ------------------------------------------------------------
Timer2_ISR:
    push acc

    ; Clear Timer2 overflow flag
    clr TF2

    inc ms_ticks
    mov a, ms_ticks
    jnz T2_done
    inc ms_ticks+1

T2_done:
    pop acc
    reti

; ------------------------------------------------------------
; Timer0 ISR: reload TH0/TL0 and toggle SPEAKER if tone_on=1
; ------------------------------------------------------------
Timer0_ISR:
    push acc

    ; Reload timer
    mov TH0, tone_rh
    mov TL0, tone_rl

    mov a, tone_on
    jz  T0_silent
    cpl SPEAKER               ; toggle pin -> square wave
    sjmp T0_done

T0_silent:
    clr SPEAKER               ; keep low when silent (optional)

T0_done:
    pop acc
    reti

; ------------------------------------------------------------
; WaitMs: wait R7 milliseconds using ms_ticks
; (Safe 16-bit compare, works across wrap)
; ------------------------------------------------------------
WaitMs:
    push acc
    push b
    push dpl
    push dph

    ; start = ms_ticks
    mov dpl, ms_ticks
    mov dph, ms_ticks+1

WaitMs_loop:
    ; elapsed = current - start (16-bit)
    mov a, ms_ticks
    clr c
    subb a, dpl
    mov b, a                  ; elapsed low
    mov a, ms_ticks+1
    subb a, dph               ; elapsed high in A

    ; if elapsed >= R7 (and R7 <= 255), just check high==0 and low>=R7,
    ; OR if high != 0, elapsed is definitely >= R7.
    mov a, ms_ticks+1
    clr c
    subb a, dph               ; recompute elapsed high quickly
    jnz WaitMs_done           ; if elapsed high != 0 => elapsed >= 256 >= R7

    mov a, b
    clr c
    subb a, r7
    jc  WaitMs_loop           ; elapsed < R7 -> keep waiting

WaitMs_done:
    pop dph
    pop dpl
    pop b
    pop acc
    ret

; ------------------------------------------------------------
; PlayTone:
; Inputs:
;   R5 = reload high (TH0)
;   R6 = reload low  (TL0)
;   R7 = duration (ms)
; ------------------------------------------------------------
PlayTone:
    mov tone_rh, r5
    mov tone_rl, r6

    mov TH0, tone_rh
    mov TL0, tone_rl

    mov tone_on, #01h
    setb TR0

    lcall WaitMs         ; duration in R7

    clr TR0
    mov tone_on, #00h
    clr SPEAKER

    ; --- staccato gap ---
    mov r7, #20          ; 20ms silence
    lcall WaitMs

    ret

; ------------------------------------------------------------
; Done Song (converted from your Windows Beep list)
; 261,261,392,392,440,440,392 with 250ms each
; Using reload = 65536 - CLK/(24*f)
; Precomputed for CLK=33.333333MHz:
;   261 Hz -> 0xF9D1
;   392 Hz -> 0xFB8A
;   440 Hz -> 0xFBF5
; ------------------------------------------------------------
PlayDoneSong:
    ; 261
    mov r5, #0F9h
    mov r6, #0D1h
    mov r7, #250
    lcall PlayTone

    mov r5, #0F9h
    mov r6, #0D1h
    mov r7, #250
    lcall PlayTone

    ; 392
    mov r5, #0FBh
    mov r6, #08Ah
    mov r7, #250
    lcall PlayTone

    mov r5, #0FBh
    mov r6, #08Ah
    mov r7, #250
    lcall PlayTone

    ; 440
    mov r5, #0FBh
    mov r6, #0F5h
    mov r7, #250
    lcall PlayTone

    mov r5, #0FBh
    mov r6, #0F5h
    mov r7, #250
    lcall PlayTone

    ; 392 (final)
    mov r5, #0FBh
    mov r6, #08Ah
    mov r7, #250
    lcall PlayTone

    ret

; ------------------------------------------------------------
; MAIN (demo): init, play song once, then loop forever
; In your project: call PlayDoneSong in DONE state instead.
; ------------------------------------------------------------
main:
    lcall InitTimers

    ; demo play once:
    lcall PlayDoneSong

Forever:
    sjmp Forever

END
