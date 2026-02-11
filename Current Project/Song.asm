$NOLIST
$MODMAX10
$LIST

CLK            EQU 33333333
TIMER2_RATE    EQU 1000
TIMER2_RELOAD  EQU (65536-(CLK/(12*TIMER2_RATE))) ; 1ms tick

; 2 kHz tone
TONE_RATE      EQU 4000
TIMER0_RELOAD  EQU (65536-(CLK/(12*TONE_RATE)))

SPEAKER        BIT P1.0

; --------------------------
; VECTORS
; --------------------------
CSEG at 0x0000
    ljmp main

CSEG at 0x000B
    ljmp Timer0_ISR

CSEG at 0x002B
    ljmp Timer2_ISR

; --------------------------
; RAM
; --------------------------
DSEG at 0x40
ms_lo: ds 1
ms_hi: ds 1

CSEG

; --------------------------
; Timer0: tone
; --------------------------
Timer0_Init:
    anl TMOD, #0F0h
    orl TMOD, #01h
    mov TH0, #HIGH(TIMER0_RELOAD)
    mov TL0, #LOW(TIMER0_RELOAD)
    setb ET0
    ret

Timer0_ISR:
    mov TH0, #HIGH(TIMER0_RELOAD)
    mov TL0, #LOW(TIMER0_RELOAD)
    cpl SPEAKER
    reti

; --------------------------
; Timer2: 1 ms counter
; --------------------------
Timer2_Init:
    mov T2CON, #00h
    mov RCAP2H,#HIGH(TIMER2_RELOAD)
    mov RCAP2L,#LOW(TIMER2_RELOAD)
    mov TH2,#HIGH(TIMER2_RELOAD)
    mov TL2,#LOW(TIMER2_RELOAD)

    mov ms_lo,#0
    mov ms_hi,#0

    setb IE.5        ; ET2
    setb TR2
    ret

Timer2_ISR:
    inc ms_lo
    mov a, ms_lo
    jnz t2_done
    inc ms_hi
t2_done:
    reti

; --------------------------
; Wait R7 ms
; --------------------------
WaitMs:
    mov r6, ms_lo
    mov r5, ms_hi

wait_loop:
    mov a, ms_lo
    clr c
    subb a, r6
    mov b, a

    mov a, ms_hi
    subb a, r5
    jnz done

    mov a, b
    clr c
    subb a, r7
    jc wait_loop
done:
    ret

; --------------------------
; MAIN
; --------------------------
main:
    mov SP,#7Fh

    lcall Timer0_Init
    lcall Timer2_Init
    setb EA

forever:
    setb TR0        ; sound ON
    mov r7,#250
    lcall WaitMs
    mov r7,#250
    lcall WaitMs

    clr TR0         ; sound OFF
    clr SPEAKER
    mov r7,#250
    lcall WaitMs
    mov r7,#250
    lcall WaitMs

    sjmp forever

END
