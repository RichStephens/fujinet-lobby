; lbdisp.inc -- the 48-pixel text display, with a colour per row.
;
; The cartridge composes the glyphs (firmware/src/vcs_render.c) and publishes
; them as six 128-byte planes at $1800-$1AFF; this is the console half.
;
; THE 53-CYCLE INK BODY BELOW IS TRANSCRIBED FROM
; fujinet-firmware/pico/atari-2600/testrom/fujidisp.inc AND MUST NOT BE
; RETIMED. Its four constants are the coordinates of a ONE-PIXEL-WIDE window
; found by byte-comparing the raster against the renderer with
; emu/dispcheck.py -- every wrong setting still looks like text.
;
; WHAT IS ADDED HERE: a background colour per row, for nothing.
;
; vcs_render_row() writes ZERO to scanline 5 of every cell -- the sixth line
; of a 4x6 cell is blank leading and the renderer does not store it. So the
; loop is 21 rows of (5 cycle-exact ink lines + 1 SEAM LINE), the seam line is
; a line on which no glyph can possibly be drawn, and it is free for whatever
; the kernel wants to do instead. That costs no scanlines at all: the blank
; line was already there, and the picture is still 21*6 = 126 lines.
;
; "Free" means free of DEADLINES, not free of cycles: the seam line still has
; to finish inside its 76, or it quietly costs a second scanline. The budget
; is spelled out where it is spent.
;
; WHERE THIS DIFFERS FROM THE SIBLING PORTS. 5 Card Stud, Battleship and
; Fujitzee all colour the seam line, but from a table in ROM, because a seat's
; colour is a function of the LAYOUT. A lobby row's colour is a function of
; what the server sent -- a game header appears wherever the game name changes
; -- so the table has to be written at render time and therefore has to be in
; RAM. It is LBCLS, twenty-two bytes of zero page, and it holds the COLUBK
; value itself rather than an index into a palette.
;
; Holding the colour rather than a class is what makes the seam line cheap:
; one zero-page,X load and one store, 23 cycles in, where a class plus a
; palette lookup would have been 32 and right on the border's edge. Zero-page,X
; is also four cycles FLAT, one less than the ROM form's worst case -- an
; absolute,X load pays a fifth cycle whenever its table straddles a page, and
; cdisp.inc's own budget note has to reserve that cycle.
;
; THE INK IS ONE COLOUR FOR THE WHOLE SCREEN, set in DINIT and never touched
; again. 5 Card Stud varies it per row because a seat carries its status in
; its ink; every class here is a background at luminance 0 or 4 under white,
; so nothing is gained by spending the cycles.

; ---------------- kernel timing constants ----------------
; Not taste. See the file header.
RNOP    EQU     16              ; NOPs before RESP0 (2 cycles each)...
R3      EQU     1               ; ...plus this, so RESP0 lands on cycle 38
HM0     EQU     15              ; HMP0 = $F0: move P0 right one pixel...
HM1     EQU     0               ; ...and leave P1, closing the gap to eight
VDEL    EQU     1               ; vertical delay on both players

; ---------------- text plane bases ----------------
TP0     EQU     FNTEXT+$000
TP1     EQU     FNTEXT+$080
TP2     EQU     FNTEXT+$100
TP3     EQU     FNTEXT+$180
TP4     EQU     FNTEXT+$200
TP5     EQU     FNTEXT+$280

TINK    EQU     FNTCLH-1        ; 5 ink lines, then the seam
TLINES  EQU     FNTROW*FNTCLH   ; 126 scanlines of text

; The seam line indexes LBCLS with zero-page,X, which is four cycles and wraps
; inside page zero. The table's last entry must therefore still be in it --
; an assembly-time failure rather than a comment, because the wrap is silent.
        IF      LBCLS+LBCLSN-1>$FF
        ERROR   "LBCLS runs off the end of zero page"
        ENDIF

; NTSC: 3 vsync + 37 vblank + 192 visible + 30 overscan = 262.
VBLINES EQU     37
OSLINES EQU     30
PADLINE EQU     (192-TLINES)/2  ; 33 above and below

; THE BLANKED BANDS ARE TIMED, NOT COUNTED, and that is not a refinement --
; counting them is what made the picture jump in every port that tried it.
;
; Burning VBLINES scanlines on WSYNC and THEN calling APPVBL adds whatever the
; hook did to the frame instead of spending it inside. 5 Card Stud measured
; 265 scanlines rather than 262 just from scanning the input, and 413 on the
; frame a recompose ran. Every one of those is a different vertical position.
;
; So the two blanked bands set the RIOT's 64-cycle timer, do their work, and
; wait out whatever is left. The hook costs the frame nothing at all, as long
; as it fits -- and what it has to fit in is 37 scanlines, 2812 cycles.
;
; The counts are in 64-cycle units and one less than the arithmetic suggests,
; because the timer has to expire INSIDE the last line rather than on its
; boundary. Taken from the sibling ports, where they were histogrammed rather
; than derived.
VBTIM   EQU     43              ; ~37 scanlines of vblank
OSTIM   EQU     35              ; ~30 scanlines of overscan

; ---------------- DINIT: TIA setup and player positioning ----------------
DINIT:
; Two players, three copies each, eight pixels apart: P0 draws groups 0,2,4
; and P1 groups 1,3,5, interleaving to 48 contiguous pixels. VDELP is what
; makes the six-write sequence land in the right copies.
        lda     #$03            ; NUSIZ: three copies, close
        sta     NUSIZ0
        sta     NUSIZ1
        lda     #VDEL
        sta     VDELP0
        sta     VDELP1
        lda     #CWHITE
        sta     COLUP0
        sta     COLUP1
        lda     #CBORDER
        sta     COLUBK
        sta     COLUPF

; The side border, and the seam line's deadline with it -- see PFEDGE0 in
; lbdefs.inc. PF0's high nibble is pixels 0-15; with CTRLPF's reflect bit the
; right half mirrors, putting the same sixteen at 144-159. The 48-pixel text
; block sits at pixels 46-94 and never comes near either.
        lda     #$01            ; CTRLPF: reflect, so one nibble draws both
        sta     CTRLPF          ;   edges
        lda     #PFEDGE0
        sta     PF0
        lda     #PFEDGE1
        sta     PF1
        lda     #0
        sta     PF2
        sta     LBFRAME

; Player positioning, transcribed from batari Basic's std_kernel.asm rather
; than re-derived. RESP0 strobed at cycle 43, RESP1 three cycles later (nine
; pixels, since two stores cannot be closer), then HMP0/HMP1 pull them to
; eight apart. The delay is built from NOPs plus an optional 3-cycle zero-page
; store, because the copies are 2.67 cycles apart and NOPs alone only reach
; even delays.
        sta     WSYNC
        REPT    RNOP
        nop
        ENDM
        IF      R3
        sta     PAD3            ; 3 cycles, so odd delays are reachable
        ENDIF
        sta     RESP0
        sta     RESP1
        lda     #HM0*16
        sta     HMP0
        lda     #(HM1*16)&$FF
        sta     HMP1
; An EARLY HMOVE -- WSYNC, then strobe -- rather than batari's late one at
; cycle 73. A late HMOVE does not apply the motion nibbles cleanly: nudging
; HMP0 by one there widened the player gap from 8 pixels to 9 instead of
; sliding the block, and the window this kernel needs is one pixel wide.
        sta     WSYNC
        sta     HMOVE
        rts

; ---------------- DLOOP: draw frames, forever ----------------
DLOOP:  jsr     DFRAME
        jmp     DLOOP

; ---------------- DFRAME: draw ONE frame, then return ----------------
; Split out of DLOOP so a bank that is not running the display loop can still
; keep the picture alive: net.inc waits for the cartridge a frame at a time
; through here, which is what stops a poll from blanking the screen.
;
; A JSR into this is safe despite the kernel parking a graphics byte in S. The
; return address is pushed BEFORE that happens and nothing pushes again until
; SAVSP has been restored -- the same rule the kernel lives by, one level out.
DFRAME:
        lda     #2
        sta     VSYNC
        sta     WSYNC
        sta     WSYNC
        sta     WSYNC
        lda     #0
        sta     VSYNC

        lda     #2
        sta     VBLANK
        lda     #VBTIM
        sta     TIM64T
        inc     LBFRAME

; INPUT IS SCANNED HERE, IN EVERY BANK, AND OR'D INTO A LATCH.
;
; Not in the hook, and this is the single worst bug the family has had. The
; fetch bank is mapped for as long as a round trip takes -- tens of frames --
; and while it is mapped nothing updates what the edge detector compares
; against. A press made in that window is simply not there when the list bank
; next looks for it, and the first thing that moves the cursor is the
; auto-repeat half a second later. Resyncing on the way back makes it worse:
; a press begun during a fetch is then guaranteed to be swallowed.
;
; So every bank scans, every frame, through the same DFRAME, and whichever
; hook cares drains LBINP.
        jsr     INREPT
        ora     LBINP
        sta     LBINP

; The client's per-frame hook, called while the screen is still blanked and
; the raster is nowhere near the text. It runs ON the clock the store above
; started, so the frame does not grow by what it does -- within the 2812
; cycles VBTIM allows.
        jsr     APPVBL

; Wait out the rest of the band, then land the unblank on a LINE BOUNDARY.
; Both halves matter. The timer is what makes the band a fixed length whatever
; APPVBL did; the WSYNC is what keeps VBLANK from being cleared mid-scanline,
; which brings the first visible line up in two colours and puts a visible
; notch in the top left corner.
;
; TIMINT, not INTIM. Past zero the timer does not stop: it free-runs at a tick
; a cycle, and a seven-cycle `lda INTIM / bne` walks over the single cycle it
; reads zero on again and again. TIMINT's bit 7 LATCHES on the underflow and
; stays latched, so an overrun costs exactly the overrun.
DVBLP:  bit     TIMINT
        bpl     DVBLP
        sta     WSYNC
        lda     #0
        sta     VBLANK

; The top band is border colour, and its LAST line hands over to row 0: the
; store lands a couple of cycles into hblank, so that line is already row 0's
; colour and no scanline is spent on the transition.
        ldx     #PADLINE-1
DPADA:  sta     WSYNC
        dex
        bne     DPADA
        sta     WSYNC
        lda     LBCLS           ; row 0's background; the seam line does the
        sta     COLUBK          ;   other twenty-one

; ---------------- the kernel ----------------
; The stack pointer is a spare register in the ink body, and that is not a
; flourish: the six player copies are 2.67 cycles apart while a zero-page
; store is 3, so the four late writes drift a full cycle across the block.
; Recovering a byte from zero page costs 3 cycles; `tsx` costs 2, and that one
; cycle is the difference between a schedule that closes and one that does
; not. It is also why the seventh write is `sty GRP0`: its value is a
; don't-care, so Y serves and no register need be spared.
;
; NOTHING between the txs here and the restore below may touch the stack --
; no JSR -- which is why the row loop and the seam line are inline. The 6507
; has no interrupts, so there is nothing else to worry about.
        tsx
        stx     SAVSP
        ldy     #0              ; the absolute scanline, 0-125; never clobbered
        lda     #0
        sta     LBROW

DROWL:  lda     #TINK
        sta     LBLINE

DINK:   sta     WSYNC
        lda     TP0,y           ; 4
        sta     GRP0            ; 3   ->  7   new GRP0 = group 0
        lda     TP1,y           ; 4   -> 11
        sta     GRP1            ; 3   -> 14   displays group 0
        lda     TP2,y           ; 4   -> 18
        sta     GRP0            ; 3   -> 21   displays group 1
        lda     TP4,y           ; 4   -> 25
        tax                     ; 2   -> 27
        txs                     ; 2   -> 29   park group 4 in S
        lda     TP3,y           ; 4   -> 33
        tax                     ; 2   -> 35
        lda     TP5,y           ; 4   -> 39
        stx     GRP1            ; 3   -> 42   displays group 2
        tsx                     ; 2   -> 44   recover group 4
        stx     GRP0            ; 3   -> 47   displays group 3
        sta     GRP1            ; 3   -> 50   displays group 4
        sty     GRP0            ; 3   -> 53   displays group 5; value unused
        iny                     ; 2   -> 55
        dec     LBLINE          ; 5   -> 60
        bne     DINK            ; 3   -> 63

; ---- the seam line ----
; Line 5 of the cell. The cartridge stores zero here, so no glyph can be drawn
; and the kernel does something useful instead.
;
; IT HAS TO FIT IN ONE LINE. This is a WSYNC-bounded loop, so a seam that runs
; past cycle 76 does not glitch -- it silently costs a SECOND scanline,
; because the next `sta WSYNC` is then already on the following line and waits
; for the end of THAT one. 5 Card Stud shipped that once: every seat row was
; seven scanlines instead of six, 278 lines to a frame, a picture that rolls
; on anything that cares, and nothing about it looked wrong on screen.
;
; The budget is from this WSYNC to the last cycle of the next one, and it is
; 76. This reaches it at 41, which is thirty-five spare -- the room the ROM
; table and the palette indirection would have spent. emu/frames.lua proves
; the frame is 262 lines rather than anyone counting this by eye.
        sta     WSYNC
        lda     #0              ; 2
        sta     GRP0            ; 3   ->  5   three writes, not two: with
        sta     GRP1            ; 3   ->  8     VDELP set a write to GRP0
        sta     GRP0            ; 3   -> 11     reloads the DELAYED GRP1
        ldx     LBROW           ; 3   -> 14
        inx                     ; 2   -> 16   the row this colour is FOR
        lda     LBCLS,x         ; 4   -> 20   zero-page,X: four cycles, always
        sta     COLUBK          ; 3   -> 23   pixel 1 or so, deep under the
                                ;   border, which draws over the background
                                ;   out to pixel 31 and is the whole reason
                                ;   this store has room to be here
        stx     LBROW           ; 3   -> 26   advanced here rather than with a
                                ;   read-modify-write at the bottom: X still
                                ;   holds it, and `inc` costs five cycles
        iny                     ; 2   -> 28   step past the blank plane byte
        cpx     #FNTROW         ; 2   -> 30   row 21 is the handover entry:
        bne     DROWL           ; 3   -> 33     programme it, then stop
                                ;   + DROWL's 5 and the WSYNC's 3 = 41

        ldx     SAVSP
        txs

; The last seam line already blanked the sprites and set the background back
; to the border colour -- LBCLS's twenty-second entry exists for exactly that
; -- so the bottom band needs nothing but scanlines.
        ldx     #PADLINE
DPADB:  sta     WSYNC
        dex
        bne     DPADB

        lda     #2
        sta     VBLANK
        lda     #OSTIM
        sta     TIM64T
DOSLP:  bit     TIMINT
        bpl     DOSLP
        sta     WSYNC
; Returns with VBLANK SET, which is what makes DFRAME safe to call from a bank
; that is going to do a few hundred cycles of work before the next one: the
; gap is blanked rather than showing the raster free-running.
        rts
