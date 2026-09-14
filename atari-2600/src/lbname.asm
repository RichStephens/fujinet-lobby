; lbname.asm -- bank 2: the on-screen keyboard.
;
; One thing gets typed on this console: the player's name, 2 to 8 characters
; of A-Z and 0-9. It is short enough to fit in console RAM and it lives in the
; CARTRIDGE anyway, in path buffer 3 -- because the appkey write streams it
; straight out of there with FP_TXRAW, and because that is the only way the
; same code works when the thing being typed is longer than the machine.
;
; That is also why the value row is painted with FN_BLIT_PATH rather than
; composed here: the page the characters are written through is WRITE-ONLY, so
; the only way to see what has been typed is to ask the cartridge to render it.
;
; THE CURSOR POSITION IS THE CHARACTER. Thirty-six cells in three rows of
; twelve is A-Z then 0-9 exactly, which is the one shape that comes out even
; in this many columns -- the Intellivision uses six rows of sixteen for the
; same trick, and sixteen columns do not exist here.
;
; NO SPACE KEY AND NO CONTROL ROW. A lobby name is A-Z0-9 only, so a space
; would be a key that cannot be pressed legally; and with SELECT and RESET
; free on this screen, DELETE and DONE are buttons rather than cells. That
; buys back the fourth row and, with it, the double spacing that makes 4x6
; cells readable.
;
; The sibling ports mark the cursor with brackets on a row of their own,
; because there is no inverse video and no way to read the planes back as
; characters. This one has a colour per row, so the grid ROW the cursor is on
; is simply a different colour, and only the COLUMN needs saying -- which the
; PICK row does, in the same breath as the length.

        CPU     6502
        INCLUDE "vcs.inc"

PAD3    EQU     $81             ; the display kernel's 3-cycle pad target
SAVSP   EQU     $82

LBHASTX EQU     1               ; this bank emits a path buffer into TX

        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"
        INCLUDE "../build/tail.inc"

KROWT   EQU     0               ; "ENTER NAME"
KROWN   EQU     2               ; what has been typed, blitted from the buffer
KROWP   EQU     4               ; "PICK <A> 3/8"
KROW0   EQU     6               ; the grid: rows 6, 8 and 10
KROWSP  EQU     2               ; ...double spaced, which the colour bands
                                ;   want as much as the reader does
KROWD   EQU     19
KROWH   EQU     20

KGRIDW  EQU     FNTCOL          ; 12 -- the grid is exactly the screen width
KGRIDH  EQU     3
KCELLS  EQU     KGRIDW*KGRIDH

        IF      KCELLS<>36
        ERROR   "the grid is not A-Z plus 0-9"
        ENDIF

        ORG     $1000

START:  lda     #2
        sta     VBLANK

        lda     #0
        sta     LBKCOL
        sta     LBKROW
        sta     LBNLEN

; Start empty rather than seeded with the current name. A name is at most
; eight characters and the grid is three keystrokes from anywhere, so editing
; would cost more to explain than retyping costs to do -- and CANCEL is then
; simply never writing the appkey, which is what makes it safe.
        lda     #PBEDIT
        jsr     FNWSEL
        jsr     FNWRST

        jsr     KDRAW

        lda     #0
        sta     LBINP           ; the press that GOT here is not a press aimed
        sta     LBKEY           ;   at this screen
        sta     VBLANK
        jsr     DINIT
        jmp     DLOOP

; ---------------------------------------------------------------------------
APPVBL: lda     LBINP
        sta     LBKEY
        lda     #0
        sta     LBINP
        lda     LBKEY
        beq     AV9

        and     #IN_LEFT
        beq     AV1
        lda     LBKCOL
        beq     AV9
        dec     LBKCOL
        jmp     KPICK
AV1:    lda     LBKEY
        and     #IN_RIGHT
        beq     AV2
        lda     LBKCOL
        cmp     #KGRIDW-1
        bcs     AV9
        inc     LBKCOL
        jmp     KPICK
AV2:    lda     LBKEY
        and     #IN_UP
        beq     AV3
        lda     LBKROW
        beq     AV9
        dec     LBKROW
        jmp     KROWHI
AV3:    lda     LBKEY
        and     #IN_DOWN
        beq     AV4
        lda     LBKROW
        cmp     #KGRIDH-1
        bcs     AV9
        inc     LBKROW
        jmp     KROWHI
AV4:    lda     LBKEY
        and     #IN_FIRE
        beq     AV5
        jmp     KTYPE
AV5:    lda     LBKEY
        and     #IN_SEL
        beq     AV6
        jmp     KDELET
AV6:    lda     LBKEY
        and     #IN_RST
        beq     AV9
        jmp     KDONE
AV9:    rts

; ---------------------------------------------------------------------------
; KTYPE -- append the character under the cursor.
KTYPE:  lda     LBNLEN
        cmp     #NAMEMAX
        bcs     KT9             ; full: a ninth character would be dropped by
        jsr     KCHR            ;   the server anyway
        sta     FNRSEL+FH_PATHC
        inc     LBNLEN
        jmp     KVALUE
KT9:    rts

; KDELET -- drop the last character. FP_POPCH, not FP_POP: the latter drops a
; whole path component, which is right for ".." and useless for typing.
KDELET: lda     LBNLEN
        beq     KD9
        lda     #FP_POPCH
        sta     FNRSEL+FH_PATHO
        dec     LBNLEN
        jmp     KVALUE
KD9:    rts

; KDONE -- accept, if there is enough to accept.
;
; Two characters is the floor every client in the family enforces, so a name
; that would be rejected by the next game to read the slot is rejected here,
; where there is somebody to tell.
KDONE:  lda     LBNLEN
        cmp     #NAMEMIN
        bcc     KDN9
        jsr     AKWRITE
; Back to the list the long way round, through a cold entry: the name row can
; only be composed from an appkey REPLY, so the one bank that can draw it has
; to read it again. That the page is refetched with it is not waste -- the
; list is a live thing and this took a while.
        lda     #ENCOLD
        sta     LBENT
        lda     #BANKLST
        jmp     LBGOTO
KDN9:   rts

; ---------------------------------------------------------------------------
; KCHR -- A = the character under the cursor. The cell IS the character.
KCHR:   lda     LBKROW
        asl     a
        asl     a               ; row * 4
        sta     LBTMP
        asl     a               ; row * 8
        clc
        adc     LBTMP           ; row * 12
        clc
        adc     LBKCOL
        tax
        lda     KCHARS,x
        rts

; ---------------------------------------------------------------------------
; KDRAW -- the whole screen, once.
KDRAW:  jsr     FNCLS

        ldx     #(NSTITL)&$FF
        ldy     #(NSTITL)>>8
        jsr     FNSETP
        lda     #KROWT
        jsr     FNSTRA

        ldx     #(NSDEL)&$FF
        ldy     #(NSDEL)>>8
        jsr     FNSETP
        lda     #KROWD
        jsr     FNSTRA

        ldx     #(NSDONE)&$FF
        ldy     #(NSDONE)>>8
        jsr     FNSETP
        lda     #KROWH
        jsr     FNSTRA

; The three grid rows, which never change again: only their colour does.
        lda     #0
        sta     LBIDX
KD1:    lda     LBIDX
        jsr     KSROW           ; A = the screen row for grid row LBIDX
        jsr     FNROWA
        lda     LBIDX
        asl     a
        asl     a
        sta     LBTMP
        asl     a
        clc
        adc     LBTMP           ; grid row * 12
        tax
        ldy     #KGRIDW
KD2:    lda     KCHARS,x
        sta     FNRSEL+FH_TCHR
        inx
        dey
        bne     KD2
        jsr     FNENDR
        inc     LBIDX
        lda     LBIDX
        cmp     #KGRIDH
        bne     KD1

        jsr     KROWHI
        jmp     KVALUE

; KSROW -- A = the screen row of grid row A.
KSROW:  asl     a               ; KROWSP is 2, so this is the spacing
        clc
        adc     #KROW0
        rts

; ---------------------------------------------------------------------------
; KROWHI -- colour the grid row the cursor is on, and no other.
;
; This is the whole cursor, for a row: three stores. The sibling ports cannot
; do it at all -- vcs_render_row() takes no attribute, so a selected row
; cannot be highlighted -- and mark the column with brackets on a row of their
; own instead.
KROWHI: lda     #0
        sta     LBIDX
KH1:    lda     LBIDX
        jsr     KSROW
        tax                     ; X = the screen row this grid row lives on
        lda     LBIDX
        cmp     LBKROW
        beq     KH3
        lda     #CLROOM
        jmp     KH4
KH3:    lda     #CLSEL
KH4:    sta     LBCLS,x
        inc     LBIDX
        lda     LBIDX
        cmp     #KGRIDH
        bne     KH1
        jmp     KPICK

; ---------------------------------------------------------------------------
; KPICK -- "PICK <A> 3/8": which character the cursor is on, and how much room
; is left. Twelve columns exactly, which is why the two share a row.
KPICK:  lda     #KROWP
        jsr     FNROWA
        ldx     #(NSPICK)&$FF
        ldy     #(NSPICK)>>8
        jsr     FNSETP
        jsr     FNSTRC
        lda     #'<'
        sta     FNRSEL+FH_TCHR
        jsr     KCHR
        sta     FNRSEL+FH_TCHR
        lda     #'>'
        sta     FNRSEL+FH_TCHR
        lda     #' '
        sta     FNRSEL+FH_TCHR
        lda     LBNLEN
        jsr     LBDEC2
        lda     #'/'
        sta     FNRSEL+FH_TCHR
        lda     #NAMEMAX
        jsr     LBDEC2
        jsr     FNENDR
        ldx     #KROWP
        lda     #CLCHROM
        sta     LBCLS,x
        rts

; ---------------------------------------------------------------------------
; KVALUE -- show what has been typed.
;
; By asking the CARTRIDGE to render it. The buffer is on the other side of a
; write-only page, so this is not one way of several to see it, it is the only
; one.
KVALUE: lda     #PBEDIT
        jsr     FNWSEL
        lda     #0
        sta     FNRSEL+FH_BSL
        sta     FNRSEL+FH_BSH
        sta     FNRSEL+FH_BDH
        lda     #KROWN
        sta     FNRSEL+FH_BDL
        lda     #FNTCOL
        sta     FNRSEL+FH_BCNT
        lda     #FB_PATH
        sta     FNRSEL+FH_BGO
        ldx     #KROWN
        lda     #CLROOM         ; a field, so it reads as one
        sta     LBCLS,x
        jmp     KPICK

; ---------------------------------------------------------------------------
; AKWRITE -- store what was typed, so the next FujiNet game finds it.
;
; Best effort: the lobby works perfectly well without the slot being written,
; and a failure here would only strand the player on a keyboard they have
; already finished with.
;
; NPARAM = 1 CARRYING THE LENGTH, then the bytes raw. The ColecoVision sends
; no parameter at all and lets the payload length speak; both reach the same
; handler, but only this shape has been run on THIS transport, so it is not
; the place to economise.
AKWRITE: lda    #AKKEY
        ldx     #AKMWR
        jsr     AKOPEN
        bne     AKWX
        lda     #FNDEVF
        sta     FNDEV
        lda     #FCAKWR
        sta     FNCMD
        lda     #1
        sta     FNNPR
        jsr     FNBEG
        lda     LBNLEN
        jsr     FNPB
        lda     #PBEDIT
        jsr     FNWSEL
        jsr     FNWRAW
        jsr     FNGO
        jsr     AKCLOSE
AKWX:   rts

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
        jsr     FNGO
        cmp     #FNEOK
        bne     AKO9
        jsr     FNACK
AKO9:   rts

AKCLOSE: lda    #FNDEVF
        sta     FNDEV
        lda     #FCAKCLS
        sta     FNCMD
        lda     #0
        sta     FNNPR
        jsr     FNBEG
        jsr     FNGO
        lda     #0              ; a close that failed is not worth a screen
        rts

; ---------------------------------------------------------------------------
        INCLUDE "lblib.inc"
        INCLUDE "lbdisp.inc"

NSTITL: DB      "ENTER NAME",0
NSPICK: DB      "PICK ",0
NSDEL:  DB      "SEL=DEL",0
NSDONE: DB      "RST=DONE",0

; A-Z then 0-9: thirty-six cells in three rows of twelve, which is the one
; shape that comes out even in this many columns.
KCHARS: DB      "ABCDEFGHIJKL"
        DB      "MNOPQRSTUVWX"
        DB      "YZ0123456789"

        END
