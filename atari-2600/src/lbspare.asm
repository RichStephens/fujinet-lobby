; lbspare.asm -- the spare bank.
;
; An image has to be 4K, 8K, 16K or 32K -- MAME's cart slot accepts no other
; size -- so 16K is the one that fits six banks and a fixed half, and a
; seventh exists whether or not it is wanted. Rather than leave it as filler,
; it holds a stub back to bank 0: a stray bank switch then lands somewhere
; sensible instead of in a page of $FF, which disassembles as ISC and runs
; until it hits something.

        CPU     6502
        INCLUDE "vcs.inc"

PAD3    EQU     $81
SAVSP   EQU     $82

        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"
        INCLUDE "../build/tail.inc"

        ORG     $1000

START:  lda     #ENCOLD         ; whatever brought us here, nothing is known
        sta     LBENT           ;   about the state, so start over
        lda     #BANKLST
        jmp     LBGOTO

        END
