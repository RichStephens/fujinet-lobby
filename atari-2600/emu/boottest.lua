-- boottest.lua -- FIRE on a room really boots the game behind it.
--
-- The whole handoff, end to end: re-fetch the record, split its client_url,
-- claim the last host slot, mount the host, write the room's own URL into the
-- appkey the booted game reads, set the device path, MOUNT_IMAGE, and swap.
--
-- THE PROOF THAT IT BOOTED IS THAT THE CLAIM GOES AWAY. An image carrying
-- "FUJI" at FN_R_CLAIM promises it is a FujiNet client and the mailbox stays
-- live; an ordinary game carries no such promise and the cartridge stops
-- decoding for the rest of the session. So when those four bytes stop reading
-- "FUJI", something that is not this client is running -- which is exactly
-- what booting a game means.
--
--   ROOM=BOOTME SECS=180 ./run.sh lobby boottest
--
-- Point ROOM at a room whose client_url is a real image the FujiNet can
-- reach. A room on the fujinet's own SD host is the honest choice: it boots
-- for real and it rewrites the last host slot with the name that was already
-- in it.

local sp   = manager.machine.devices[":maincpu"].spaces["program"]
local joy  = manager.machine.ioport.ports[":joyport1:joy:JOY"]
local DOWN = joy.fields["P1 Down"]
local FIRE = joy.fields["P1 Button 1"]

local ROOM   = os.getenv("ROOM") or "BOOTME"
local LBCLS  = 0x8F
local CLROOM, CLSEL = 0x00, 0x44
local RLIST0, RLISTN = 1, 18
local BANK, CLAIM = 0x1F0E, 0x1F10

package.path = (os.getenv("A2600_FWEMU") or ".") .. "/?.lua;" .. package.path
local okf, vf = pcall(require, "vcsfont")

local function readrow(r)
    if not okf or not vf.glyph then return "" end
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
    return table.concat(out)
end

local function claimed()
    return string.char(sp:readv_u8(CLAIM), sp:readv_u8(CLAIM + 1),
                       sp:readv_u8(CLAIM + 2), sp:readv_u8(CLAIM + 3))
end

local n, phase, mark, steps, seen = 0, "settle", 0, 0, {}
local fails = {}

_G._bt = emu.add_machine_frame_notifier(function()
    n = n + 1
    seen[sp:readv_u8(BANK)] = true

    if phase == "settle" then
        if n > 400 and sp:readv_u8(BANK) == 0 and sp:readv_u8(0xAC) ~= 0 then
            -- Count the room rows before the one wanted. The colour table is
            -- the only record of which rows are rooms, which is the same
            -- thing the client's own cursor walks.
            local idx, want = 0, nil
            for r = RLIST0, RLISTN do
                local c = sp:readv_u8(LBCLS + r)
                if c == CLROOM or c == CLSEL then
                    if readrow(r):find(ROOM, 1, true) then want = idx end
                    idx = idx + 1
                end
            end
            if not want then
                fails[#fails + 1] = "no room called '" .. ROOM
                                    .. "' on the first page"
                phase = "done"
                return
            end
            print(string.format("BOOTTEST: '%s' is room %d of %d",
                                ROOM, want, idx))
            steps, phase, mark = want, "walk", n
        end
    elseif phase == "walk" then
        local t = (n - mark) % 12
        if steps > 0 then
            if t == 1 then DOWN:set_value(1)
            elseif t == 5 then DOWN:set_value(0); steps = steps - 1 end
        else
            local got = readrow(sp:readv_u8(0xAA))
            if not got:find(ROOM, 1, true) then
                fails[#fails + 1] = "the cursor landed on '" .. got
                                    .. "', wanted " .. ROOM
            end
            print("BOOTTEST: firing on '" .. got .. "'")
            FIRE:set_value(1)
            phase, mark = "fired", n
        end
    elseif phase == "fired" then
        if n == mark + 6 then FIRE:set_value(0) end
        if claimed() ~= "FUJI" then
            print(string.format("BOOTTEST: the claim went away at frame %d "
                  .. "-- a game is running", n))
            phase = "done"
        elseif n > mark + 9000 then
            fails[#fails + 1] = "the claim was still 'FUJI' after 150 seconds"
                                .. " -- nothing booted"
            phase = "done"
        end
    end
end)

_G._bt_stop = emu.add_machine_stop_notifier(function()
    local banks = {}
    for b = 0, 6 do if seen[b] then banks[#banks + 1] = b end end
    print("BOOTTEST: banks visited: " .. table.concat(banks, " "))
    if not seen[3] then fails[#fails + 1] = "the prep bank never ran" end
    if not seen[4] then fails[#fails + 1] = "the boot bank never ran" end
    if #fails == 0 then
        print("BOOTTEST: PASS -- the room booted")
    else
        print("BOOTTEST: FAIL")
        for _, f in ipairs(fails) do print("  " .. f) end
    end
end)
