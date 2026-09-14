; state.inc -- a server record, read IN PLACE in the cartridge's reply window.
;
; Nothing here copies a record anywhere. A record is 215 bytes and this
; console has 128, so every field is reached through FNPTRL/FNPTRH pointed at
; the record where it already lies, and the bytes go cartridge -> text plane
; to be drawn and cartridge -> TX page to be sent without ever crossing into
; console memory.
;
; An indirect LOAD is how that is done and an indirect STORE is banned
; outright: `sta (zp),y` performs a read at the address it is about to write,
; and on a page the cartridge does not drive that read is decoded as an access
; carrying the floating bus. tools/checkrom.py fails the build on one.

; ---------------------------------------------------------------------------
; LBRPTR -- point FNPTRL/FNPTRH at record A of the chunk in the window.
;
; A chunk is SVPERRD records read as one, so A is 0 or 1 and the offset is
; A * SVSTRID. The three-byte header is read by itself, before any chunk, so
; it never displaces the records the way it would if the whole page came in
; one read.
LBRPTR: cmp     #0
        beq     LBRP2
        lda     #(FNRPLY+SVSTRID)&$FF
        ldx     #(FNRPLY+SVSTRID)>>8
        jmp     LBRP3
LBRP2:  lda     #(FNRPLY)&$FF
        ldx     #(FNRPLY)>>8
LBRP3:  sta     FNPTRL
        stx     FNPTRH
        rts

; Both records must lie inside slice 0. Two at 215 bytes is 430 of 512, where
; three would not fit -- and reaching the second slice means writing FR_RXSL,
; which no client in this family has ever done and which the window was sized
; 512 rather than 256 specifically to avoid.
        IF      SVPERRD*SVSTRID>$200
        ERROR   "a chunk does not fit slice 0; SVPERRD is too big"
        ENDIF

; ---------------------------------------------------------------------------
; LBGHASH -- hash the record's game field into A (low) and LBTMP (high).
;
; THIS IS THE ONE PLACE THIS CLIENT IS INEXACT WHERE A SIBLING IS EXACT, and
; it is worth knowing why before anyone "fixes" it.
;
; A header row is drawn wherever the game name changes, so a record has to be
; compared against the one before it. coleco/st_list.c keeps
; `static char prevgame[17]` and compares the bytes. Neither half of that is
; available here. There are no seventeen spare bytes on a machine with 128 --
; and, decisively, THE PREVIOUS RECORD IS NO LONGER IN THE WINDOW: records
; arrive two at a time and every committed transaction repaints the window, so
; record k and record k-1 are in different chunks whenever k is even.
;
; So what crosses a chunk boundary is sixteen bits instead of seventeen bytes.
; A collision merges two ADJACENT games under one header -- one missing header
; row, and nothing else; the value is compared and never displayed. A page of
; nine risks eight comparisons.
;
; The hash is a circular 16-bit rotate-then-xor, which is cheap and mixes the
; high bytes back into the low ones -- a plain sum would collide on anagrams,
; and "5 CARD STUD" against "STUD CARD 5" is not a hypothetical shape for a
; list of game names.
LBGHASH: lda    #0
        sta     LBTMP           ; the high half
        ldy     #SVGAME
LBGH1:  asl     a               ; low << 1, bit 7 out into carry...
        rol     LBTMP           ; ...into the high half, whose bit 15 comes
        adc     #0              ;   back around into bit 0. A circular rotate
        eor     (FNPTRL),y      ;   of the pair, then the byte.
        iny
        cpy     #SVGAME+SVGAMEL
        bne     LBGH1
        rts

; ---------------------------------------------------------------------------
; LBFLD -- append a fixed-width wire field to the row being composed.
;   A = the field's offset in the record, X = how many columns to fill.
;
; The field is NUL-terminated inside its width and the remainder is spaces:
; the server pads with NULs and a NUL is not a space to the glyph renderer,
; which draws it as '?'. Pushing a field UP TO its NUL and never through it is
; the rule the Arcadia port calls out by name.
LBFLD:  sta     LBIDX           ; where in the record
        stx     LBTMP           ; how many columns are left
LBFL1:  ldy     LBIDX
        lda     (FNPTRL),y
        beq     LBFL2           ; the NUL: everything after it is padding
        sta     FNRSEL+FH_TCHR
        inc     LBIDX
        dec     LBTMP
        bne     LBFL1
        rts
LBFL2:  lda     LBTMP           ; pad the rest of the field with spaces
        jmp     FNSPCS

; ---------------------------------------------------------------------------
; FERECS -- A = whole records present in the reply just read, 0, 1 or 2.
;
; In state.inc rather than beside its caller because BOTH banks that read
; records ask it: the fetch bank to know how much of a chunk landed, and the
; prep bank to know whether the single record it asked for is really there. A
; short read is not an error -- it is how a page ends -- but a PARTIAL record
; is not renderable and not bootable either.
FERECS: lda     LBRXL1
        bne     FR2
        lda     LBRXL0
        cmp     #(SVSTRID)&$FF
        bcc     FR0
        lda     #1
        rts
FR0:    lda     #0
        rts
FR2:    lda     LBRXL1
        cmp     #(2*SVSTRID)>>8
        bcc     FR1
        bne     FR3
        lda     LBRXL0
        cmp     #(2*SVSTRID)&$FF
        bcc     FR1
FR3:    lda     #2
        rts
FR1:    lda     #1
        rts

