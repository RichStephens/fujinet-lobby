; lbchat.asm -- bank 5, the chat room URL
;
; A PLACEHOLDER. It exists so the image is the right size and a switch into
; this bank lands on code rather than on a page of BRK; the screen it will
; carry is not written yet.

        CPU     6502
        INCLUDE "vcs.inc"

PAD3    EQU     $81
SAVSP   EQU     $82

        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"
        INCLUDE "../build/tail.inc"

        ORG     $1000

START:  lda     #ENSHOWN
        sta     LBENT
        lda     #BANKLST
        jmp     LBGOTO

        END
