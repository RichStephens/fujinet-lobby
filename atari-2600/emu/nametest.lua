-- nametest.lua -- the keyboard types and the appkey round-trips.
--
-- THE USERNAME APPKEY IS SHARED BY EVERY FUJINET CLIENT ON THE DEVICE --
-- creator 1, app 1, key 0 -- so running this CHANGES something that belongs
-- to the whole machine. It prints the name it found before typing over it, so
-- putting the slot back is a second run with NAME= set to that:
--
--   SECS=120 NAME=VCS   ./run.sh lobby nametest
--   SECS=120 NAME=THOMA ./run.sh lobby nametest
--
-- The cursor position IS the character -- thirty-six cells in three rows of
-- twelve -- so the whole key sequence is arithmetic and can be computed
-- before the machine has run a frame. Nothing here has to watch the screen to
-- know where the cursor is.

local sp   = manager.machine.devices[":maincpu"].spaces["program"]
local joy  = manager.machine.ioport.ports[":joyport1:joy:JOY"]
local swb  = manager.machine.ioport.ports[":SWB"]

local UP, DOWN    = joy.fields["P1 Up"],   joy.fields["P1 Down"]
local LEFT, RIGHT = joy.fields["P1 Left"], joy.fields["P1 Right"]
local FIRE        = joy.fields["P1 Button 1"]
local SEL         = swb.fields["Select Game"]
local RST         = swb.fields["Reset Game"]

local GRID   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local KGRIDW = 12
local NAME   = (os.getenv("NAME") or "VCS"):upper()

local Z    = { LBCNT = 0xAC, LBNLEN = 0xBB, LBKCOL = 0xBC, LBKROW = 0xBD }
local BANK = 0x1F0E

-- ONE is pressed and ZERO is released, for the console switches too.
--
-- SWCHB is active low on the hardware -- INSCAN reads it and treats a CLEAR
-- bit as pressed -- but MAME applies that inversion itself, so a harness that
-- "helpfully" writes 0 to press SELECT is really releasing it, and the 1 it
-- writes to release is really a press that then never ends. The symptom is
-- the good one: everything works once, and then the screen it opened will not
-- close, because the button that opened it is still down.
local function pressed(f) return 1 end
local function idle(f)    return 0 end

-- ---- the script: a flat list of {press = field} and {wait = frames} ----
local script = {}
local function press(f, gap)
    script[#script + 1] = { press = f }
    script[#script + 1] = { wait = gap or 6 }
end
local function wait(n) script[#script + 1] = { wait = n } end
local function check(fn) script[#script + 1] = { check = fn } end

local row, col = 0, 0                   -- where the keyboard starts
local function typechar(ch)
    local i = GRID:find(ch, 1, true)
    if not i then error("no grid cell for '" .. ch .. "'") end
    local wr, wc = (i - 1) // KGRIDW, (i - 1) % KGRIDW
    while row < wr do press(DOWN);  row = row + 1 end
    while row > wr do press(UP);    row = row - 1 end
    while col < wc do press(RIGHT); col = col + 1 end
    while col > wc do press(LEFT);  col = col - 1 end
    press(FIRE)
end

local fails, found = {}, nil

-- The planes cannot be read back as characters, so a row is read as the
-- SHAPES it draws and compared against what a string WOULD look like. At 3x5
-- decoding is lossy and always will be.
package.path = (os.getenv("A2600_FWEMU") or ".") .. "/?.lua;" .. package.path
local okf, vf = pcall(require, "vcsfont")

local function readrow(r)
    if not okf or not vf.glyph then return nil end
    local out = {}
    for c = 0, 11 do
        local key = 0
        for line = 0, 4 do
            local b = sp:readv_u8(0x1800 + (c // 2) * 0x80 + r * 6 + line)
            local nib = (c % 2 == 0) and ((b >> 5) & 7) or ((b >> 1) & 7)
            key = key * 8 + nib
        end
        out[#out + 1] = vf.glyph[key] or "?"
    end
    return (table.concat(out):gsub("%s+$", ""))
end

check(function()
    found = (readrow(19) or ""):gsub("^SEL=", "")
    print("NAMETEST: the slot held '" .. found .. "' before this run")
    if sp:readv_u8(Z.LBCNT) == 0 then
        fails[#fails + 1] = "the list was empty; nothing was under test"
    end
end)

press(SEL, 60)                          -- into the keyboard
check(function()
    if sp:readv_u8(BANK) ~= 2 then
        fails[#fails + 1] = "SELECT did not reach the keyboard bank"
    end
end)

for i = 1, #NAME do typechar(NAME:sub(i, i)) end
wait(20)
check(function()
    local got = sp:readv_u8(Z.LBNLEN)
    if got ~= #NAME then
        fails[#fails + 1] = string.format(
            "typed %d characters and LBNLEN says %d", #NAME, got)
    end
    local shown = readrow(2)
    if shown and shown ~= NAME then
        fails[#fails + 1] = "the value row reads '" .. shown
                            .. "', wanted '" .. NAME .. "'"
    end
end)

press(RST, 1200)                         -- accept: write the appkey, refetch
check(function()
    local r = readrow(19) or ""
    if r ~= "SEL=" .. NAME then
        fails[#fails + 1] = "after accepting, the name row reads '" .. r
                            .. "', wanted 'SEL=" .. NAME .. "'"
    end
    if sp:readv_u8(Z.LBCNT) == 0 then
        fails[#fails + 1] = "the list did not come back after the name change"
    end
end)

-- ---- the driver ----
-- Presses are HELD for several frames. The client scans once per frame in
-- DFRAME, and a press released on the very next frame can fall between two
-- scans -- which looks exactly like a button that does not work.
local HOLD = 4
local n, i, held = 0, 1, nil
_G._nt = emu.add_machine_frame_notifier(function()
    n = n + 1
    if n < 300 then return end          -- let the first list land
    if held then
        held.n = held.n - 1
        if held.n <= 0 then
            held.f:set_value(idle(held.f))
            held = nil
        end
        return
    end
    local job = script[i]
    if not job then return end
    if job.wait then
        job.wait = job.wait - 1
        if job.wait <= 0 then i = i + 1 end
    elseif job.check then
        job.check(); i = i + 1
    else
        job.press:set_value(pressed(job.press))
        held = { f = job.press, n = HOLD }
        i = i + 1
    end
end)

_G._nt_stop = emu.add_machine_stop_notifier(function()
    if i <= #script then
        fails[#fails + 1] = string.format(
            "the script did not finish: %d of %d steps", i, #script)
    end
    if #fails == 0 then
        print("NAMETEST: PASS -- typed '" .. NAME
              .. "', it came back on the list row")
    else
        print("NAMETEST: FAIL")
        for _, f in ipairs(fails) do print("  " .. f) end
    end
    if found and found ~= NAME then
        print("NAMETEST: to put the slot back, run again with NAME=" .. found)
    end
end)
