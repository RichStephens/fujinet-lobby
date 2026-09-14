; lbdefs.inc -- the wire format, the screen, and the 128 bytes.
;
; Equates only, so this goes BEFORE the ORG next to fujinet.inc.
;
; This console has 128 bytes of RAM and the stack mirrors into the top of
; them. What that buys, once accepted, is a design where the CARTRIDGE holds
; the state: a 215-byte record is read out of the cartridge's 512-byte reply
; window IN PLACE and rendered from there, and the four strings a boot needs
; live in the cartridge's path buffers. Nothing below is a buffer.

; ---------------- the banks ----------------
; A bank switch replaces every byte of $1000-$17FF, so each bank carries its
; own copy of every module it calls; only zero page crosses. The text planes,
; the reply window and the path buffers are CARTRIDGE state and survive the
; switch, which is why a bank change is a screen change and nothing has to be
; copied.
;
; Image = (N+1) * 2048 with N in {1,3,7,15} -- MAME's cart slot accepts no
; other size -- so seven banks and 16K.
;
; THE FETCH HAS A BANK OF ITS OWN, as in the sibling ports: net.inc and
; url.inc are ~550 bytes together and the list bank needs its room for the
; kernel, the renderer and the scroll. A bank with no display kernel of its
; own does not care that the screen is blanked while it talks.
BANKLST EQU     0               ; the room list. Bank 0 is where the cold stub
                                ;   sends us, so it is the first screen by
                                ;   construction.
BANKFET EQU     1               ; fetch a page, stage a record, count pages
BANKNAM EQU     2               ; the on-screen keyboard and the username
BANKPRP EQU     3               ; host slot and appkey: everything that has to
                                ;   happen before a mount can be asked for
BANKBOT EQU     4               ; set the path, mount, watch the bar, swap
BANKCHT EQU     5               ; the chat room's URL
BANKSPR EQU     6               ; the spare bank. An image has to be one of
                                ;   four sizes and 16K is the one that fits
                                ;   five banks, so two exist whether or not
                                ;   they are wanted; each holds a stub back to
                                ;   bank 0, so a stray switch is survivable
                                ;   rather than a jump into a page of BRK.
NBANKS  EQU     7

; The trampoline, at a fixed address in the fixed tail because the banks are
; assembled separately. See lbtail.asm.
LBGOTO  EQU     FNTAIL

; ---------------- what to do on arrival ----------------
; A bank switch is a JUMP, never a call: the store that switches is the last
; instruction fetched from the old bank, so there is no return address to come
; back to. "Where to carry on" is therefore DATA, in LBENT.
ENCOLD  EQU     0               ; the list, from scratch -- and it MUST be 0,
                                ;   because the cold stub forces this value
ENLIST  EQU     1               ; the list, redrawing what is already there
ENSHOWN EQU     2               ; the list, already drawn -- just run
ENFETCH EQU     3               ; the fetch bank: one page
ENSTAGE EQU     4               ; the fetch bank: stage the selected record
ENCOUNT EQU     5               ; the fetch bank: how many pages are there
ENNAME  EQU     6               ; the keyboard
ENPREP  EQU     7               ; claim a host slot and write the appkey
ENBOOT  EQU     8               ; mount and boot the staged room
ENCHAT  EQU     9               ; the chat URL screen

; ---------------- the path buffers ----------------
; The strings too big for console RAM live in the CARTRIDGE, which cannot
; spare 130 bytes for two URLs out of 128. They are filled while the record
; they come from is still in the reply window and read back long after it is
; gone.
;
; PBNAME doubles as the scroll's source: the room name is streamed in at the
; same moment as the boot strings, and FB_PATH then slides a window over it
; with no further round trip.
;
; There are five things that want a buffer and there are four buffers, so one
; pair has to share. It is the boot path's and the keyboard's, because those
; two are the pair that provably cannot be live together: the keyboard is a
; screen of its own, reached from the list by SELECT, and staging happens on
; the way out of the list by FIRE. Whichever ran last wrote the buffer, and
; whichever runs next rewrites it before reading it.
PBURL   EQU     FP_SEL0         ; the room's serverurl, for the appkey handoff
PBNAME  EQU     FP_SEL1         ; the room name, for the bounce scroll
PBHOST  EQU     FP_SEL2         ; the client_url's host half
PBPATH  EQU     FP_SEL3         ; ...and its path half
PBEDIT  EQU     FP_SEL3         ; what the keyboard is typing -- see above

; ---------------- the wire format, ?bin=2 ----------------
; GET /view answers with a 3-byte header then COUNT fixed-stride records. The
; layout is the Go server's GameServerMin.appendAsBinary (server/model.go) and
; is identical to the offsets in the intv and coleco ports' REC_* tables.
;
; bin=2 rather than bin=1: its first 189 bytes are byte-for-byte the bin=1
; record -- that format is frozen forever by the server's own comment -- and
; the 26 bytes it adds are the chat room's URL. Asking for the superset costs
; 26 bytes a record and nothing else.
;
; Do NOT ask for &be=1. The Go server's big-endian path is the road much less
; travelled, and the Intellivision port found corruption on it that always
; landed on exact multiples of 256.
LBHDRL  EQU     3               ; [count][reserved][reserved]
LBHCNT  EQU     0               ; the count is the first of the three

SVGT    EQU     0               ; appkey/game_type: the key_id the booted game
                                ;   reads its server URL back from
SVGAME  EQU     1               ; game[17]     -- the header row's text
SVROOM  EQU     18              ; server[33]   -- the room row's text
SVURL   EQU     51              ; serverurl[65]
SVCLI   EQU     116             ; client_url[65]
SVREG   EQU     181             ; region[3]    -- unused by any client today
SVONL   EQU     184             ; online       -- ditto
SVCUR   EQU     185             ; curplayers
SVMAX   EQU     186             ; maxplayers
SVPING  EQU     187             ; pingage, u16 -- always zero, reserved
SVCHAT  EQU     189             ; chat url[26], uppercase, <= 25 chars
SVSTRID EQU     215             ; bin=2. bin=1 is 189.

SVGAMEL EQU     17
SVROOML EQU     33
SVURLL  EQU     65
SVCLIL  EQU     65
SVCHATL EQU     26

; TWO RECORDS PER READ, and that is the number the reply window chooses: it is
; 512 bytes and 2 * 215 = 430 fits, where three would not. Reading a whole
; page in one go would need the second slice, and no 2600 client has ever
; implemented slice paging.
SVPERRD EQU     2
SVRDLEN EQU     SVPERRD*SVSTRID

; ---------------- paging ----------------
; NINE RECORDS A PAGE, and the nine is load-bearing rather than a taste.
;
; A page draws a header row whenever the game name changes, so the worst case
; -- every record a different game -- is two rows per record. Nine records can
; therefore never overflow eighteen list rows, whatever the server sends.
;
; That one property pays for three things the sibling ports had to build:
;
;   * NO PAGE STACK. The Intellivision and the ColecoVision keep a ten-deep
;     stack of page-start offsets because a page that deferred a widowed
;     header does not start where arithmetic says it does. Here page N starts
;     at 9N, always, so going back is a decrement.
;   * NO WIDOW RULE. intv/st_list.bas defers a record whose header would have
;     no room row under it. Nothing can be widowed here.
;   * A CHEAP PAGE COUNT. The Intellivision re-walks the ENTIRE list with
;     pagesize=255 to count pages, because headers make the count
;     uncomputable from the total. With a fixed stride it is
;     ceil(total / 9) -- and the total is the first byte of a reply, so
;     counting is one request whose body is never read.
;
; The cost is density: nine rooms of one game use ten of the eighteen rows.
; On a twelve-column screen that is the better trade.
LBPGSZ  EQU     9

; PAGING PAST THE END IS AN HTTP 404, NOT AN EMPTY REPLY. server/actions.go
; answers a platform with no servers -- and an offset past the last one -- with
; 404 and a JSON body, which has a perfectly plausible length and would parse
; as a record count of whatever its first byte happens to be. The only place
; that is visible is NET_STATUS's fourth byte, so NSDEVST is checked on every
; settle and a failure with LBPAGE > 0 steps back a page and refetches.

; ---------------- the screen: 12 columns, 21 rows ----------------
;   0        LOBBY   n/m     the title, and which page of how many
;   1-18     the list: a game header row wherever the game name changes,
;            a room row under it. Rooms are what the cursor selects; games
;            are not.
;   19       SEL=<name>      the player name, ON the key that changes it --
;                            which is the only way a legend fits in twelve
;                            columns at all
;   20       RST=REFRESH
RTITLE  EQU     0
RLIST0  EQU     1
NLISTR  EQU     18              ; list rows
RLISTN  EQU     RLIST0+NLISTR-1
RNAME   EQU     19
RHINT   EQU     20

; Nine records can never overflow eighteen rows, which is what removes the
; widow rule. An assembly-time failure rather than a comment, because the
; overflow would be a truncated page that looked exactly like a short one.
;
; This test has to come AFTER NLISTR, not up beside LBPGSZ where it reads
; better: AS resolves an IF in its FIRST pass, and a condition naming a symbol
; defined further down the file is not a build error -- it quietly takes the
; branch it should not.
        IF      2*LBPGSZ>NLISTR
        ERROR   "a page of LBPGSZ records can widow a header in NLISTR rows"
        ENDIF

; A room row is seven columns of name and five of "cur/max", right-flushed.
;
; Five, not four, and the fifth is not spare: a full table of sixteen reads
; "12/16", and a count field that could not hold two digits either side would
; have to clamp at nine and lie about the room. Seven visible characters
; against a 33-byte field is why the selected row bounce-scrolls -- truncation
; alone cannot tell two tables of one game apart, and "TABLE T" is exactly
; that failure.
RMNAMEW EQU     7
RMCNTW  EQU     FNTCOL-RMNAMEW

NAMEMAX EQU     8               ; the appkey username: 2-8 of A-Z0-9
NAMEMIN EQU     2

; ---------------- row classes and colours (NTSC) ----------------
; The kernel colours each row from LBCLS, one byte a row, on the seam line.
; See lbdisp.inc for why that line is free and what it costs.
CBLACK  EQU     $00
CBLUE   EQU     $84             ; chrome, and the side border
CTEAL   EQU     $B4             ; a game header's band
CRED    EQU     $44             ; the selected room
CWHITE  EQU     $0E
CBORDER EQU     CBLUE

; A ROW'S CLASS IS ITS COLOUR, not an index into a palette, and that is what
; makes the seam line cheap: one zero-page,X load straight into COLUBK, 23
; cycles in, where a class plus a palette lookup would be 32 and right on the
; border's edge. The names exist so a renderer reads as intent.
;
; What it gives up is a per-class INK. Every background here is luminance 0 or
; 4 under white, so there is nothing to gain -- and the seam line has
; thirty-five cycles spare if that ever stops being true.
;
; It also means nothing records what a row was BEFORE it was selected. That is
; fine, and it is fine by construction: the cursor only ever lands on a room
; row, and every room row is CLROOM, so deselecting is a store of a constant.
; A second room colour -- dimming an offline room, say -- would have to bring
; a byte to remember it by, which is why offline rooms are not dimmed.
CLCHROM EQU     CBLUE           ; the title, the name row, the hint
CLHDR   EQU     CTEAL           ; a game header
CLROOM  EQU     CBLACK          ; a room
CLSEL   EQU     CRED            ; the selected room

; The blue side border is not only decoration, it is also the seam line's
; DEADLINE. The playfield draws OVER the background, so a COLUBK store landing
; under the border cannot be seen -- which is what lets the seam reprogramme
; the background at all, rather than having to finish inside hblank.
;
; PF0's high nibble is pixels 0-15 and PF1 drawn MSB first is pixels 16-31, so
; the sibling ports' $F0/$F0 gives a 32-pixel border. THIS PORT LIGHTS PF0
; ONLY, for sixteen: the seam's store completes at cycle 23, which is pixel 1,
; so fifteen pixels of margin is already an order of magnitude more than it
; needs -- and the other sixteen pixels a side are worth more as band. A row's
; colour then runs pixels 16-143 instead of 32-127, which on a screen whose
; whole hierarchy is carried by the background is the difference between a
; band and a stripe.
PFEDGE0 EQU     $F0             ; pixels 0-15, mirrored to 144-159
PFEDGE1 EQU     $00

; ---------------- zero page ----------------
; $80-$8C is the transport's (fujinet.inc) and $81/$82 the display kernel's;
; $A8/$A9 are INSCAN's. Everything else below is ours.
;
; $80-$A6 is ALSO the ROM swap stub's landing ground, and unlike the sibling
; game ports -- which boot nothing and take the whole region as theirs -- this
; client really does swap. It is still safe to keep the kernel's cells and the
; row-class table there: FNSWAP copies the 39-byte stub in and jumps to it,
; and the stub never returns. No frame is ever drawn after the copy, so
; nothing reads LBCLS again. What must NOT live here is anything the boot
; sequence itself still needs, and nothing does -- by then every string it
; uses is in a cartridge path buffer.
LBIDX   EQU     $84             ; a render loop's index. Its own cell because
                                ;   LBTMP is not safe across a call.
LBTMP   EQU     $85             ; scratch. SHORT-LIVED means exactly that: any
                                ;   routine you call may clobber it.
LBROW   EQU     $8D             ; kernel: the row being drawn, 0-20
LBLINE  EQU     $8E             ; kernel: ink lines left in it

; LBCLS -- the per-row class table, one byte a row, read by the seam line.
;
; TWENTY-TWO entries, not twenty-one: the seam at the bottom of row 20
; programmes row 21, which does not exist, and giving that entry the chrome
; class is what turns the handover to the bottom band into a colour the kernel
; was going to write anyway.
;
; In ZERO PAGE, and that is the one place this port departs from
; fujinet-5cardstud/atari-2600/src/cdisp.inc, whose equivalent table is in
; ROM. A seat's colour there is a function of the layout; a lobby row's is a
; function of what the server sent, so the table has to be written at render
; time. Zero-page,X costs four cycles flat -- one LESS than the ROM form,
; which pays a fifth whenever its table straddles a page.
LBCLS   EQU     $8F             ; $8F-$A4
LBCLSN  EQU     FNTROW+1

INRPT   EQU     $A5             ; INREPT's auto-repeat countdown
LBDGT   EQU     $A6             ; LBDEC's digit and its leading-zero latch
LBNUM   EQU     $A7             ; the value LBDEC is printing

; ---------------- the application's own ----------------
; $AA-$BA is PERSISTENT: written by one bank and read by another, so nothing
; may alias it. Seventeen cells, and they are all of them.
LBSEL   EQU     $AA             ; the SCREEN ROW the cursor is on
LBIDXS  EQU     $AB             ; the RECORD it is on, 0-based within the page.
                                ;   Both, because the colour table is indexed
                                ;   by row and the server is indexed by record
LBCNT   EQU     $AC             ; rooms drawn on this page
LBFULL  EQU     $AD             ; the server filled the ask, so a next page
                                ;   may exist
LBPAGE  EQU     $AE             ; the page being shown, 0-based
LBPAGES EQU     $AF             ; how many there are, 0 = not counted yet
LBGT    EQU     $B0             ; the staged room's game_type: the appkey KEY
                                ;   the booted game reads its server back from
LBERR   EQU     $B1             ; the last failure
LBSTEP  EQU     $B2             ; where it happened: 1 open 2 status 3 read
                                ;   4 stage 5 host 6 appkey 7 boot
LBENT   EQU     $B3             ; EN*: what the bank being entered should do
LBFRAME EQU     $B4             ; a free-running frame counter
LBINP   EQU     $B5             ; THE INPUT LATCH. Scanned by DFRAME in every
                                ;   bank and OR'd in; whichever hook cares
                                ;   drains it. See lbdisp.inc.
LBTMR   EQU     $B6             ; idle-before-scroll, and failure pauses
LBSCRL  EQU     $B7             ; the scroll window's offset into the name
LBSDIR  EQU     $B8             ; which way it is panning
LBSTG   EQU     $B9             ; nonzero: the path buffers hold the room the
                                ;   cursor is on, so FIRE needs no round trip
LBKEY   EQU     $BA             ; THIS FRAME'S input, drained out of LBINP.
                                ;   Its own cell and not LBTMP: every handler
                                ;   below the first test is reached through a
                                ;   call that borrows the scratch, and 5 Card
                                ;   Stud's move cursor walked on its own for
                                ;   exactly that reason -- the second test of
                                ;   a frame read a string length as a press.

; ---------------- $BB-$CB: bank-local, and deliberately aliased ----------
; The banks are different 2K images and only zero page crosses between them,
; so a cell that exactly one bank touches is one cell. This is the same
; bank-local overlap 5 Card Stud's CDCNT/SNDCNT uses and Battleship's
; placement screen uses; what makes it safe is that each column below is
; reachable only from its own bank, and nothing in either column outlives the
; bank switch that ends it.
LBNLEN  EQU     $BB             ; characters typed so far   -- NAME BANK ONLY
LBKCOL  EQU     $BC             ; the grid cursor's column  -- NAME BANK ONLY
LBKROW  EQU     $BD             ; ...and its row            -- NAME BANK ONLY

LBREQ   EQU     $BB             ; the request in flight     -- FETCH BANK ONLY
LBROWS  EQU     $BC             ; the next list row to draw. Fetch-bank-only
                                ;   because bank 0 finds its rows by scanning
                                ;   LBCLS for a colour, not by counting them.
LBAVL0  EQU     $BD             ; NET_STATUS bytes waiting
LBAVL1  EQU     $BE
                                ; $BF-$C0 are free. They held the settle
                                ; loop's "previous reading" until the floor
                                ; turned out to be the whole condition -- see
                                ; NSETL in net.inc.
LBRXL0  EQU     $C1             ; the READ's reply length, captured at once
LBRXL1  EQU     $C2
LBMIN0  EQU     $C3             ; the byte count THIS CHUNK will not settle
LBMIN1  EQU     $C4             ;   below
LBTRIES EQU     $C5             ; the settle loop's bound
LBDLY   EQU     $C6             ; its inter-poll delay: in memory, because
                                ;   NFRAME counts in X and Y and comes back
                                ;   with both gone
LBGOT   EQU     $C7             ; records consumed out of this page so far,
                                ;   which is also the number of room rows
                                ;   drawn: every record draws exactly one --
                                ;   and, because it is zero for the first
                                ;   record, it is also what says that record
                                ;   always gets a header
LBCHUNK EQU     $C8             ; records in the chunk now in the window
LBCHI   EQU     $C9             ; which of them is being rendered. Its own
                                ;   cell and not LBIDX, because LBFLD borrows
                                ;   LBIDX to walk a field and would eat the
                                ;   loop counter under it -- the family's
                                ;   "a scratch cell is not safe across a call"
                                ;   rule.

; THE PREVIOUS RECORD'S GAME NAME, AS A 16-BIT HASH -- and this is the one
; place this client is inexact where the ColecoVision is exact.
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
LBGS0   EQU     $CA
LBGS1   EQU     $CB

; ---------------- the stack ----------------
; $CC-$FF, 52 bytes, 26 nested calls. The two sibling game ports give it
; $C0-$FF for a measured depth of about sixteen; this client has more state
; and a shallower call graph, so it takes twelve of those bytes back. "26 is
; still enough" is a claim, so emu/stack.lua watermarks SP every frame and
; fails if it ever goes below STKLOW.
STKLOW  EQU     $CC

; ---------------- requests ----------------
RQPAGE  EQU     0               ; one page of the list
RQONE   EQU     1               ; the selected record, to stage it
RQCOUNT EQU     2               ; the total, whose body is never read

; How long things wait, in frames.
INDLAY  EQU     30              ; ~0.5s before a held direction repeats
INRATE  EQU     6               ; ~10 a second after that
IDLEFRM EQU     45              ; cursor still this long: stage and scroll
SCRLTIC EQU     6               ; frames per scroll step
SCRLHLD EQU     30              ; ...and the pause at each end
FAILFRM EQU     150             ; ~2.5s after a failure
