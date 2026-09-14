; lbboot.asm -- bank 4: set the path, mount, watch the bar, swap.
;
; By the time this bank is entered the host is mounted and the appkey is
; written, so it takes no argument at all: THE CARTRIDGE'S PATH BUFFER ALREADY
; HOLDS the full path of the image to boot, and SET_DEVICE_FULLPATH emits all
; 256 payload bytes of it with one store. That is the whole reason this can be
; a bank of its own.
;
; MOUNT_IMAGE only STARTS the push. What follows is a progress bar over
; FN_R_BOOT_PCT until FN_R_BOOT_STATE says ready, and then the swap -- which
; replaces every byte of the window including the code that asked for it, so
; the store that does it has to run from console RAM.

        CPU     6502
        INCLUDE "vcs.inc"

PAD3    EQU     $81             ; the display kernel's 3-cycle pad target
SAVSP   EQU     $82

LBHASTX EQU     1               ; emits a path buffer into TX
LBLSWAP EQU     1               ; ...and is the one bank that swaps

        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"
        INCLUDE "../build/tail.inc"

BROWT   EQU     6               ; "MOUNTING"
BROWB   EQU     8               ; the bar
BROWP   EQU     10              ; the percentage
BROWW   EQU     12              ; "DO NOT POWER OFF" -- as much as fits
BROWE   EQU     14              ; where a failure is reported

; ~60 seconds. A mount is a whole ROM over TNFS and then over the serial link,
; and the sibling ports all found that a bound of a few seconds gives up on
; transfers that were going to succeed.
BTIMO   EQU     240             ; quarter-seconds
BTICK   EQU     15              ; frames per quarter-second

        ORG     $1000

START:  lda     #2
        sta     VBLANK
        jsr     FNCLS

        ldx     #(SMOUNT)&$FF
        ldy     #(SMOUNT)>>8
        jsr     FNSETP
        lda     #BROWT
        jsr     FNSTRA
        ldx     #BROWT
        lda     #CLHDR
        sta     LBCLS,x

        ldx     #(SWARN)&$FF
        ldy     #(SWARN)>>8
        jsr     FNSETP
        lda     #BROWW
        jsr     FNSTRA

        lda     #0
        sta     LBTMR           ; the last percentage drawn
        jsr     BAR
        jsr     BPCT

        lda     #0
        sta     VBLANK
        jsr     DINIT
        jsr     DFRAME          ; the screen before the stall, not after

        jsr     SDFP
        bne     BFAIL
        jsr     MIMG
        bne     BFAIL

        lda     #BTIMO
        sta     LBSTG           ; quarter-seconds left -- LBSTG is dead from
        lda     #BTICK          ;   the moment a boot is under way
        sta     LBSCRL
        jmp     DLOOP

; ---------------------------------------------------------------------------
; APPVBL -- watch the transfer.
;
; AND ACT ON NOTHING ELSE. The input is still scanned, in DFRAME, as it is in
; every bank -- but a press must not cancel a boot: the host slot has already
; been rewritten and the appkey already carries this room, so "back out" is
; not a state that exists any more.
APPVBL: lda     FNBST
        cmp     #FNBFAIL
        bcs     BDIED
        cmp     #FNBRDY
        beq     BREADY

        lda     FNBPC
        cmp     LBTMR
        beq     BTIM
        sta     LBTMR
        jsr     BAR
        jsr     BPCT

; The timeout counts in quarter-seconds so a byte can hold a minute of them.
BTIM:   dec     LBSCRL
        bne     BT9
        lda     #BTICK
        sta     LBSCRL
        dec     LBSTG
        bne     BT9
        lda     #FNEWAIT
        sta     LBERR
        jmp     BFAIL2
BT9:    rts

; The cartridge says the image is staged. Arm the lock, then go.
BREADY: jsr     FNBLK
        jmp     FNSWAP          ; does not return -- the next fetch is the new
                                ;   image's own reset vector

BDIED:  lda     FNBER
        sta     LBERR
BFAIL2: lda     #7
        sta     LBSTEP
        ; fall through

; ---------------------------------------------------------------------------
; BFAIL -- say what happened, hold it long enough to read, and go back to a
; cold start. Nothing is left mounted that matters, and the list is refetched
; because a room that would not boot may well have gone away.
BFAIL:  lda     #BROWE
        jsr     FNROWA
        ldx     #(SERR)&$FF
        ldy     #(SERR)>>8
        jsr     FNSETP
        jsr     FNSTRC
        lda     LBSTEP
        jsr     LBDEC2
        lda     #' '
        sta     FNRSEL+FH_TCHR
        lda     LBERR
        jsr     FNHEX
        jsr     FNENDR
        ldx     #BROWE
        lda     #CLSEL
        sta     LBCLS,x
        lda     #FAILFRM
        sta     LBTMR
BFW:    jsr     DFRAME
        dec     LBTMR
        bne     BFW
        lda     #ENCOLD
        sta     LBENT
        lda     #BANKLST
        jmp     LBGOTO

; ---------------------------------------------------------------------------
; BAR -- a twelve-cell bar, one character a cell.
;
; Composed as a row rather than poked through the blit port a cell at a time.
; The blit request slot is single -- a second blit fired before the first has
; run is lost on hardware and invisible in emulation -- so twelve pokes want
; twelve waits on FN_B_BLITGEN, and this screen has nothing else to spend its
; vblank on anyway.
BAR:    lda     LBTMR
        cmp     #100
        bcc     BAR1
        lda     #99
BAR1:   ldy     #0              ; cells = pct * 12 / 100, near enough: each
BARL:   cmp     #9              ;   cell is a whole twelfth and the last one
        bcc     BAR2            ;   lands at 99
        sec
        sbc     #9
        iny
        cpy     #FNTCOL
        bcc     BARL
BAR2:   sty     LBIDX

        lda     #BROWB
        jsr     FNROWA
        ldy     #0
BARD:   cpy     LBIDX
        bcs     BARE
        lda     #'#'
        jmp     BARF
BARE:   lda     #'.'
BARF:   sta     FNRSEL+FH_TCHR
        iny
        cpy     #FNTCOL
        bcc     BARD
        jsr     FNENDR
        ldx     #BROWB
        lda     #CLROOM
        sta     LBCLS,x
        rts

; BPCT -- the number, because a bar alone cannot tell slow from stopped.
BPCT:   lda     #BROWP
        jsr     FNROWA
        lda     LBTMR
        jsr     LBDEC2
        lda     #'%'
        sta     FNRSEL+FH_TCHR
        jmp     FNENDR

; ---------------------------------------------------------------------------
; SDFP -- SET_DEVICE_FULLPATH(slot, host, mode, the path). One store emits all
; 256 payload bytes, out of the cartridge's own buffer.
SDFP:   lda     #FNDEVF
        sta     FNDEV
        lda     #FCSDFP
        sta     FNCMD
        lda     #3
        sta     FNNPR
        jsr     FNBEG
        lda     #DEVSLOT
        jsr     FNPB
        lda     #NHOSTS-1       ; the slot lbprep claimed
        jsr     FNPB
        lda     #FMREAD
        jsr     FNPB
        lda     #PBPATH
        jsr     FNWSEL
        jsr     FNWTX
        lda     #6
        sta     LBSTEP
        jmp     BGO

; MIMG -- MOUNT_IMAGE. This is what starts the push.
MIMG:   lda     #FNDEVF
        sta     FNDEV
        lda     #FCMIMG
        sta     FNCMD
        lda     #2
        sta     FNNPR
        jsr     FNBEG
        lda     #DEVSLOT
        jsr     FNPB
        lda     #FMREAD
        jsr     FNPB
        lda     #7
        sta     LBSTEP
        ; fall through

BGO:    jsr     FNGO
        sta     LBERR
        cmp     #FNEOK
        bne     BGO9
        jsr     FNACK
        sta     LBERR
BGO9:   rts

; ---------------------------------------------------------------------------
        INCLUDE "lblib.inc"
        INCLUDE "lbdisp.inc"

SMOUNT: DB      "MOUNTING",0
SWARN:  DB      "DO NOT STOP",0
SERR:   DB      "ERR ",0

        END
