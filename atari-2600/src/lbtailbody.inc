; lbtailbody.inc -- the contents of the fixed half.
;
; Included by lbtail.asm, which becomes the real client's last 2K, AND by
; layout.asm, whose flat 4K image carries its own fixed half. Sharing the
; source is what makes the addresses in build/tail.inc true for both: the
; sibling port's layout ROM once included only the generated equates, and
; every jsr into the shared transport landed on p2bin's filler.

; LBGOTO is not a label here: lbdefs.inc gives it a fixed address and this ORG
; is what makes that true, so the two cannot drift apart. It must be FIRST in
; the tail, because it is the one address a bank has to know before
; build/tail.inc exists.
        ORG     LBGOTO

; ---------------------------------------------------------------------------
; LBGOTO -- select bank A and enter it at $1000.
;
; `sta FNRSEL,x` is the documented-safe indexed form: the base low byte is $00
; so the index cannot carry, which means the dummy read STA abs,X always
; performs lands on the same address as the write.
        clc
        adc     #FH_BANK
        tax
        sta     FNRSEL,x
; RESET THE STACK. A bank switch is a JUMP and nothing ever returns through
; one, so every switch abandons whatever return addresses were on the stack --
; and the switches here are taken from inside APPVBL, which DFRAME reached
; with a JSR. 5 Card Stud leaked two bytes per switch, and after thirty-five
; of them the stack had grown down out of its 64 bytes and was overwriting the
; entry code: a bank dispatching on the low byte of a return address.
;
; This is the one place it can be got right once. The store above has already
; switched the bank, but these instructions are fetched from the FIXED tail,
; which is not banked, so they still execute.
        ldx     #$FF
        txs
        jmp     $1000

; ---------------------------------------------------------------------------
; The shared transport. tools/mktail.py turns the addresses these assemble to
; into build/tail.inc, which is what the banks include.
        INCLUDE "lbcore.inc"

; ---------------------------------------------------------------------------
; LBCOLD -- power-on and RESET.
;
; Deliberately TINY. Everything else a cold start has to do -- clear the 128
; bytes, blank the screen, empty the cartridge's four path buffers, read the
; username -- is done by bank 0, because the tail is 220 bytes and the shared
; transport wants most of them.
;
; A cold stub in bank 0 would not do. This console has NO RESET LINE to the
; cartridge: the RESET switch restarts the 6507 with whatever bank was last
; selected still mapped, so the stub has to be somewhere every bank can see.
LBCOLD: sei
        cld
        ldx     #$FF
        txs
; FORCE A COLD ENTRY. This console does not clear its RAM on a reset, so LBENT
; -- the byte that says what the bank being entered should do -- still holds
; whatever the last screen set it to. A reset taken during a boot would come
; back into the boot bank's warm path and poll a progress bar for a transfer
; that is not running.
        lda     #ENCOLD
        sta     LBENT
        lda     #FNAM1
        sta     FNRSEL+FH_ARM1
        lda     #FNAM2
        sta     FNRSEL+FH_ARM2
        lda     #BANKLST
        jmp     LBGOTO

        ORG     $1FFC
        DW      LBCOLD
        DW      LBCOLD
