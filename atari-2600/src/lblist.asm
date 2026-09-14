; lblist.asm -- bank 0: the cold start, the username, and the cursor.
;
; THIS BANK COMPOSES ALMOST NOTHING. The list, the title and the error line are
; all bank 1's, because a record can only be rendered while it is in the reply
; window and the window holds two records at a time. What is left here is the
; cold start, the two rows only this bank can draw, and a cursor that moves by
; storing two bytes.
;
; It is bank 0 by construction: the cold stub in the fixed tail is the only
; code that can know a bank number before anything else has run.
;
; The two rows it owns are the name row and the hint row, and it owns them
; because THE NAME CANNOT BE RECOMPOSED ANYWHERE ELSE. It lives in an appkey,
; and the only moment the console can see it is while the appkey's reply is in
; the window -- which is here, on the cold path, and nowhere else. Every other
; bank clears a RANGE of rows rather than all of them, and leaves these two.

        CPU     6502
        INCLUDE "vcs.inc"

PAD3    EQU     $81             ; the display kernel's 3-cycle pad target
SAVSP   EQU     $82

        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"
        INCLUDE "../build/tail.inc"

        ORG     $1000

START:  lda     LBENT
        cmp     #ENCOLD
        beq     COLD
        jmp     WARM

; ---------------------------------------------------------------------------
; COLD -- power-on, RESET, and the way back from a name change.
;
; Reached with LBENT already zero: the cold stub forces it, because THIS
; CONSOLE DOES NOT CLEAR ITS RAM ON A RESET and the entry code would otherwise
; still hold whatever the last screen set. A reset taken during a boot would
; come back into the boot bank's warm path and poll a progress bar for a
; transfer that is not running.
COLD:   sei
        cld
        ldx     #$FF
        txs
        lda     #0
CLRLP:  sta     $00,x           ; $00-$7F is the TIA, $80-$FF is RAM
        dex
        bne     CLRLP
        sta     $00

        lda     #2
        sta     VBLANK

; The gate, again. The cold stub already armed it, but a RESET comes back
; through here and arming twice is free where arming never is not.
        jsr     FNARM
        jsr     FNCHK
        beq     CHAVE

; No cartridge answered. Say so in the one way that needs no text at all,
; because composing text is exactly what is not working.
        lda     #CRED
        sta     COLUBK
        lda     #0
        sta     VBLANK
CHALT:  jmp     CHALT

CHAVE:  jsr     FNCLS

; THE PATH BUFFERS SURVIVE A CONSOLE RESET TOO -- there is no reset line on
; this connector -- so a cold start empties all four rather than trusting
; them, and leaves buffer 0 selected, which is where every bank expects to
; start. FP_SEL0..FP_SEL3 are contiguous by construction.
        ldx     #FP_SEL3
CPB1:   txa
        sta     FNRSEL+FH_PATHO
        lda     #FP_RST
        sta     FNRSEL+FH_PATHO
        dex
        cpx     #FP_SEL0
        bcs     CPB1

        jsr     LHINT
        jsr     NAMERD
        beq     CGO
; No usable name in the appkey. Every game in the family reads this same slot,
; so it can perfectly well hold something that is not a name at all.
        lda     #ENNAME
        sta     LBENT
        lda     #BANKNAM
        jmp     LBGOTO

CGO:    lda     #0
        sta     LBPAGE
        sta     LBPAGES
        sta     LBSTG
CFETCH: lda     #ENFETCH
        sta     LBENT
        lda     #BANKFET
        jmp     LBGOTO

; ---------------------------------------------------------------------------
; WARM -- the list is on the planes; run it.
WARM:   lda     #2
        sta     VBLANK
        lda     LBENT
        cmp     #ENSHOWN
        beq     WRUN            ; nothing changed: leave the cursor alone
        jsr     LSEL0
WRUN:   lda     #ENSHOWN
        sta     LBENT
        lda     #0
        sta     LBINP           ; a press aimed at the screen we have LEFT is
        sta     LBKEY           ;   not a press aimed at this one
        sta     VBLANK
        jsr     DINIT
        jmp     DLOOP

; ---------------------------------------------------------------------------
; APPVBL -- drain the input latch and act on it.
;
; DFRAME has already scanned and OR'd; this is the only bank besides the
; keyboard that empties it. The value is copied into a cell of its own before
; anything is dispatched, because every handler below the first test is
; reached through calls that borrow the scratch.
APPVBL: lda     LBINP
        sta     LBKEY
        lda     #0
        sta     LBINP
        lda     LBKEY
        beq     AV9

        and     #IN_DOWN
        beq     AV1
        jmp     LDOWN
AV1:    lda     LBKEY
        and     #IN_UP
        beq     AV2
        jmp     LUP
AV2:    lda     LBKEY
        and     #IN_FIRE
        beq     AV3
        jmp     LFIRE
AV3:    lda     LBKEY
        and     #IN_SEL
        beq     AV4
        jmp     LNAME
AV4:    lda     LBKEY
        and     #IN_RST
        beq     AV5
        jmp     LFRESH
AV5:    lda     LBKEY
        and     #IN_RIGHT
        beq     AV6
        jmp     LNEXTP
AV6:    lda     LBKEY
        and     #IN_LEFT
        beq     AV9
        jmp     LPREVP
AV9:    rts

; ---------------------------------------------------------------------------
; The cursor.
;
; THERE IS NO LIST IN MEMORY TO MOVE THROUGH. LBCLS is the only record of what
; each row is, and it is enough: a room row is the one painted CLROOM, so
; moving the selection is a scan of the colour table for the next one. The
; room's INDEX comes along beside it, because that is what a boot has to ask
; the server for and nothing else knows it.
;
; Four zero-page stores, no blit, no transaction and not one byte of any row's
; text. The sibling ports spend a whole mechanism here -- with no inverse video
; and no way to read the planes back as characters, a list marks its selection
; with a '>' in column 0, and moving it means poking two cells through the
; blit port and waiting on FN_B_BLITGEN between them.

; LSEL0 -- put the cursor on the first room row.
LSEL0:  lda     #0
        sta     LBIDXS
        sta     LBSTG           ; a new page: whatever was staged is not it
        ldx     #RLIST0
LS01:   cpx     #RLISTN+1
        bcs     LS09            ; no rooms at all: no cursor
        lda     LBCLS,x
        cmp     #CLROOM
        beq     LS02
        inx
        bne     LS01            ; always
LS02:   stx     LBSEL
        lda     #CLSEL
        sta     LBCLS,x
LS09:   rts

LDOWN:  lda     LBCNT
        beq     LD9
        ldx     LBSEL
LD1:    inx
        cpx     #RLISTN+1
        bcs     LD9             ; off the bottom: stay where we are
        lda     LBCLS,x
        cmp     #CLROOM
        bne     LD1
        inc     LBIDXS
        jmp     LMOVE
LD9:    rts

LUP:    lda     LBCNT
        beq     LU9
        ldx     LBSEL
LU1:    cpx     #RLIST0
        beq     LU9             ; off the top
        dex
        lda     LBCLS,x
        cmp     #CLROOM
        bne     LU1
        dec     LBIDXS
        jmp     LMOVE
LU9:    rts

; LMOVE -- select row X, deselect whatever was selected.
LMOVE:  ldy     LBSEL
        lda     #CLROOM
        sta     LBCLS,y
        stx     LBSEL
        lda     #CLSEL
        sta     LBCLS,x
        lda     #0
        sta     LBSTG           ; the staged room is no longer the one under
        rts                     ;   the cursor

; ---------------------------------------------------------------------------
; The actions.
; FIRE -- join the room under the cursor.
;
; Straight to the prep bank, which re-fetches the one record it needs. The
; list was rendered two records at a time and the selected one was repainted
; out of the reply window several reads ago, so there is nothing here to hand
; over -- only LBPAGE and LBIDXS, which say where to ask for it again.
LFIRE:  lda     LBCNT
        beq     LF9             ; an empty page has nothing to boot
        lda     #ENPREP
        sta     LBENT
        lda     #BANKPRP
        jmp     LBGOTO
LF9:    rts

LNAME:  lda     #ENNAME
        sta     LBENT
        lda     #BANKNAM
        jmp     LBGOTO

; RESET is a SWITCH on this console. It restarts nothing, so what it means is
; the client's to choose, and here it is what every sibling lobby makes it:
; fetch the list again from the top. The count goes with it, because the
; reason to refresh is that the list may have changed.
LFRESH: lda     #0
        sta     LBPAGE
        sta     LBPAGES
        jmp     CFETCH

LNEXTP: lda     LBFULL
        beq     LN9             ; the server did not fill the ask: this is the
        inc     LBPAGE          ;   last page
        jmp     CFETCH
LN9:    rts

LPREVP: lda     LBPAGE
        beq     LP9
        dec     LBPAGE
        jmp     CFETCH
LP9:    rts

; ---------------------------------------------------------------------------
; LHINT -- the hint row. Twelve columns, and this is what they are for.
LHINT:  ldx     #(SHINT)&$FF
        ldy     #(SHINT)>>8
        jsr     FNSETP
        lda     #RHINT
        jsr     FNSTRA
        ldx     #RHINT
        lda     #CLCHROM
        sta     LBCLS,x
        rts

; ---------------------------------------------------------------------------
; The username, out of the appkey every FujiNet client in the family shares.
;
; Creator 1, app 1, key 0 -- the same slot the Intellivision, the ColecoVision
; and the desktop clients all read, which is the point of it: a player types a
; name once and every game knows it. That is also why it has to be VALIDATED
; rather than trusted. Anything at all may be in there.
;
; The reply is a 2-byte little-endian length and then the bytes: an appkey read
; carries its own length, unlike a network read.

; NAMERD -- read, validate and draw. A = 0 if there is a usable name.
; LBSTEP says WHICH of the four ways this can fail actually happened, because
; from the outside they are one symptom -- the keyboard comes up -- and three
; of them are not the user's fault.
NAMERD: lda     #1
        sta     LBSTEP
        lda     #AKKEY
        ldx     #AKMRD
        jsr     AKOPEN
        bne     NRBAD
        lda     #2
        sta     LBSTEP
        jsr     AKREAD
        bne     NRBAD
        lda     #3
        sta     LBSTEP
        lda     FNRPLY+1
        bne     NRBAD           ; a length over 255 is not a name
        lda     FNRPLY+0
        sta     LBERR           ; the length, for anyone asking why
        cmp     #NAMEMIN
        bcc     NRBAD
        cmp     #NAMEMAX+1
        bcs     NRBAD
        sta     LBNLEN
        lda     #4
        sta     LBSTEP
        ldx     #0
NRV1:   lda     FNRPLY+2,x
        jsr     NRUPR
        cmp     #'0'
        bcc     NRBAD
        cmp     #'9'+1
        bcc     NRV2
        cmp     #'A'
        bcc     NRBAD
        cmp     #'Z'+1
        bcs     NRBAD
NRV2:   inx
        cpx     LBNLEN
        bne     NRV1
        lda     #0
        sta     LBSTEP
        jsr     NAMEROW         ; while the reply is still in the window
        jsr     AKCLOSE
        lda     #0
        rts
NRBAD:  jsr     AKCLOSE
        lda     #$FF
        rts

; NRUPR -- fold a lowercase letter to upper. The slot is shared, and a client
; that wrote "thom" is not wrong, it is just not this screen's alphabet.
NRUPR:  cmp     #'a'
        bcc     NRU9
        cmp     #'z'+1
        bcs     NRU9
        sec
        sbc     #32
NRU9:   rts

; NAMEROW -- "SEL=" and the name, straight out of the reply window.
;
; Four characters of label and eight of name is exactly twelve, which is the
; whole reason the name sits ON the key that changes it rather than on a row
; of its own: a legend and a value do not both fit on this screen, so they are
; the same thing.
NAMEROW: lda    #RNAME
        jsr     FNROWA
        ldx     #(SSEL)&$FF
        ldy     #(SSEL)>>8
        jsr     FNSETP
        jsr     FNSTRC
        ldx     #0
NM1:    lda     FNRPLY+2,x
        jsr     NRUPR
        sta     FNRSEL+FH_TCHR
        inx
        cpx     LBNLEN
        bne     NM1
        jsr     FNENDR
        ldx     #RNAME
        lda     #CLCHROM
        sta     LBCLS,x
        rts

; ---------------------------------------------------------------------------
; AKOPEN -- open appkey (AKCREAT, AKAPP) key A, mode X.
;
; THE PAYLOAD IS SIX BYTES AND THE SIXTH IS RESERVED. Sending five leaves the
; firmware's transaction_get() blocked waiting for a byte that never arrives,
; which reads back as a timeout rather than as a protocol error -- so the
; symptom points at the network and not at this.
AKOPEN: sta     LBIDX
        stx     LBTMP
        lda     #FNDEVF
        sta     FNDEV
        lda     #FCAKOPN
        sta     FNCMD
        lda     #0
        sta     FNNPR
        jsr     FNBEG
        lda     #AKCREAT
        sta     FNTX
        lda     #0
        sta     FNTX            ; creator, high
        lda     #AKAPP
        sta     FNTX
        lda     LBIDX
        sta     FNTX
        lda     LBTMP
        sta     FNTX
        lda     #0
        sta     FNTX            ; the reserved byte -- see above
        jmp     AKGO

AKREAD: lda     #FNDEVF
        sta     FNDEV
        lda     #FCAKRD
        sta     FNCMD
        lda     #0
        sta     FNNPR
        jsr     FNBEG
        jmp     AKGO

AKCLOSE: lda    #FNDEVF
        sta     FNDEV
        lda     #FCAKCLS
        sta     FNCMD
        lda     #0
        sta     FNNPR
        jsr     FNBEG
        jsr     AKGO
        lda     #0              ; a close that failed is not worth a screen
        rts

; AKGO -- launch and check. The tail's FNGO, not net.inc's display-paced twin:
; this bank has no transport in it and the cold start has no picture to keep.
AKGO:   jsr     FNGO
        cmp     #FNEOK
        bne     AKG9
        jsr     FNACK
AKG9:   rts

; ---------------------------------------------------------------------------
        INCLUDE "lblib.inc"
        INCLUDE "lbdisp.inc"

SSEL:   DB      "SEL=",0
SHINT:  DB      "RST=REFRESH",0

        END
