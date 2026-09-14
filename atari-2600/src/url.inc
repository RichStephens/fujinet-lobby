; url.inc -- the devicespec, streamed straight into the TX page a character at
; a time.
;
; Nothing is assembled in RAM. The cartridge counts the payload itself, so
; nothing here tracks a length -- which is the only reason a console with 128
; bytes can build
;
;   N:https://lobby.fujinet.online/view?bin=2&platform=a2600&pagesize=9&offset=18
;
; at all.
;
; THERE IS NO &appkey= HERE AND THERE MUST NOT BE, and it is worth knowing why
; before anyone adds one to filter the list by game. server/tx.go picks its
; ORDER BY on exactly that: with no appkey the query is
;
;   ORDER BY Game, Status DESC, Curplayers DESC, Server
;
; and with one it becomes ORDER BY Status, Lastping. This client draws a
; header row wherever the game name CHANGES, which is only a grouping while
; the rows arrive grouped -- so an appkey filter would not narrow the list, it
; would shred it into a header above almost every room.
;
; bin=2 rather than bin=1: the first 189 bytes of a bin=2 record are the bin=1
; record unchanged -- that format is frozen forever by the server's own
; comment -- and the 26 it adds carry the chat room's URL.
;
; No &be=1 either. The Go server's big-endian path is the road much less
; travelled, and the Intellivision port found corruption on it that always
; landed on exact multiples of 256.

; UTXS -- append the NUL-terminated string at FNPTRL/FNPTRH to the TX stream.
UTXS:   ldy     #0
UTXS1:  lda     (FNPTRL),y      ; an indirect LOAD is legal; an indirect STORE
        beq     UTXS2           ;   is not, anywhere
        sta     FNTX
        iny
        bne     UTXS1
UTXS2:  rts

; UPUT -- point at the string in X (lo) / Y (hi) and append it.
UPUT:   jsr     FNSETP
        jmp     UTXS

; UDEC -- append A as decimal, 0-255, no leading zeros.
;
; A byte is enough for every number this client sends. An offset is
; LBPAGE * LBPGSZ and the server's own pagesize cap is 255, so the largest
; offset that can ever be asked for is 252.
; Leading zeros are suppressed, but only ahead of the first digit printed:
; offset=105 must not come out as offset=15, so once the hundreds digit has
; gone out the tens digit goes out too, zero or not.
UDEC:   ldx     #0
UDEC1:  cmp     #100            ; sets carry when A >= 100, which is what makes
        bcc     UDEC2           ;   the SBC below subtract exactly 100
        sbc     #100
        inx
        bne     UDEC1
UDEC2:  stx     LBDGT           ; hundreds
        ldx     #0
UDEC3:  cmp     #10
        bcc     UDEC4
        sbc     #10
        inx
        bne     UDEC3
UDEC4:  sta     LBNUM           ; units, with X the tens
        lda     LBDGT
        beq     UDEC5
        ora     #'0'
        sta     FNTX
        txa                     ; hundreds went out, so the tens must too
        ora     #'0'
        sta     FNTX
        jmp     UDEC6
UDEC5:  txa
        beq     UDEC6           ; no hundreds and no tens: just the units
        ora     #'0'
        sta     FNTX
UDEC6:  lda     LBNUM
        ora     #'0'
        sta     FNTX
        rts

; ---------------------------------------------------------------------------
; BLDURL -- stream the devicespec for the request in LBREQ.
;
; All three shapes are the same URL with a different pagesize and offset, so
; there is one path through this and two small branches rather than three
; copies of a sixty-byte literal.
BLDURL: lda     #'N'
        sta     FNTX
        lda     #':'
        sta     FNTX
        ldx     #(UENDPT)&$FF
        ldy     #(UENDPT)>>8
        jsr     UPUT
        ldx     #(UVIEW)&$FF
        ldy     #(UVIEW)>>8
        jsr     UPUT
        ldx     #(UPLATF)&$FF
        ldy     #(UPLATF)>>8
        jsr     UPUT

        ldx     #(UPGSZ)&$FF
        ldy     #(UPGSZ)>>8
        jsr     UPUT

        lda     LBREQ
        cmp     #RQONE
        beq     BUONE
        cmp     #RQCOUNT
        beq     BUCNT

; A page: pagesize=LBPGSZ, offset = LBPAGE * LBPGSZ.
        lda     #LBPGSZ
        jsr     UDEC
        jsr     BUOFF
        lda     LBPAGE
        jsr     UMUL9
        jmp     UDEC

; One record, to stage it for a boot: pagesize=1, offset = the absolute index.
BUONE:  lda     #1
        jsr     UDEC
        jsr     BUOFF
        lda     LBPAGE
        jsr     UMUL9
        clc
        adc     LBIDXS
        jmp     UDEC

; The count: ask for everything and read only the three-byte header. The
; server's pagesize cap is 255, so this is "how many are there", and with a
; fixed page stride that is all a page counter needs -- where the
; Intellivision has to re-walk the entire list because its pages are bounded
; by rows rather than by records.
BUCNT:  lda     #255
        jsr     UDEC
        jsr     BUOFF
        lda     #0
        jmp     UDEC

BUOFF:  ldx     #(UOFF)&$FF
        ldy     #(UOFF)>>8
        jmp     UPUT

; UMUL9 -- A = A * LBPGSZ. Nine is (n<<3) + n, so no multiply and no table.
        IF      LBPGSZ<>9
        ERROR   "UMUL9 is LBPGSZ = 9; the shift-and-add is not general"
        ENDIF
UMUL9:  sta     LBTMP
        asl     a
        asl     a
        asl     a
        clc
        adc     LBTMP
        rts

        INCLUDE "../build/lobbyurl.inc"

UVIEW:  DB      "view?bin=2&platform=",0
UPGSZ:  DB      "&pagesize=",0
UOFF:   DB      "&offset=",0
