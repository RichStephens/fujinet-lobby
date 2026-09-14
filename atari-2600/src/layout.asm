; layout.asm -- the screen with no network at all.
;
; A flat 4K image: the kernel, the row colours, the geometry and a hand-written
; page of rooms that never came from anywhere. It is what emu/shot.lua
; snapshots and emu/dispcheck.py byte-compares, and what emu/colours.lua taps
; COLUBK against -- all of which can then be believed, because nothing in here
; can fail for a reason that is really the server's.
;
; It also runs the real cursor. Moving the selection is four zero-page stores
; and no round trip at all, which is the whole point of putting the colour
; table in RAM, so it is worth being able to see it move before there is a
; list to move it through.
;
; The tail is the REAL tail (lbtailbody.inc), not a stub, so the addresses in
; build/tail.inc are true for this image too. The sibling port's layout ROM
; once included only the generated equates and every jsr into the shared
; transport landed on p2bin's filler.

        CPU     6502
        INCLUDE "vcs.inc"

PAD3    EQU     $81             ; the display kernel's 3-cycle pad target
SAVSP   EQU     $82

        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"

        ORG     $1000

START:  sei
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

; The gate. Banking and the text ports decode nothing until this ordered pair
; of stores arrives, and a 7800's BIOS probing cartridge space cannot produce
; it -- which is the point of it.
        jsr     FNARM
        jsr     FNCHK
        beq     LHAVE

; No cartridge answered. Say so in the one way that needs no text at all,
; because composing text is exactly what is not working.
        lda     #CRED
        sta     COLUBK
        lda     #0
        sta     VBLANK
LHALT:  jmp     LHALT

LHAVE:  jsr     LDRAW
        jsr     LSEL0

        lda     #0
        sta     VBLANK
        jsr     DINIT
        jmp     DLOOP

; ---------------------------------------------------------------------------
; APPVBL -- the per-frame hook, called from DFRAME inside the timed vblank.
;
; DFRAME has already scanned the input and OR'd it into LBINP; this drains it.
APPVBL: lda     LBINP
        ldx     #0
        stx     LBINP
        sta     LBTMP

        and     #IN_DOWN
        beq     AV1
        jmp     LDOWN
AV1:    lda     LBTMP
        and     #IN_UP
        beq     AV2
        jmp     LUP
AV2:    rts

; ---------------------------------------------------------------------------
; The cursor.
;
; THERE IS NO LIST IN MEMORY TO MOVE THROUGH. LBCLS is the only record of what
; each row is, and it is enough: a room row is the one painted CLROOM, so
; moving the selection is a scan of twenty-two zero-page bytes for the next
; one. That is the same code the real list bank runs, which is why it is worth
; having here -- nothing about the cursor depends on where the rows came from.

; LSEL0 -- put the cursor on the first room row.
LSEL0:  ldx     #RLIST0
LS01:   lda     LBCLS,x
        cmp     #CLROOM
        beq     LS02
        inx
        cpx     #RLISTN+1
        bcc     LS01
        rts                     ; no rooms: no cursor, and nothing to select
LS02:   stx     LBSEL
        lda     #CLSEL
        sta     LBCLS,x
        rts

; LDOWN / LUP -- to the next or previous room row, or nowhere.
LDOWN:  ldx     LBSEL
LDN1:   inx
        cpx     #RLISTN+1
        bcs     LDN9            ; off the bottom: stay where we are
        lda     LBCLS,x
        cmp     #CLROOM
        bne     LDN1
        jmp     LMOVE
LDN9:   rts

LUP:    ldx     LBSEL
LUP1:   cpx     #RLIST0
        beq     LUP9            ; off the top
        dex
        lda     LBCLS,x
        cmp     #CLROOM
        bne     LUP1
        jmp     LMOVE
LUP9:   rts

; LMOVE -- select row X, deselect whatever was selected. Four stores, no blit,
; no transaction, and not one byte of any row's text.
;
; The sibling ports spend a whole mechanism here: with no inverse video and no
; way to read the planes back as characters, a list marks its selection with a
; '>' in column 0, and moving it means poking two cells through the blit port
; and waiting on FN_B_BLITGEN between them. Colouring the row instead costs
; this, and gives column 0 back to the text.
LMOVE:  ldy     LBSEL
        lda     #CLROOM
        sta     LBCLS,y
        stx     LBSEL
        lda     #CLSEL
        sta     LBCLS,x
        rts

; ---------------------------------------------------------------------------
; LDRAW -- paint the fake page.
;
; Four bytes an entry: the row, its colour, and the address of its text. The
; table ends with $FF, which is not a row.
LDRAW:  jsr     FNCLS
        ldx     #0
LD1:    lda     LROWS,x
        cmp     #$FF
        beq     LD9
        sta     LBTMP           ; the row
        inx
        lda     LROWS,x         ; ...and its colour, straight into the table
        ldy     LBTMP           ;   the seam line reads
        sta     LBCLS,y
        inx
        lda     LROWS,x
        sta     FNPTRL
        inx
        lda     LROWS,x
        sta     FNPTRH
        inx
        stx     LBIDX           ; FNSTRA does not touch X today; this is so
        lda     LBTMP           ;   that staying true is not a condition of
        jsr     FNSTRA          ;   this loop being correct
        ldx     LBIDX
        jmp     LD1
LD9:    rts

; ---------------------------------------------------------------------------
        INCLUDE "lblib.inc"
        INCLUDE "lbdisp.inc"

; ---------------------------------------------------------------------------
; The page. Two games and six rooms, with the room names long enough to be
; truncated, because a layout that only ever shows short names is not the
; layout that ships.
LROWS:  DB      RTITLE,CLCHROM
        DW      STITLE
        DB      1,CLHDR
        DW      SGAME1
        DB      2,CLROOM
        DW      SROOM1
        DB      3,CLROOM
        DW      SROOM2
        DB      4,CLROOM
        DW      SROOM3
        DB      5,CLHDR
        DW      SGAME2
        DB      6,CLROOM
        DW      SROOM4
        DB      7,CLROOM
        DW      SROOM5
        DB      8,CLHDR
        DW      SGAME3
        DB      9,CLROOM
        DW      SROOM6
        DB      RNAME,CLCHROM
        DW      SNAME
        DB      RHINT,CLCHROM
        DW      SHINT
        DB      $FF

; Twelve columns, and the title has to carry the page counter too. "LOBBY"
; then four spaces then "1/2" is exactly twelve.
STITLE: DB      "LOBBY    1/2",0
SGAME1: DB      "5 CARD STUD",0
SROOM1: DB      "NORMAL  2/8",0
SROOM2: DB      "HIGHROL 0/8",0
SROOM3: DB      "BOTS    8/8",0
SGAME2: DB      "BATTLESHIP",0
SROOM4: DB      "OPEN    1/2",0
SROOM5: DB      "PRIVATE 2/2",0
SGAME3: DB      "FUJITZEE",0
SROOM6: DB      "TABLE 1 3/4",0

; The name sits ON the key that changes it, which is the only way a legend
; fits in twelve columns at all: "SEL=" plus an eight-character name is
; exactly the width of the screen.
SNAME:  DB      "SEL=THOMC",0
SHINT:  DB      "RST=REFRESH",0

; ---------------------------------------------------------------------------
; The fixed half, and the real one: the trampoline, the shared transport and
; the cold stub, at the addresses every bank will reach them at.
        INCLUDE "lbtailbody.inc"

        END
