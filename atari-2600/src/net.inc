; net.inc -- the N: device round trip.
;
; A 6502 transcription of the sibling ports' sequence, which is the Arcadia's,
; which is the Astrocade's, which is the Odyssey 2's. The rules it carries
; forward were each learned somewhere else in this family and none of them is
; optional:
;
;  * The CLOSE belongs at the START of the next request, never after the READ.
;    Every transaction repaints the whole reply window, a CLOSE reply is
;    empty, and this client renders straight out of that window -- so closing
;    after the read wipes the thing being rendered.
;  * FNRXLO/FNRXHI belong to the MOST RECENT transaction, so the reply length
;    is captured immediately after the READ and not a transaction later.
;  * The ESP32 reports STATUS as soon as SOME of the response has arrived.
;    Poll until two consecutive readings agree AND the count has reached a
;    caller-supplied minimum. Two agreeing readings alone is not enough: the
;    Channel F port watched a fetch settle at 129 bytes of a 385-byte reply
;    and hand back a plausible header followed by forty bytes of nothing.
;  * The 4th STATUS byte is nDevStatus_t. The HTTP GET is DEFERRED until the
;    first STATUS call, so that byte is the only place an HTTP error is
;    visible -- and it matters more here than anywhere else in the family,
;    because THE LOBBY SERVER 404s AN EMPTY PAGE. Paging past the end returns
;    a JSON error document with a perfectly readable body and a perfectly
;    plausible length, whose first byte would parse as a record count.
;  * Unsigned compares go through the CARRY, never the sign bit. The Channel F
;    port's settle loop used the sign and 181 - 1 came out negative, so a
;    settled 181-byte reply read as short of a one-byte minimum and the poll
;    never terminated.
;
; WHAT IS NEW HERE: THE SETTLE FLOOR IS PER CHUNK, NOT PER REQUEST.
;
; A page is up to 1935 bytes against a 512-byte window, so it arrives two
; records at a time and each chunk is repainted by the next READ. The
; ColecoVision settles once after the OPEN and then reads a record at a time
; with no re-settle, treating any short read as the end of the page. That
; loses a record whenever the ESP32's buffer simply had not filled yet -- and
; worse, a short read of a two-record ask leaves the stream halfway through a
; record, so everything after it is garbage rather than merely missing.
; Settling to each chunk's own floor first is what makes a short read mean
; what the ColecoVision assumes it means.
;
; Every routine returns A = 0 on success and sets Z accordingly.

NPQUANT EQU     34              ; frames per FNTMO quantum, ~0.57s
NSTRIES EQU     20              ; settle polls before giving up
NSDELAY EQU     3               ; frames between them

; ---------------------------------------------------------------------------
; NCLOSE -- close the previous request's connection. The first call has
; nothing to close and earns a NAK; both results are ignored on purpose.
NCLOSE: lda     #NETDEV
        sta     FNDEV
        lda     #NCCLOSE
        sta     FNCMD
        lda     #0
        sta     FNNPR
        jsr     FNBEG
        jsr     NPGO
        lda     #0
        rts

; ---------------------------------------------------------------------------
; NOPEN -- OPEN the devicespec as an HTTP GET with no translation.
; BLDURL streams it straight into the TX page; nothing is assembled in RAM,
; because there is no RAM to assemble it in.
NOPEN:  lda     #NETDEV
        sta     FNDEV
        lda     #NCOPEN
        sta     FNCMD
        lda     #2
        sta     FNNPR
        jsr     FNBEG
        lda     #NMHTTPG
        jsr     FNPB
        lda     #NTRNONE
        jsr     FNPB
        jsr     BLDURL
        jsr     NPGO
        cmp     #FNEOK
        bne     NOBAD
        jsr     FNACK
        cmp     #FNEOK
        bne     NOBAD
        lda     #FNEOK
        rts
NOBAD:  sta     LBERR
        lda     #1
        sta     LBSTEP
        lda     #$FF
        rts

; ---------------------------------------------------------------------------
; NSTATUS -- one STATUS poll. On success LBAVL0/1 is the byte count waiting.
NSTATUS: lda    #NETDEV
        sta     FNDEV
        lda     #NCSTAT
        sta     FNCMD
        lda     #2
        sta     FNNPR
        jsr     FNBEG
        lda     #0
        jsr     FNPB
        lda     #0
        jsr     FNPB
        jsr     NPGO
        cmp     #FNEOK
        bne     NSBAD
        jsr     FNACK
        cmp     #FNEOK
        bne     NSBAD
        lda     FNRPLY+NSDEVST
        cmp     #1              ; SUCCESS -- anything else is an HTTP error,
        bne     NSBAD2          ;   and a 404's body would read as a page
        lda     FNRPLY+NSAVLO
        sta     LBAVL0
        lda     FNRPLY+NSAVHI
        sta     LBAVL1
        lda     #FNEOK
        rts
NSBAD2: lda     FNRPLY+NSDEVST  ; report what the server actually said
NSBAD:  sta     LBERR
        lda     #2
        sta     LBSTEP
        lda     #$FF
        rts

; ---------------------------------------------------------------------------
; NSETL -- poll STATUS until at least LBMIN0/1 bytes are waiting. A = 0 then.
;
; THE FLOOR ONLY, AND NOT "TWO CONSECUTIVE READINGS THAT AGREE" -- which is
; where this client departs from every sibling, so here is why.
;
; That rule exists because the sibling ports READ WHATEVER IS AVAILABLE:
; net.inc's NRCAP asks for min(avail, cap), so a reply that has only half
; arrived is read as a whole short reply, and the Channel F port watched a
; fetch settle at 129 bytes of 385 and hand back a plausible header followed
; by forty bytes of nothing. Waiting for the count to stop moving is what
; stops that.
;
; THIS CLIENT NEVER READS "WHATEVER IS AVAILABLE". Every read is for an exact
; byte count -- three for a header, 430 for a chunk, 215 for a record -- and
; the floor already proves that many are there. Waiting for the total to stop
; moving asks a question whose answer does not matter, and on a big reply it
; is actively harmful: the page COUNT asks for every room on the server, and
; polling STATUS repeatedly while the body is still arriving timed the mailbox
; out at 3013 bytes of 3228. One poll, one floor, one read.
NSETL:  lda     #NSTRIES
        sta     LBTRIES
NSET1:  jsr     NSTATUS
        beq     NSET2
        rts                     ; NSTATUS has already set LBERR/LBSTEP
NSET2:  lda     LBAVL1          ; avail >= LBMIN, unsigned, through the CARRY
        cmp     LBMIN1          ;   and never the sign bit: the Channel F
        bcc     NSETAG          ;   port's settle loop used the sign, 181 - 1
        bne     NSET3           ;   came out negative, and a settled reply
        lda     LBAVL0          ;   read as short of a one-byte minimum for
        cmp     LBMIN0          ;   ever
        bcc     NSETAG
NSET3:  lda     #FNEOK
        rts
NSETAG: lda     #NSDELAY
        sta     LBDLY           ; NOT in X or Y: NFRAME comes back with both
NSETDL: jsr     NFRAME          ;   gone, and Battleship's first caller counted
        dec     LBDLY           ;   its repeats in Y and ran every wait 256
        bne     NSETDL          ;   times over
        dec     LBTRIES
        bne     NSET1
        lda     #FNEWAIT
        sta     LBERR
        lda     #2
        sta     LBSTEP
        lda     #$FF
        rts

; ---------------------------------------------------------------------------
; NREAD -- READ exactly A (low) / X (high) bytes, then capture the length.
NREAD:  pha
        txa
        pha
        lda     #NETDEV
        sta     FNDEV
        lda     #NCREAD
        sta     FNCMD
        lda     #1
        sta     FNNPR
        jsr     FNBEG
        pla
        tax
        pla
        jsr     FNPW            ; ONE parameter of TWO bytes, not two of one
        jsr     NPGO
        cmp     #FNEOK
        bne     NRBAD
        jsr     FNACK
        cmp     #FNEOK
        bne     NRBAD
        lda     FNRXLO          ; capture NOW: the next transaction's reply
        sta     LBRXL0          ;   length would replace it, and it is always 0
        lda     FNRXHI
        sta     LBRXL1
        lda     #FNEOK
        rts
NRBAD:  sta     LBERR
        lda     #3
        sta     LBSTEP
        lda     #$FF
        rts

; ---------------------------------------------------------------------------
; NCHUNK -- settle for A (low) / X (high) bytes, then read exactly that many.
; The one call a chunked read needs, and the reason the floor is per chunk.
NCHUNK: sta     LBMIN0
        stx     LBMIN1
        jsr     NSETL
        beq     NCH1
        rts
NCH1:   lda     LBMIN0
        ldx     LBMIN1
        jmp     NREAD

; ---------------------------------------------------------------------------
; NPGO -- FNGO, paced by the display instead of by a spin loop.
;
; The fixed tail's FNGO waits on ACKSEQ in a three-deep counted loop with the
; screen dead. It cannot be changed there -- the tail is shared with the
; keyboard bank, which has no picture to keep during an appkey call -- so this
; is its twin, assembled into the banks that talk.
;
; The launch is identical and has to be: the next sequence number comes from
; the CART'S OWN persisted ACKSEQ + 1, never from a counter in RAM, because a
; console RESET restarts this client without resetting the cartridge and a
; program-local counter would collide with a sequence already answered.
;
; The timeout is the same ~9s in the same FNTMO quanta, so a real stall is
; still reported as the cartridge's error rather than ours. FNTMO itself is
; the inner counter -- FNBEG's value is dead the moment it has been copied
; into FNCNT.
NPGO:   lda     FNACKS
        clc
        adc     #1
        bne     NPGO1
        lda     #1              ; 0 is reserved as "never used"
NPGO1:  sta     FNSEQ
        ldx     #FR_SEQ
        jsr     FNRW            ; launching it is this single commit
        lda     FNTMO
        sta     FNCNT
NPGO2:  lda     #NPQUANT
        sta     FNTMO
; ACKSEQ is published LAST, after the reply, its length and the error code are
; all in place, so a match means everything behind it is already readable.
NPGO3:  lda     FNACKS
        cmp     FNSEQ
        beq     NPGO5
        jsr     NFRAME
        dec     FNTMO
        bne     NPGO3
        dec     FNCNT
        bne     NPGO2
        lda     #FNEWAIT
        rts
NPGO5:  lda     FNERR
        rts

; ---------------------------------------------------------------------------
; NFRAME -- one frame of waiting, and the whole reason this bank has a display
; kernel in it.
;
; A REAL frame, always. The text planes hold whatever rows have been rendered
; so far and the reply window is not repainted until the next transaction, so
; drawing is both correct and free -- and a page visibly fills in as it loads
; instead of arriving behind a blank screen. It is also what keeps DFRAME
; scanning the input while a round trip is in flight, which is the whole
; reason a press made during a fetch is still there afterwards.
;
; It clobbers X and Y, which is why every caller counts its repeats in memory.
NFRAME: jmp     DFRAME
