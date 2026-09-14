; lbfetch.asm -- bank 1: the page and the page count.
;
; THIS BANK COMPOSES THE WHOLE LIST, and bank 0 composes none of it. That is
; not a division of labour, it is forced: a page is up to 1935 bytes against a
; 512-byte reply window, so records arrive two at a time and each pair is
; repainted by the next READ. A record can only be rendered while it is in the
; window, so the renderer has to be in the bank that reads -- and once it is,
; leaving bank 0 with nothing to compose turns a cursor move into four
; zero-page stores.
;
; It also carries no APPVBL worth the name. Every frame it draws is drawn from
; inside a transaction, and acting on input there would re-enter the settle
; loop through itself. DFRAME still SCANS the input and ORs it into LBINP --
; that is the whole point of scanning in DFRAME rather than in the hook -- so
; a press made while a page is loading is still there when bank 0 comes back.

        CPU     6502
        INCLUDE "vcs.inc"

PAD3    EQU     $81             ; the display kernel's 3-cycle pad target
SAVSP   EQU     $82

; The title literal's width, needed by FETITLE to right-flush the page
; counter. Up here with the equates rather than beside the string it measures:
; AS resolves a forward-referenced symbol in an expression on its second pass,
; and a first-pass guess of zero is a phase error rather than a build failure.
STITLEL EQU     5

        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"
        INCLUDE "../build/tail.inc"

        ORG     $1000

START:  jsr     FETCH
; The page count is one extra round trip whose body is never read, so it is
; only ever taken when it is not already known: a cold start or a refresh
; clears LBPAGES, a page turn does not.
        lda     LBPAGES
        bne     STDONE
        jsr     COUNT
        jsr     FETITLE         ; the title was drawn before the count landed
STDONE: lda     #ENLIST
        sta     LBENT
        lda     #BANKLST
        jmp     LBGOTO

; ---------------------------------------------------------------------------
; APPVBL -- nothing. See the file header: this bank must not act on input.
APPVBL: rts

; ---------------------------------------------------------------------------
; FETCH -- one page of the list, rendered as it arrives.
FETCH:  lda     #RTITLE         ; the name and hint rows belong to bank 0 and
        ldx     #RLISTN         ;   are left alone: their text cannot be
        jsr     FNCLSR          ;   recomposed from here
        ldx     #RTITLE
        lda     #CLCHROM
        sta     LBCLS,x
        ldx     #(SLOAD)&$FF
        ldy     #(SLOAD)>>8
        jsr     FNSETP
        lda     #RTITLE
        jsr     FNSTRA

        lda     #0
        sta     LBCNT
        sta     LBGOT
        sta     LBFULL
        lda     #RLIST0
        sta     LBROWS

        lda     #RQPAGE
        sta     LBREQ
        jsr     NCLOSE          ; the PREVIOUS request's connection
        jsr     NOPEN
        beq     FE0
        jmp     FEFAIL
; The three-byte header is read by itself, so it never displaces the records
; the way it would if it shared a read with them.
FE0:    lda     #LBHDRL
        ldx     #0
        jsr     NCHUNK
        beq     FE1
        jmp     FEFAIL
FE1:    lda     FNRPLY+LBHCNT
        beq     FEEMPTY
        cmp     #LBPGSZ
        bcc     FE2
        lda     #LBPGSZ         ; never render more than a page, whatever the
        sta     LBCNT           ;   server felt like sending
        lda     #1
        sta     LBFULL          ; it filled the ask, so there may be another
        jmp     FELOOP
FE2:    sta     LBCNT

; ---- the chunk loop ----
FELOOP: lda     LBCNT
        sec
        sbc     LBGOT
        beq     FEDONE
        cmp     #SVPERRD
        bcc     FE3
        lda     #SVPERRD
FE3:    sta     LBCHUNK
        cmp     #2
        beq     FE4
        lda     #(SVSTRID)&$FF
        ldx     #(SVSTRID)>>8
; JMP, not a branch. `ldx #0` SETS Z, so a `bne` here -- taken on the theory
; that 215 has a nonzero low byte -- reads the flags of the wrong instruction
; and falls straight through into the two-record case. The last chunk of a
; page is one record, and it then waited for 430 bytes that were never coming:
; nine rooms fetched, eight drawn, and an error line under them.
        jmp     FE5
FE4:    lda     #(2*SVSTRID)&$FF
        ldx     #(2*SVSTRID)>>8
FE5:    jsr     NCHUNK
        beq     FE6
        jmp     FEFAIL

; How much of the ask actually landed? A short read is not an error -- it is
; how the page ends when the server had fewer rooms than it said -- but a
; PARTIAL record is not renderable, so only whole ones count.
FE6:    jsr     FERECS
        cmp     LBCHUNK
        bcs     FE7
        sta     LBCHUNK
        beq     FEDONE
FE7:    lda     #0
        sta     LBCHI
FEREC:  lda     LBCHI
        jsr     LBRPTR
        jsr     FEROW
        inc     LBGOT
        inc     LBCHI
        lda     LBCHI
        cmp     LBCHUNK
        bne     FEREC
        jmp     FELOOP

FEDONE: lda     LBGOT
        sta     LBCNT           ; what actually drew is what the cursor may
        beq     FEEMPTY         ;   move through
        jmp     FETITLE

FEEMPTY: lda    #0
        sta     LBCNT
        ldx     #(SNONE)&$FF
        ldy     #(SNONE)>>8
        jsr     FNSETP
        lda     #RLIST0
        jsr     FNSTRA
        jmp     FETITLE

; A failure leaves whatever rendered on screen and says where it stopped. The
; error code is the server's or the cartridge's, never this client's opinion
; of it.
FEFAIL: lda     #0
        sta     LBCNT
        lda     #RTITLE         ; the TITLE row, not a list row and above all
        jsr     FNROWA          ;   not the name row: bank 0 owns that one and
                                ;   nothing here could put it back
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
        jmp     FNENDR          ; and NOT on to FETITLE, which would paint the
                                ;   page counter straight over this

; ---------------------------------------------------------------------------
; FEROW -- render the record at FNPTRL/H: a game header if the game changed,
; then its room row.
;
; The new hash goes on the STACK rather than into a zero-page cell, because
; everything between computing it and storing it calls LBFLD, and LBFLD
; borrows LBIDX and LBTMP to walk a field.
FEROW:  jsr     LBGHASH         ; A = the low half, LBTMP the high
        ldx     #1              ; assume the game changed
        ldy     LBGOT
        beq     FEH1            ; the first record of a page always gets one,
                                ;   and LBGOT being zero is what says so --
                                ;   no separate "have we seen one yet" flag
        cmp     LBGS0
        bne     FEH1
        ldy     LBTMP
        cpy     LBGS1
        bne     FEH1
        ldx     #0
FEH1:   pha                     ; the new hash, low
        lda     LBTMP
        pha                     ; ...and high
        txa
        pha                     ; ...and whether a header is wanted

        pla
        beq     FEROOM
        lda     LBROWS
        jsr     FNROWA
        lda     #SVGAME
        ldx     #FNTCOL
        jsr     LBFLD
        jsr     FNENDR
        ldx     LBROWS
        lda     #CLHDR
        sta     LBCLS,x
        inc     LBROWS

FEROOM: lda     LBROWS
        jsr     FNROWA
        lda     #SVROOM
        ldx     #RMNAMEW
        jsr     LBFLD
        jsr     FECNT
        jsr     FNENDR
        ldx     LBROWS
        lda     #CLROOM
        sta     LBCLS,x
        inc     LBROWS

        pla
        sta     LBGS1
        pla
        sta     LBGS0
        rts

; ---------------------------------------------------------------------------
; FECNT -- "cur/max", right-flushed into the last RMCNTW columns.
FECNT:  ldy     #SVCUR
        lda     (FNPTRL),y
        jsr     FCLAMP
        sta     LBIDX
        ldy     #SVMAX
        lda     (FNPTRL),y
        jsr     FCLAMP
        sta     LBTMP
        lda     LBIDX
        jsr     FCDIG
        pha
        lda     LBTMP
        jsr     FCDIG
        sta     LBDGT
        pla
        clc
        adc     LBDGT
        adc     #1              ; the '/'; carry is clear, both are 1 or 2
        sta     LBDGT
        lda     #RMCNTW
        sec
        sbc     LBDGT
        jsr     FNSPCS
        lda     LBIDX
        jsr     LBDEC2
        lda     #'/'
        sta     FNRSEL+FH_TCHR
        lda     LBTMP
        jmp     LBDEC2

; A count wider than two digits cannot be shown, so it is clamped rather than
; wrapped: a room that says 99 is wrong by less than one that says 4.
FCLAMP: cmp     #100
        bcc     FCL1
        lda     #99
FCL1:   rts

FCDIG:  cmp     #10
        bcc     FCD1
        lda     #2
        rts
FCD1:   lda     #1
        rts

; ---------------------------------------------------------------------------
; FETITLE -- "LOBBY" and which page of how many, right-flushed.
FETITLE: lda    #RTITLE
        jsr     FNROWA
        ldx     #(STITLE)&$FF
        ldy     #(STITLE)>>8
        jsr     FNSETP
        jsr     FNSTRC

        lda     LBPAGE
        clc
        adc     #1
        sta     LBIDX           ; the page number as a person counts them
        jsr     FCDIG
        sta     LBTMP
        lda     LBPAGES
        beq     FT1             ; not counted yet: one character, a '?'
        jsr     FCDIG
        jmp     FT2
FT1:    lda     #1
FT2:    clc
        adc     LBTMP
        adc     #1              ; the '/'
        sta     LBTMP
        lda     #FNTCOL-STITLEL
        sec
        sbc     LBTMP
        jsr     FNSPCS
        lda     LBIDX
        jsr     LBDEC2
        lda     #'/'
        sta     FNRSEL+FH_TCHR
        lda     LBPAGES
        beq     FT3
        jsr     LBDEC2
        jmp     FNENDR
FT3:    lda     #'?'
        sta     FNRSEL+FH_TCHR
        jmp     FNENDR

; ---------------------------------------------------------------------------
; COUNT -- how many pages there are, in one round trip whose body is never
; read.
;
; The Intellivision re-walks the ENTIRE list to answer this, because its pages
; are bounded by ROWS: a page that deferred a widowed header does not start
; where arithmetic says it does, so the only way to count them is to replay
; the row fitting over every record. This client's pages are bounded by
; RECORDS -- nine of them, always -- so the answer is ceil(total / 9), and the
; total is the first byte of a reply. Ask for everything, read three bytes,
; and never fetch the other eighteen hundred.
COUNT:  lda     #RQCOUNT
        sta     LBREQ
        jsr     NCLOSE
        jsr     NOPEN
        bne     COBAD
        lda     #LBHDRL
        ldx     #0
        jsr     NCHUNK
        bne     COBAD
        lda     FNRPLY+LBHCNT
        ldx     #0
CO1:    cmp     #LBPGSZ
        bcc     CO2
        sbc     #LBPGSZ         ; carry is set by the compare
        inx
        bne     CO1
CO2:    cmp     #0
        beq     CO3
        inx                     ; a part-page is still a page
CO3:    stx     LBPAGES
        rts
COBAD:  lda     #0
        sta     LBPAGES         ; unknown, and the title says '?'
        rts

; ---------------------------------------------------------------------------
        INCLUDE "lblib.inc"
        INCLUDE "state.inc"
        INCLUDE "net.inc"
        INCLUDE "url.inc"
        INCLUDE "lbdisp.inc"

STITLE: DB      "LOBBY",0
SLOAD:  DB      "LOADING",0
SNONE:  DB      "NO SERVERS",0
SERR:   DB      "ERR ",0

        END
