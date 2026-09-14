-- colours.lua -- the seam line actually paints what LBCLS says.
--
-- This is the test for the one thing this port does that no sibling does:
-- a background colour per row, written on the blank sixth scanline of each
-- text cell out of a table in zero page.
--
-- Not by looking at a screenshot. Every wrong kernel constant still looks
-- like text, and every wrong colour still looks like colour -- a table that
-- went stale across a bank switch draws a perfectly convincing screen of the
-- PREVIOUS screen's bands. What is unambiguous is the program's own stores:
-- tap COLUBK, collect the writes between one VSYNC and the next, and compare
-- them against LBCLS read out of RAM.
--
-- A frame must be exactly twenty-two writes: DPADA hands row 0 its colour
-- before the kernel starts, then each of the twenty-one seam lines programmes
-- the row below it, the last of them programming row 21, which does not exist
-- and is what hands the picture back to the bottom band.
--
--   ./run.sh layout colours
--   DRIVE_LUA=emu/drive.lua ./run.sh lobby colours

if os.getenv("DRIVE_LUA") then dofile(os.getenv("DRIVE_LUA")) end

local LBCLS  = 0x8F             -- must match src/lbdefs.inc
local NROWS  = 22               -- LBCLSN: 21 rows plus the handover entry
local SETTLE = tonumber(os.getenv("SETTLE") or "60")

local sp = manager.machine.devices[":maincpu"].spaces["program"]

local writes  = {}
local frames, checked, bad = 0, 0, 0
local firstbad = nil

local function classtable()
    local t = {}
    for i = 0, NROWS - 1 do t[i + 1] = sp:readv_u8(LBCLS + i) end
    return t
end

local function fmt(t, n)
    local out = {}
    for i = 1, (n or #t) do out[#out + 1] = string.format("%02X", t[i] or 0) end
    return table.concat(out, " ")
end

-- COLUBK is $09. install_write_tap over the TIA range as a whole does not
-- fire, but the single-address form does -- which is what blank.lua in the
-- sibling port relies on too.
_G._colubk = sp:install_write_tap(0x09, 0x09, "colubk", function(off, data, mask)
    writes[#writes + 1] = data
end)

_G._vsync = sp:install_write_tap(0x00, 0x00, "vsync", function(off, data, mask)
    if (data & 0x02) == 0 then return end          -- VSYNC going ON only
    local got = writes
    writes = {}
    frames = frames + 1
    if frames <= SETTLE then return end            -- let the screen settle

    -- The table is read AFTER the frame it described, which is safe because
    -- nothing writes LBCLS during the picture: the cursor moves in APPVBL,
    -- inside the blanked band, and a bank switch happens there too.
    local want = classtable()
    checked = checked + 1

    if #got ~= NROWS then
        bad = bad + 1
        if not firstbad then
            firstbad = string.format(
                "frame %d wrote COLUBK %d times, want %d -- a seam line that "
                .. "overran costs a whole scanline and drops a write",
                frames, #got, NROWS)
        end
        return
    end
    for i = 1, NROWS do
        if got[i] ~= want[i] then
            bad = bad + 1
            if not firstbad then
                firstbad = string.format(
                    "frame %d row %d: painted %02X, LBCLS says %02X\n"
                    .. "  painted %s\n  LBCLS   %s",
                    frames, i - 1, got[i], want[i], fmt(got), fmt(want))
            end
            return
        end
    end
end)

_G._colours_stop = emu.add_machine_stop_notifier(function()
    if checked == 0 then
        print("COLOURS: FAIL -- no frames checked; did the kernel ever run?")
    elseif bad == 0 then
        print(string.format(
            "COLOURS: PASS -- %d frames, %d COLUBK writes each, every one "
            .. "equal to LBCLS", checked, NROWS))
    else
        print(string.format("COLOURS: FAIL -- %d of %d frames disagreed",
                            bad, checked))
        print("  " .. firstbad)
    end
end)
