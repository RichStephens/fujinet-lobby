; lbprep.asm -- bank 3: everything that has to be true before a mount can be
; asked for.
;
; THE ORDER IN HERE IS THE WHOLE THING. READ_HOST_SLOTS repaints the reply
; window with 256 bytes of host names, so by the time it has run, the record
; the player picked is GONE and its two 65-byte URLs with it. There is nowhere
; in 128 bytes of console RAM to keep them. So they go into the cartridge's
; path buffers first, and nothing else happens until they are all there.
;
; The record has to be fetched again to be here at all. The list was rendered
; chunk by chunk, two records at a time, so the selected record was repainted
; out of the window several reads ago -- the ColecoVision re-fetches for the
; same reason, and by the same route: pagesize=1 at the absolute offset.

        CPU     6502
        INCLUDE "vcs.inc"

PAD3    EQU     $81             ; the display kernel's 3-cycle pad target
SAVSP   EQU     $82

LBHASTX EQU     1               ; emits path buffers into TX
LBHASPL EQU     1               ; ...and builds 256-byte payloads

        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"
        INCLUDE "../build/tail.inc"

PROW    EQU     8               ; the one row this screen has to say anything on
PROWE   EQU     10              ; ...and where it says what went wrong

        ORG     $1000

START:  lda     #2
        sta     VBLANK
        lda     #RTITLE
        ldx     #RLISTN
        jsr     FNCLSR
        ldx     #(SJOIN)&$FF
        ldy     #(SJOIN)>>8
        jsr     FNSETP
        lda     #PROW
        jsr     FNSTRA
        ldx     #PROW
        lda     #CLHDR
        sta     LBCLS,x
        lda     #0
        sta     VBLANK
        jsr     DINIT
        jsr     DFRAME          ; one frame, so the word is on screen before
                                ;   the first round trip stalls the picture

        jsr     STAGE
        bne     PFAIL
        jsr     HOSTUP
        bne     PFAIL
        jsr     AKPUT           ; best effort: see below

        lda     #ENBOOT
        sta     LBENT
        lda     #BANKBOT
        jmp     LBGOTO

; A failure here leaves nothing mounted and nothing written that matters, so
; the way back is a cold entry: the list is refetched, which is the right
; thing anyway if the room the player picked has just gone away.
PFAIL:  lda     #PROWE
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
        ldx     #PROWE
        lda     #CLSEL
        sta     LBCLS,x
        lda     #FAILFRM
        sta     LBTMR
PFWAIT: jsr     DFRAME
        dec     LBTMR
        bne     PFWAIT
        lda     #ENCOLD
        sta     LBENT
        lda     #BANKLST
        jmp     LBGOTO

; ---------------------------------------------------------------------------
; APPVBL -- nothing. A press must not cancel a join half way through: by the
; time this screen is up, a host slot is about to be rewritten.
APPVBL: rts

; ---------------------------------------------------------------------------
; STAGE -- put everything a boot needs into the cartridge, while the record it
; comes from is still in the window.
;
; THE ORDER IS THE WHOLE THING. READ_HOST_SLOTS repaints the window with 256
; bytes of host names, so by the time the boot bank runs, this record is gone
; and its two 65-byte URLs with it. There is nowhere in 128 bytes of console
; RAM to keep them, so they go into the cartridge's path buffers and nothing
; else happens until they are all there.
;
; The record has to be fetched again to be here at all: the list was rendered
; chunk by chunk, so the selected record was repainted out of the window
; several reads ago. One more round trip for one record is what the
; ColecoVision does and for the same reason.
STAGE:  lda     #0
        sta     LBSTG
        lda     #RQONE
        sta     LBREQ
        jsr     NCLOSE
        jsr     NOPEN
        bne     STBAD
        lda     #LBHDRL
        ldx     #0
        jsr     NCHUNK
        bne     STBAD
        lda     FNRPLY+LBHCNT
        beq     STBAD           ; the list is live and it moved under us
        lda     #(SVSTRID)&$FF
        ldx     #(SVSTRID)>>8
        jsr     NCHUNK
        bne     STBAD
        jsr     FERECS
        beq     STBAD

        lda     #0
        jsr     LBRPTR
        ldy     #SVGT
        lda     (FNPTRL),y
        sta     LBGT
        beq     STBAD           ; game_type 0: nothing to hand off through an
                                ;   appkey, so there is nothing to boot into

; The room's own URL, for the appkey the booted game reads.
        lda     #PBURL
        jsr     FNWSEL
        jsr     FNWRST
        lda     #SVURL
        ldx     #SVURLL
        jsr     FNWFLD

; The room's name, for the bounce scroll. The same round trip pays for both.
        lda     #PBNAME
        jsr     FNWSEL
        jsr     FNWRST
        lda     #SVROOM
        ldx     #SVROOML
        jsr     FNWFLD

        jsr     STSPLT
        bne     STBAD
        lda     #1
        sta     LBSTG
        lda     #FNEOK
        rts
STBAD:  lda     #0
        sta     LBSTG
        lda     #$FF
        rts

; ---------------------------------------------------------------------------
; STSPLT -- split the record's client_url into a host and a path.
;
; It has to happen HERE, on the console side, while the bytes are in the
; window. A path buffer cannot be read back -- the page it is written through
; is write-only -- so a URL parked in one can never be parsed afterwards.
;
; "tnfs://ec.tnfs.io/a2600/lobby.bin" -> host "ec.tnfs.io", path
; "/a2600/lobby.bin". A URL with no scheme is assumed to start at the host,
; which is what every sibling port does; one with no '/' after the host has no
; path and is rejected.
STSPLT: lda     #SVCLI
        sta     LBIDX
SS1:    ldy     LBIDX
        lda     (FNPTRL),y
        beq     SS2             ; ran out: no scheme, so the host starts at 0
        cmp     #':'
        bne     SS1B
        iny
        lda     (FNPTRL),y
        cmp     #'/'
        bne     SS1B
        iny
        lda     (FNPTRL),y
        cmp     #'/'
        bne     SS1B
        iny
        sty     LBIDX           ; the host starts just past the "://"
        jmp     SS3
SS1B:   inc     LBIDX
        lda     LBIDX
        cmp     #SVCLI+SVCLIL
        bcc     SS1
SS2:    lda     #SVCLI
        sta     LBIDX

SS3:    lda     #PBHOST
        jsr     FNWSEL
        jsr     FNWRST
SS4:    ldy     LBIDX
        lda     (FNPTRL),y
        beq     SSBAD           ; a host with no path is not bootable
        cmp     #'/'
        beq     SS5
        sta     FNRSEL+FH_PATHC
        inc     LBIDX
        lda     LBIDX
        cmp     #SVCLI+SVCLIL
        bcc     SS4
        bcs     SSBAD

; The rest INCLUDING the leading '/', because that is what
; SET_DEVICE_FULLPATH wants: a path relative to the mounted host's root.
SS5:    lda     #PBPATH
        jsr     FNWSEL
        jsr     FNWRST
SS6:    ldy     LBIDX
        lda     (FNPTRL),y
        beq     SS7
        sta     FNRSEL+FH_PATHC
        inc     LBIDX
        lda     LBIDX
        cmp     #SVCLI+SVCLIL
        bcc     SS6
SS7:    lda     #0
        rts
SSBAD:  lda     #$FF
        rts


; ---------------------------------------------------------------------------
; HOSTUP -- put the room's host in a slot and mount it.
;
; THE LAST SLOT, ALWAYS, AND ALWAYS OVERWRITTEN. The other seven accumulate
; whatever every other FujiNet client on the machine has left in them, so a
; "does one of these already match?" test can be fooled by a leftover -- and
; the last is the least likely to be something somebody wanted.
HOSTUP: jsr     RDHOST
        bne     HU9
        jsr     WRHOST
        bne     HU9
        jsr     RDHOST          ; the reply window is stale after a write, and
        bne     HU9             ;   nothing else would say so
        lda     #NHOSTS-1
        jsr     MHOST
HU9:    rts

; RDHOST -- READ_HOST_SLOTS. The reply stays in the window: eight names of
; thirty-two bytes, 256 in all, which is slice 0 whole.
RDHOST: lda     #FNDEVF
        sta     FNDEV
        lda     #FCRHST
        sta     FNCMD
        lda     #0
        sta     FNNPR
        jsr     FNBEG
        jsr     FNGO
        sta     LBERR
        cmp     #FNEOK
        bne     RDHE
        jsr     FNACK
        sta     LBERR
        cmp     #FNEOK
        beq     RDHOK
RDHE:   lda     #5
        sta     LBSTEP
        lda     #$FF
        rts
RDHOK:  lda     #0
        rts

; WRHOST -- WRITE_HOST_SLOTS. All eight, 256 bytes, because there is no
; single-slot write in the protocol.
;
; Seven are copied straight back out of the window READ_HOST_SLOTS just
; filled, and the eighth is emitted by the CARTRIDGE out of PBHOST. Nothing is
; buffered anywhere.
WRHOST: lda     #FNDEVF
        sta     FNDEV
        lda     #FCWHST
        sta     FNCMD
        lda     #0
        sta     FNNPR
        jsr     FNBEG
        jsr     FNPBEG

        lda     #0
        sta     LBIDX           ; the slot
        ldx     #0              ; ...and its offset in the reply
WRH1:   lda     LBIDX
        cmp     #NHOSTS-1
        beq     WRHNEW
        ldy     #HOSTSLN        ; verbatim, NUL padding and all
WRH2:   lda     FNRPLY,x
        jsr     FNPCH
        inx
        dey
        bne     WRH2
        jmp     WRHNXT

WRHNEW: lda     #PBHOST
        jsr     FNWSEL
        jsr     FNWRAW
        lda     FNPCNT          ; the cartridge emitted these; count them, or
        clc                     ;   the padding below is measured from the
        adc     FNPLNL          ;   wrong place
        sta     FNPCNT
        lda     #HOSTSLN
        sec
        sbc     FNPLNL
        beq     WRH4            ; exactly full: nothing to pad
        tay
WRH3:   lda     #0
        jsr     FNPCH
        dey
        bne     WRH3
WRH4:   txa                     ; step over the slot that was replaced rather
        clc                     ;   than copied
        adc     #HOSTSLN
        tax

WRHNXT: inc     LBIDX
        lda     LBIDX
        cmp     #NHOSTS
        bcc     WRH1

        jsr     FNPEND
        jsr     FNGO
        sta     LBERR
        cmp     #FNEOK
        bne     WRHE
        jsr     FNACK
        sta     LBERR
        cmp     #FNEOK
        beq     WRHOK
WRHE:   lda     #5
        sta     LBSTEP
        lda     #$FF
        rts
WRHOK:  lda     #0
        rts

; MHOST -- MOUNT_HOST(A).
MHOST:  sta     LBTMP
        lda     #FNDEVF
        sta     FNDEV
        lda     #FCMHST
        sta     FNCMD
        lda     #1
        sta     FNNPR
        jsr     FNBEG
        lda     LBTMP
        jsr     FNPB
        jsr     FNGO
        sta     LBERR
        cmp     #FNEOK
        bne     MHE
        jsr     FNACK
        sta     LBERR
        cmp     #FNEOK
        beq     MHOK
MHE:    lda     #5
        sta     LBSTEP
        lda     #$FF
        rts
MHOK:   lda     #0
        rts

; ---------------------------------------------------------------------------
; AKPUT -- appkey(creator 1, app 1, key = the room's game_type) = its URL.
;
; THIS IS THE HANDOFF, and it is the whole reason the lobby exists: the client
; this is about to boot reads that same slot under its OWN game_type and finds
; out which server to talk to. There is no HTTP request for joining a room --
; it is a local write and a reboot.
;
; BEST EFFORT. A game that cannot read its server back will say so far better
; than this screen can, and refusing to boot over it would strand the player
; on a list with nothing to do.
AKPUT:  lda     #PBURL
        jsr     FNWSEL          ; so FNPLNL is this buffer's length
        lda     LBGT
        ldx     #AKMWR
        jsr     AKOPEN
        bne     AKP9
        lda     #FNDEVF
        sta     FNDEV
        lda     #FCAKWR
        sta     FNCMD
        lda     #1
        sta     FNNPR
        jsr     FNBEG
        lda     FNPLNL
        jsr     FNPB
        lda     #PBURL
        jsr     FNWSEL
        jsr     FNWRAW
        jsr     FNGO
        jsr     AKCLOSE
AKP9:   lda     #0
        rts

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
        sta     FNTX            ; the reserved SIXTH byte: five leaves the
                                ;   firmware waiting for one that never comes,
                                ;   and that reads back as a timeout
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
        lda     #0
        rts

; ---------------------------------------------------------------------------
        INCLUDE "lblib.inc"
        INCLUDE "state.inc"
        INCLUDE "net.inc"
        INCLUDE "url.inc"
        INCLUDE "lbdisp.inc"

SJOIN:  DB      "JOINING",0
SERR:   DB      "ERR ",0

        END
