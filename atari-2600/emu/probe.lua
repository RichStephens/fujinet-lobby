-- probe.lua -- where is it, and what does it think?
--
-- A tool rather than a test. Prints the live bank, the entry code, the
-- sequence numbers and the list state once a second, which is the quickest
-- way to tell a client that is stuck in a transaction from one that is stuck
-- in a loop -- the two look identical on a blanked screen.
--
--   SECS=60 ./run.sh lobby probe

local sp = manager.machine.devices[":maincpu"].spaces["program"]

local Z = {                     -- must match src/lbdefs.inc
    LBSEL = 0xAA, LBIDXS = 0xAB, LBCNT = 0xAC, LBFULL = 0xAD,
    LBPAGE = 0xAE, LBPAGES = 0xAF, LBGT = 0xB0, LBERR = 0xB1,
    LBSTEP = 0xB2, LBENT = 0xB3, LBINP = 0xB5, LBSTG = 0xB9,
}
-- The fetch bank's own cells. Bank-local and aliased, so they only mean this
-- while bank 1 is mapped -- which is exactly when a transport question is
-- being asked.
Z.LBREQ = 0xBB; Z.LBROWS = 0xBC
Z.LBAVL0 = 0xBD; Z.LBAVL1 = 0xBE
Z.LBRXL0 = 0xC1; Z.LBRXL1 = 0xC2
Z.LBMIN0 = 0xC3; Z.LBMIN1 = 0xC4
Z.LBTRIES = 0xC5; Z.LBGOT = 0xC7; Z.LBCHUNK = 0xC8

local ORDER = { "LBENT", "LBERR", "LBSTEP", "LBCNT", "LBGOT", "LBCHUNK",
                "LBROWS", "LBTRIES" }
local WIDE  = { "LBAVL", "LBRXL", "LBMIN" }

local EVERY = tonumber(os.getenv("EVERY") or "60")
local n, last = 0, nil

_G._probe = emu.add_machine_frame_notifier(function()
    n = n + 1
    if n % EVERY ~= 0 then return end
    local out = {}
    for _, k in ipairs(ORDER) do
        out[#out + 1] = string.format("%s=%02X", k, sp:readv_u8(Z[k]))
    end
    for _, k in ipairs(WIDE) do
        out[#out + 1] = string.format("%s=%d", k,
            sp:readv_u8(Z[k .. "0"]) + 256 * sp:readv_u8(Z[k .. "1"]))
    end
    local line = string.format(
        "f%-6d bank=%02X ackseq=%02X status=%02X err=%02X rxlen=%02X%02X "
        .. "magic=%c%c | %s",
        n,
        sp:readv_u8(0x1F0E), sp:readv_u8(0x1F00), sp:readv_u8(0x1F01),
        sp:readv_u8(0x1F02), sp:readv_u8(0x1F05), sp:readv_u8(0x1F04),
        sp:readv_u8(0x1F09), sp:readv_u8(0x1F0A),
        table.concat(out, " "))
    local key = line:sub(line:find("bank"))
    if key ~= last then print(line); last = key end
end)
