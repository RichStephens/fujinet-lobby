; lbtail.asm -- the fixed half: the trampoline, the shared transport, and the
; cold stub.
;
; $1800-$1F1F is the cartridge's mailbox -- text planes, reply window, control
; page, TX page, status -- and the cartridge paints it. The client owns
; $1F20-$1FFB, which fuji_mailbox.h calls the fixed tail, plus the vectors.
;
; Everything here has to be at an address that does not move, for three
; different reasons:
;
;   * The store that switches bank is the LAST instruction fetched from the
;     old bank and the very next fetch comes from the new one, so the jump
;     after it cannot live in a bank.
;   * This console has no reset line to the cartridge. The RESET switch
;     restarts the 6507 with whatever bank was last selected still mapped, so
;     a cold stub living in bank 0 would simply not be there when it was
;     needed.
;   * The transport is the same bytes in all seven banks, and a bank is 2048.
;     Here it is one copy that all of them can reach.

        CPU     6502
        INCLUDE "vcs.inc"
        INCLUDE "fujinet.inc"
        INCLUDE "lbdefs.inc"

        INCLUDE "lbtailbody.inc"

        END
