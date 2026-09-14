; lblib.inc -- the helpers each bank carries its own copy of.
;
; CODE, so this is included INSIDE the ORG. The equates are in fujinet.inc and
; lbdefs.inc and come before it.
;
; A bank switch replaces every byte of $1000-$17FF and the high 2K is the
; mailbox in its entirety, so there is no fixed code region big enough to
; share a library from -- only the 220-byte tail, and the transport already
; fills it. Every bank therefore carries what it calls, which is why the
; bigger pieces are guarded: at 2048 bytes a bank, what a bank never calls is
; worth leaving out. Define the guard BEFORE the include; an IF whose
; condition is not yet resolvable in AS's first pass quietly assembles the
; branch it should not.

; ---------------------------------------------------------------------------
; FNCLS -- blank every text row, and set every row's colour to the border.
;
; THE TEXT PLANES ARE CARTRIDGE STATE AND SURVIVE A BANK SWITCH, so a screen
; that simply does not paint a row inherits whatever the previous screen left
; in it. So does LBCLS, which is zero page and crosses a switch the same way:
; a bank that painted rows but not colours would show the last screen's bands
; under its own text. Both are cleared here, together, so the two can never
; get out of step -- and every DRAW starts with a call to this rather than
; each bank tracking which rows it owns.
FNCLS:  lda     #CBORDER
        jsr     LBCLSF
        lda     #0
        ldx     #FNTROW-1
        ; fall through

; FNCLSR -- blank rows A through X inclusive, and colour them the border.
;
; A range and not just "all", because the name row and the hint row belong to
; the bank that can compose them and no other. The name lives in a write-only
; cartridge buffer, so the only bank that can put it on screen is the one
; holding it in the reply window -- the one that has just read the appkey.
; Every other bank has to leave those two rows alone rather than clear them
; and be unable to put them back.
; The row counter lives in memory and not in A, because FNENDR ENDS WITH A
; ZERO IN A -- it loads the attribute byte to store it. Carrying the row in A
; across the call reset it to zero every iteration and the loop never
; terminated: a cold start that cleared row 0, then row 1, then row 0 again,
; for ever, behind a screen still blanked. It is the family's "a scratch cell
; is not safe across a call" rule with a register in place of the cell.
FNCLSR: stx     LBTMP           ; the last row to clear
        sta     LBIDX           ; ...and the one being cleared
FNCLS1: ldx     LBIDX
        lda     #CBORDER
        sta     LBCLS,x
        lda     LBIDX
        jsr     FNROWA
        jsr     FNENDR
        lda     LBIDX
        cmp     LBTMP
        beq     FNCLS2
        inc     LBIDX
        bne     FNCLS1          ; always: FNTROW rows, never 256
FNCLS2: rts

; ---------------------------------------------------------------------------
; LBCLSF -- fill the whole row-colour table with A.
;
; All twenty-two entries, including the one for row 21, which does not exist:
; the seam line at the bottom of row 20 programmes it, and that is how the
; picture hands back to the bottom band.
LBCLSF: ldx     #LBCLSN-1
LBCLF1: sta     LBCLS,x
        dex
        bpl     LBCLF1
        rts

; ---------------------------------------------------------------------------
; FNSETP -- point FNPTRL/H at the string whose address is in X (low) and
; Y (high). Every caller that streams a literal goes through here.
FNSETP: stx     FNPTRL
        sty     FNPTRH
        rts

; FNSTRA -- render the NUL-terminated string at FNPTRL/H into text row A.
;
; The cartridge's cursor saturates at column 12, so a string longer than the
; screen simply loses its tail rather than running into the next row.
FNSTRA: jsr     FNROWA
FNSTR1: ldy     #0
FNSTR2: lda     (FNPTRL),y      ; an indirect LOAD is legal; an indirect STORE
        beq     FNSTR3          ;   is not, anywhere -- see lbcore.inc
        sta     FNRSEL+FH_TCHR
        iny
        cpy     #FNTCOL
        bne     FNSTR2
FNSTR3: jmp     FNENDR

; FNSTRC -- the same, but only composes: no FNROWA, no FNENDR. For a row that
; is a literal followed by something else.
FNSTRC: ldy     #0
FNSTC1: lda     (FNPTRL),y
        beq     FNSTC2
        sta     FNRSEL+FH_TCHR
        iny
        cpy     #FNTCOL
        bne     FNSTC1
FNSTC2: rts

; ---------------------------------------------------------------------------
; FNSPCS -- append A spaces to the row being composed.
;
; Zero means none. Without the test, `tax / dex / bne` would take the count
; from 0 to $FF and write 256 spaces into a row that saturates at twelve --
; harmless on the planes, and a hundred wasted cycles in the middle of a
; vblank that is measured in them.
FNSPCS: tax
        beq     FNSPC9
FNSPC1: lda     #' '
        sta     FNRSEL+FH_TCHR
        dex
        bne     FNSPC1
FNSPC9: rts

; ---------------------------------------------------------------------------
; LBDEC2 -- append A as one or two decimal digits, no leading zero, no
; padding. Clamped at 99.
;
; NOT the sibling ports' 16-bit repeated-subtraction printer: the only numbers
; this client prints are a player count, a table size and a page number, and
; all three are bytes. A pot is a u16 and a room's occupancy is not.
LBDEC2: cmp     #100
        bcc     LBD2A
        lda     #99
LBD2A:  ldx     #0
LBD2B:  cmp     #10
        bcc     LBD2C
        sbc     #10             ; carry is set here, so this subtracts 10
        inx
        bne     LBD2B
LBD2C:  sta     LBDGT           ; the units, while the tens go out
        txa
        beq     LBD2D           ; no tens digit: do not print a leading zero
        clc
        adc     #'0'
        sta     FNRSEL+FH_TCHR
LBD2D:  lda     LBDGT
        clc
        adc     #'0'
        sta     FNRSEL+FH_TCHR
        rts

; ---------------------------------------------------------------------------
; The cartridge's four 256-byte path buffers.
;
; They are where every string too big for console RAM lives: two 65-byte URLs,
; a host name and whatever the keyboard is typing. THE CONSOLE CANNOT READ ONE
; BACK -- the page they are written through is write-only -- so a buffer is
; somewhere to PUT a string and stream out again, never somewhere to parse
; one. Anything that needs deciding must be decided on the way in, while the
; bytes are still in the reply window.
;
; They also survive a console reset, which is why a cold start empties all
; four rather than trusting them.

; FNWSEL -- subsequent buffer ops act on buffer A (an FP_SEL* value).
FNWSEL: sta     FNRSEL+FH_PATHO
        rts

; FNWRST -- empty the selected buffer.
FNWRST: lda     #FP_RST
        sta     FNRSEL+FH_PATHO
        rts

; The emitters, only in the banks that send. At 2048 bytes a bank, what a
; bank never calls is worth leaving out -- define LBHASTX before the include.
        IFDEF   LBHASTX

; FNWCH -- append A to the selected buffer.
FNWCH:  sta     FNRSEL+FH_PATHC
        rts

; FNWTX -- emit the selected buffer into TX, NUL-padded to exactly 256.
FNWTX:  lda     #FP_TX
        sta     FNRSEL+FH_PATHO
        rts

; FNWRAW -- emit exactly the bytes it holds, and let the caller do the padding.
FNWRAW: lda     #FP_TXRAW
        sta     FNRSEL+FH_PATHO
        rts

        ENDIF                   ; LBHASTX

; FNWFLD -- stream a fixed-width wire field out of the record at FNPTRL/H into
; the selected buffer. A = the field's offset, X = its width.
;
; Stops at the NUL and never goes through it: the server NUL-pads every field
; to its declared width, and padding in the middle of a URL corrupts the
; request. Cartridge to cartridge -- the bytes never land in console RAM.
FNWFLD: sta     LBIDX
        stx     LBTMP
FNWF1:  ldy     LBIDX
        lda     (FNPTRL),y
        beq     FNWF2
        sta     FNRSEL+FH_PATHC
        inc     LBIDX
        dec     LBTMP
        bne     FNWF1
FNWF2:  rts

; ---------------------------------------------------------------------------
; Building a 256-byte payload a piece at a time.
;
; WRITE_HOST_SLOTS and SET_DEVICE_FULLPATH both read EXACTLY 256 bytes and a
; short payload fails the server's read, so whatever a payload is assembled
; from it has to end up exactly that long. The count is a single byte because
; it wraps to zero at exactly 256, which is the length being aimed at.
;
; Nothing is buffered: on a console with 128 bytes of RAM a 256-byte payload
; is assembled AS IT IS SENT, out of the reply window and the cartridge's own
; buffers, and never exists anywhere at once.
        IFDEF   LBHASPL

FNPBEG: lda     #0
        sta     FNPCNT
        rts

; FNPCH -- append A. Preserves X and Y, which the callers count on: one walks
; the reply window in X and a field width in Y at the same time.
FNPCH:  sta     FNTX
        inc     FNPCNT
        rts

; FNPEND -- pad out to exactly 256 bytes.
FNPEND: lda     FNPCNT
        beq     FNPE9           ; already wrapped: it is exactly 256
FNPE1:  lda     #0
        sta     FNTX
        inc     FNPCNT
        bne     FNPE1
FNPE9:  rts

        ENDIF                   ; LBHASPL

; ---------------------------------------------------------------------------
; The boot swap, assembled only into the bank that boots.
;
; About a hundred bytes -- FNBLK, FNSWAP and the stub FNSWAP copies into
; console RAM -- and every bank carries its own copy of this file, so leaving
; it in the five banks that never boot would cost five hundred bytes on a
; machine with 2K per bank.
        IFDEF   LBLSWAP

; FNBLK -- arm the ROM swap (FN_REG_BOOTLOCK).
FNBLK:  lda     #FNBLKM
        ldx     #FR_BLCK
        jmp     FNRW

; FNSWAP -- boot the staged image. Does not return.
;
; The swap replaces every byte of the 4K window INCLUDING THE CODE THAT
; TRIGGERED IT, so the trigger has to run from somewhere else -- and on this
; console the only RAM is $80-$FF, which is also the stack. The stub lives at
; $80; there is no JSR inside it and the 6507 has no interrupts, so nothing
; can touch the stack while it runs.
;
; This is also where LBCLS's life ends. The table sits at $8F-$A4, inside the
; ground the stub lands on -- which is safe precisely because nothing draws
; another frame after this point.
;
; Three of the stub's stores are easy to leave out and each breaks a different
; thing: AUDV0/AUDV1, or a tone screams until the booted game's cold start
; runs; and SWACNT/SWBCNT back to inputs, because almost no game writes them
; and a client that left the RIOT ports as outputs would brick every game
; booted after it.
FNSWAP: ldx     #FNSTE-FNSTB-1
FNSW1:  lda     FNSTB,x
        sta     $80,x
        dex
        bpl     FNSW1
        jmp     $0080

FNSTB:  lda     #0
        sta     GRP0            ; silence the sprites
        sta     GRP1
        sta     AUDV0           ; *** and the sound, or it screams ***
        sta     AUDV1
        sta     PF0
        sta     PF1
        sta     PF2
        sta     WSYNC           ; land on a line boundary
        sta     SWACNT          ; *** RIOT port A back to inputs ***
        sta     SWBCNT          ; *** and port B ***
        lda     #2
        sta     VBLANK          ; blank across the swap
        sta     VSYNC           ; a clean discontinuity, not a rolling frame
        sta     FNRSEL+FH_SWAP  ; THE SWAP. The next fetch is at $00xx, in RAM
                                ;   with A12 low, so the window may flip
                                ;   between this store and it.
        ldx     #$FF
        txs                     ; a clean stack for the new image
        jmp     ($1FFC)         ; the NEW image's own reset vector, exactly
                                ;   what the 6507 fetches at power-on
FNSTE:

; The stub lands at $80 and INCUR is at $A8. Two bytes added to the stub and
; it would eat the input state on the way past, silently, in the one code path
; nobody watches because it never returns.
        IF      FNSTE-FNSTB>INCUR-$80
        ERROR   "the swap stub has grown into INCUR"
        ENDIF

        ENDIF                   ; LBLSWAP

; ---------------------------------------------------------------------------
; FNHEX -- append A as two hex digits to the row being composed.
;
; Error codes are shown in hex and not decimal because that is how they are
; written down: FNENAK is $EE in fujinet.inc and in every sibling port's
; notes, and 238 is a number nobody can look up.
FNHEX:  pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     FNHEX1
        pla
        and     #$0F
FNHEX1: cmp     #10
        bcc     FNHEX2
        adc     #6              ; carry is set here, so this adds 7 in all
FNHEX2: adc     #'0'
        sta     FNRSEL+FH_TCHR
        rts

; ---------------------------------------------------------------------------
; Input. Joystick 0 in SWCHA bits 7-4 and the console switches in SWCHB, all
; active low, folded into one active-high byte.
;
; INSCAN returns the NEWLY PRESSED bits, so a held stick steps once; INREPT
; layers auto-repeat on top of it, for the DIRECTIONS ONLY. FIRE, SELECT and
; RESET never repeat: a repeating FIRE would boot a room and then boot
; whatever the cursor landed on next.
INSCAN: lda     SWCHA
        eor     #$FF            ; the port is active low
        and     #$F0            ; right, left, down, up in bits 7-4
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     INCUR
        lda     INPT4
        bmi     INSC1           ; bit 7 high = fire not pressed
        lda     INCUR
        ora     #IN_FIRE
        sta     INCUR
INSC1:  lda     SWCHB
        and     #$01
        bne     INSC2
        lda     INCUR
        ora     #IN_RST
        sta     INCUR
INSC2:  lda     SWCHB
        and     #$02
        bne     INSC3
        lda     INCUR
        ora     #IN_SEL
        sta     INCUR
INSC3:  lda     INPREV          ; newly pressed = current AND NOT previous
        eor     #$FF
        and     INCUR
        pha
        lda     INCUR
        sta     INPREV
        pla
        rts

INREPT: jsr     INSCAN
        beq     INRP1           ; nothing newly pressed: a repeat may be due
        pha                     ; something was: restart the delay
        lda     #INDLAY
        sta     INRPT
        pla
        rts

INRP1:  lda     INCUR
        and     #INDIRS
        beq     INRP2           ; no direction held: disarm
        lda     INRPT
        beq     INRPF           ; already expired -- fire now
        dec     INRPT
        bne     INRP3
INRPF:  lda     #INRATE
        sta     INRPT
        lda     INCUR
        and     #INDIRS
        rts

INRP2:  lda     #INDLAY
        sta     INRPT
INRP3:  lda     #0
        rts
