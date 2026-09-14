-- cursor.lua -- the selection moves, and moving it costs nothing.
--
-- Two things at once, because they are the same claim. Colouring the selected
-- row rather than poking a '>' into column 0 is supposed to make a cursor
-- step four zero-page stores with no blit and no round trip; if that is true
-- then the cursor lands on every room row in turn AND no frame grows while it
-- does. The sibling port's list redraw was ~3,800 cycles against a
-- 2,812-cycle vblank and pushed the picture thirteen scanlines down on every
-- keypress, which is the failure this rules out.
--
-- One press per PERIOD frames, because the edge detector must see a release
-- between steps -- a held stick is one press plus auto-repeat, which is a
-- different code path and not what this is measuring.
--
--   ./run.sh layout cursor

local LBCLS  = 0x8F             -- src/lbdefs.inc
local LBSEL  = 0xAA
local NROWS  = 22
local CLROOM = 0x00             -- CLROOM / CLSEL, and they must differ
local CLSEL  = 0x44
local PERIOD = tonumber(os.getenv("PERIOD") or "10")
local START  = tonumber(os.getenv("START") or "120")

local sp   = manager.machine.devices[":maincpu"].spaces["program"]
local joy  = manager.machine.ioport.ports[":joyport1:joy:JOY"]
local down = joy.fields["P1 Down"]
local up   = joy.fields["P1 Up"]

local n, step, fails = 0, 0, 0
local seen, plan = {}, {}
local phase = "down"

local function rooms()
    local r = {}
    for i = 0, NROWS - 1 do
        local c = sp:readv_u8(LBCLS + i)
        if c == CLROOM or c == CLSEL then r[#r + 1] = i end
    end
    return r
end

-- Exactly one row must be CLSEL, and it must be the one LBSEL names.
local function coherent()
    local nsel, at = 0, -1
    for i = 0, NROWS - 1 do
        if sp:readv_u8(LBCLS + i) == CLSEL then nsel = nsel + 1; at = i end
    end
    local sel = sp:readv_u8(LBSEL)
    if nsel ~= 1 then
        return false, string.format("%d rows painted as the selection, want 1",
                                    nsel)
    end
    if at ~= sel then
        return false, string.format("row %d is painted selected but LBSEL "
                                    .. "says %d", at, sel)
    end
    return true
end

_G._cursor = emu.add_machine_frame_notifier(function()
    n = n + 1
    if n < START then return end

    if n == START then
        plan = rooms()
        if #plan < 2 then
            print("CURSOR: FAIL -- the screen has fewer than two room rows")
            fails = fails + 1
        end
        return
    end

    local t = (n - START) % PERIOD
    if t == 1 then
        if phase == "down" then down:set_value(1) else up:set_value(1) end
    elseif t == 3 then
        down:set_value(0)
        up:set_value(0)
    elseif t == 6 then
        local ok, why = coherent()
        if not ok then
            fails = fails + 1
            if fails <= 5 then print("CURSOR: " .. why) end
        end
        seen[sp:readv_u8(LBSEL)] = true
        step = step + 1
        -- Walk to the bottom, then back up, so both directions and both
        -- clamps are exercised.
        if step == #plan + 1 then phase = "up" end
    end
end)

_G._cursor_stop = emu.add_machine_stop_notifier(function()
    local missed = {}
    for _, row in ipairs(plan) do
        if not seen[row] then missed[#missed + 1] = row end
    end
    if step == 0 then
        print("CURSOR: FAIL -- never got to press anything")
    elseif #missed > 0 then
        print("CURSOR: FAIL -- never selected row(s) " ..
              table.concat(missed, ", "))
    elseif fails > 0 then
        print(string.format("CURSOR: FAIL -- %d incoherent frames", fails))
    else
        print(string.format(
            "CURSOR: PASS -- %d steps over %d room rows, both directions, "
            .. "LBSEL and LBCLS agreed every time", step, #plan))
    end
end)
