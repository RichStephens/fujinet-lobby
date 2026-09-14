# The FujiNet Game Lobby on the Atari 2600

Standalone, like `../intv/` and `../coleco/`: the shared `clients/` core
assumes a keyboard, a screen wide enough for a sentence and kilobytes of
buffers, and this console has a joystick, three buttons, twelve columns and
128 bytes of RAM.

Feature parity with `../intv/` — pick a room, change your name, boot the game
— on a machine with no framebuffer and no text mode at all.

## Building

    make                      # build/lobby.bin, 16384 bytes
    make layout               # the screen with no network in it
    ./run.sh lobby <harness>  # run it in MAME

Needs [Macroassembler AS](http://john.ccac.rwth-aachen.de:8000/as/) (`asl` and
`p2bin`, on `PATH` or in `~/asl`) — the same assembler the Channel F, Arcadia
and Odyssey² ports use. Not dasm: it is not in CI, and `src/vcs.inc` is written
from the hardware register map rather than copied from the dasm world's
`vcs.h`, which is not redistributable.

`$FN2600` (default `~/Workspace/fujinet-firmware/pico/atari-2600`) is the
cartridge's own tree. Two things live there and must not be forked: the mailbox
header `src/fujinet.inc` mirrors, and the MAME cartridge device.

`make install` says where the image goes. `fujinet-config`'s LOBBY menu entry
boots `ec.tnfs.io:/a2600/lobby.bin` — one literal, in that port's
`src/hosts.asm`.

## The machine

|  |  |
|---|---|
| Display | **12 columns × 21 rows.** A 3×5 glyph in a 4×6 cell. |
| Console RAM | 128 bytes, and the stack mirrors into the top of them. |
| ROM | Six 2K banks, a spare, and a fixed 2K half. Only zero page crosses a bank switch. |
| Input | Joystick, one button, SELECT and RESET. |

**The cartridge composes the glyphs.** There is no framebuffer and no character
generator: the RP2040 renders ASCII into the exact shape a 48-pixel player
kernel wants and publishes six 128-byte planes, and the 6507 does nothing but
stream them into `GRP0`/`GRP1` on a cycle-exact schedule.

**Almost nothing lives in console RAM.** A server record is 215 bytes and is
read *in place* in the cartridge's reply window; the two URLs a boot needs, the
host name and the name being typed are all 256-byte strings held in the
cartridge. The console holds a cursor, a page number and a handful of flags.

## Controls

| | |
|---|---|
| ↑ ↓ | move the cursor between rooms |
| ← → | previous / next page |
| FIRE | join the room: mount its client and boot it |
| SELECT | change your name |
| RESET | refresh the list |

RESET is a **switch** on this console, not a reset — it restarts nothing, so
what it means is the client's to choose, and every lobby in the family makes it
"fetch again".

On the keyboard: the stick moves, FIRE types, SELECT deletes, RESET accepts.

## A colour per row

This is the one thing this port does that no sibling does, and it is free.

`vcs_render_row()` writes ZERO to scanline 5 of every cell — the sixth line of
a 4×6 cell is blank leading — so the kernel is 21 rows of *(5 cycle-exact ink
lines + 1 **seam line**)*, and the seam is a line on which no glyph can
possibly be drawn. The sibling game ports already spend it on colour. What is
new here is that the lobby's row classes are **dynamic** — a game header
appears wherever the game name changes, which depends on what the server sent —
so the table cannot be the ROM constant `cdisp.inc` uses. It is `LBCLS`,
twenty-two bytes of **zero page**, and it holds the `COLUBK` value itself
rather than an index into a palette.

Holding the colour rather than a class is what makes the seam cheap: one
zero-page,X load and one store, 23 cycles in, where a class plus a palette
lookup would have been 32 and right on the border's edge. Zero-page,X is also
four cycles *flat*, one less than the ROM form's worst case.

Three things fall out of it:

- **Game headers are a coloured band and rooms are not**, which is the whole
  hierarchy of the screen carried by something other than the eleven characters
  there is no room for.
- **The selection is a coloured row, not a `>` in column 0.** Every other client
  in the family spends a mechanism on that gutter — `FN_BLIT_TCELL`, two pokes
  and a wait on `FN_B_BLITGEN` per cursor step — because there is no inverse
  video. Colouring the row is four zero-page stores, no blit, no round trip,
  and it **gives column 0 back to the text**.
- **The blue side border is not only decoration.** The playfield draws over the
  background, so a `COLUBK` store landing under the border cannot be seen; take
  the border away and the seam's deadline tightens to the end of hblank. This
  port lights `PF0` only, for sixteen pixels rather than the siblings' thirty-two
  — the store lands at pixel 1, so fifteen pixels of margin is already an order
  of magnitude more than it needs, and the other sixteen a side are worth more
  as band.

`emu/colours.lua` taps `COLUBK` and requires exactly twenty-two writes a frame,
each equal to `LBCLS`. `emu/frames.lua` requires every frame to be 262 lines —
a seam line that overruns does not glitch, it silently costs a second scanline.

## The screen

```
row  0        LOBBY   1/2       the title and which page of how many
rows 1-18     the list          a game header wherever the game changes,
                                a room row under it
row 19        SEL=THOMA         the name, ON the key that changes it
row 20        RST=REFRESH
```

`SEL=` plus an eight-character name is exactly twelve columns. Putting the name
on the key that edits it is the only way a legend fits on this screen at all.

A room row is seven columns of name and five of `cur/max`, right-flushed —
five because a full table of sixteen reads `12/16`, and a count that could not
hold two digits either side would have to clamp at nine and lie about the room.

**Nine records a page**, and the nine is load-bearing. A record costs at most
two rows, so nine can never overflow eighteen, whatever the server sends. That
one property removes three things the sibling ports had to build: the widowed
header rule (`intv/st_list.bas` defers a record whose header would have no room
row under it — arithmetically impossible here), the page-start stack (page *N*
starts at 9*N*, so going back is a decrement, where the ColecoVision carries ten
`unsigned int`s), and the page-count walk — the Intellivision re-reads the
**entire list** to count pages, because with row-bounded pages the count is not
computable; here it is `ceil(total / 9)` and the total is the first byte of a
reply whose body is never read.

The cost is density: nine rooms of one game use ten of the eighteen rows.

## The banks

| | | |
|---|---|---|
| 0 | `lblist` | cold start, the username, the cursor |
| 1 | `lbfetch` | a page, rendered as it arrives; the page count |
| 2 | `lbname` | the on-screen keyboard |
| 3 | `lbprep` | re-fetch the room, split its URL, host slot, appkey |
| 4 | `lbboot` | set the path, mount, the bar, the swap |
| 5 | `lbchat` | the chat room's URL — **not written yet** |
| 6 | `lbspare` | a stub back to bank 0 |

**Bank 1 composes the whole list and bank 0 composes none of it.** That is
forced rather than chosen: a page is up to 1935 bytes against a 512-byte reply
window, so records arrive two at a time and each pair is repainted by the next
READ. A record can only be rendered while it is in the window. Once the
renderer is in the bank that reads, bank 0 has nothing left to compose — which
is what makes a cursor move two stores.

## The handoff

FIRE does not send anything to the lobby server. Joining a room is a **local**
write and a reboot:

1. Re-fetch the one record with `pagesize=1&offset=<absolute>`. It has to come
   back: the list was rendered two records at a time and the selected one was
   repainted out of the window several reads ago, and there is nowhere in 128
   bytes to have kept its two 65-byte URLs.
2. **While it is still in the window**, stream `serverurl`, the room name and
   the two halves of `client_url` into four cartridge path buffers. The split
   has to happen here, on the console side: a path buffer is write-only, so a
   URL parked in one can never be parsed afterwards.
3. `READ_HOST_SLOTS`, then `WRITE_HOST_SLOTS` with the **last** slot replaced —
   all eight, 256 bytes, because there is no single-slot write, and assembled
   as it is sent. The last slot always, because the other seven accumulate
   whatever every other client left in them and a "does this already match?"
   test can be fooled by a leftover.
4. `MOUNT_HOST`.
5. `OPEN_APPKEY(1, 1, game_type, write)` and write the room's URL. **This is the
   handoff**: the client about to boot reads that same slot under its own
   game_type and learns which server to talk to. Best effort — a game that
   cannot find its server says so better than this screen can.
6. `SET_DEVICE_FULLPATH`, `MOUNT_IMAGE`, a twelve-cell bar over
   `FN_R_BOOT_PCT`, then the bootlock and the swap.

`emu/boottest.lua` proves it by watching the `FUJI` claim disappear: an image
carrying it promises to be a FujiNet client and the mailbox stays live, and an
ordinary game carries no such promise. When those four bytes stop reading
`FUJI`, something that is not this client is running.

## Where this client is inexact

**The game-header comparison is a 16-bit hash, not the name.** A header is
drawn wherever the game name changes, so a record has to be compared with the
one before it. `coleco/st_list.c` keeps `static char prevgame[17]`. Neither
half of that is available here: there are no seventeen spare bytes, and — the
decisive one — **the previous record is no longer in the window**, because
records arrive two at a time and every transaction repaints it. So sixteen bits
of rotate-and-xor cross the chunk boundary instead of seventeen bytes. A
collision merges two *adjacent* games under one header: one missing row, and
nothing else. The value is compared and never displayed.

## Tests

`emu/*.lua` drive MAME against a live `fujinet-pc`. They compare **rendered
glyph forms, not decoded text** — at 3×5 the font had to have `0`/`O`, `5`/`S`
and `C`/`[` redrawn before they were even distinguishable, and decoding stays
the lossy direction.

    make shot        # the layout ROM; dispcheck.py compares the raster
    make colours     # 22 COLUBK writes a frame, every one equal to LBCLS
    make frames      # every frame is 262 lines
    make cursor      # the selection walks every room row, both directions
    make nametest    # type a name, prove it round-trips through the appkey
    make boottest    # FIRE really boots the game behind a room

`nametest` and `boottest` **write to a real FujiNet**: the first changes the
username appkey every client on the machine shares (it prints what it found, so
a second run with `NAME=` puts it back), and the second rewrites the last host
slot and mounts something. Point `boottest` at a room whose `client_url` is on
the FujiNet's own SD host and it boots for real while rewriting that slot with
the name already in it.

A local server to test against: run `../server` from a directory with its own
`db/lobby.sqlite3` (`make install-db` is **destructive** — never run it where
the real database is), POST rooms whose `clients` carry
`{"platform":"a2600","url":"tnfs://..."}`, and build with
`ENDPOINT=http://127.0.0.1:8090/`.

## Notes for anyone changing this

**A bank that grows past `$17FF` is silently truncated** by `p2bin -r`: the
image builds, the size is right, `checkrom` passes, and the instructions past
the end are simply gone — what a jump into them finds is the next bank's bytes.
`tools/checkbanks.py` reads the assembler's own listing and fails the build.
Watch `lbprep`, which has under a hundred bytes spare; if it overflows, the
host-slot half moves into the spare bank behind a new entry code.

**Equates go in a different file from code.** `src/fujinet.inc` and
`src/lbdefs.inc` are included before the `ORG`, `src/lblib.inc` and the rest
inside it. Getting that wrong assembles the whole transport at `$0000` and every
`jsr` becomes `20 00 00` — which assembles cleanly and fails at run time.

**`IF` conditions must resolve in AS's first pass.** A test naming a symbol
defined further down the file is not a build error; it quietly takes the branch
it should not. The widow-impossibility assertion sits below `NLISTR` for that
reason and not for a tidier one.

**Never use a branch as an unconditional jump on flags you did not set.**
`ldx #0` sets Z, so a `bne` placed after one on the theory that the *accumulator*
is nonzero falls straight through. That cost a page its ninth room: the last
chunk is one record and it waited for two records' worth of bytes that were
never coming.

**A register is not safe across a call either.** `FNENDR` ends with a zero in
A, because it loads the attribute byte to store it — so a loop carrying its row
counter in A across it counts 0, 1, 0, 1 for ever, behind a screen that is still
blanked.

**The settle loop here is a floor and not two agreeing readings**, which is
where this client departs from every sibling. That rule exists because they read
*whatever is available*; this one always reads an exact byte count that the
floor already proves is there. Polling until a big reply stopped moving timed
the mailbox out at 3013 bytes of 3228.

**In a MAME harness, `set_value(1)` is a press — for the console switches too.**
SWCHB is active low on the hardware and MAME applies that inversion itself, so
a harness that writes 0 to "press" SELECT is really releasing it, and the 1 it
writes to "release" is a press that then never ends.

**The sequence number comes from the cartridge**, never a counter in RAM: this
connector has no reset line, so the RESET switch restarts the 6507 and leaves
the cartridge running. **The path buffers survive a console reset too**, which
is why the cold start empties all four.

## Not done yet

- **The chat room screen.** `bin=2` is already requested and every record's
  chat URL is on the wire at offset 189; bank 5 is a stub. The plan is a text
  screen showing `HTTP://Q.TNFS.IO/6EWL3G` across two rows — **not** a QR code,
  which would need an encoder the cartridge does not have and a 2K bank cannot
  hold.
- **Bounce-scrolling the selected room's name.** Seven visible columns against a
  33-byte field. The mechanism is already paid for: `lbprep` streams the full
  name into `PBNAME` on the way to a boot, so the scroll is `FB_PATH` blits over
  a buffer that is already there — it wants the staging to move to "when the
  cursor goes idle" rather than "on FIRE".
- **Offline rooms are not dimmed.** The record's `online` byte is read by no
  client in the family today. Here it would want a second room colour, and
  nothing records what a row was before it was selected — deselecting is a store
  of a constant.
