-- frames.lua -- every frame must be 262 lines.
--
-- The failure this exists for is silent. The seam line is inside a
-- WSYNC-bounded loop, so a seam that runs past cycle 76 does not glitch --
-- the next `sta WSYNC` is already on the following line and waits for the end
-- of THAT one, so the row quietly becomes seven scanlines instead of six. The
-- sibling port shipped exactly that: 142 lines of text, a 278-line frame, a
-- picture that rolls on anything that cares, and nothing on screen that
-- looked wrong.
--
-- Not by counting frames spent in a bank: that measures where the program is,
-- not whether anything is on screen. Not by sampling the screen either --
-- screen:pixel() reads a bitmap MAME updates on its own schedule. What is
-- unambiguous is the program's own VSYNC: tap the write and measure the gap.
--
--   ./run.sh layout frames
--   DRIVE_LUA=emu/drive.lua ./run.sh lobby frames
--
-- BANK 1 IS EXCLUDED. It renders between chunk reads with the picture up, so
-- a frame in which a round trip landed is allowed to be long; every other
-- bank is not. Set STRICT=1 to hold it to 262 as well.

if os.getenv("DRIVE_LUA") then dofile(os.getenv("DRIVE_LUA")) end

local FRAME  = 1 / 59.92
local LINE   = FRAME / 262
local BANKFT = 1                -- BANKFET in src/lbdefs.inc
local STRICT = os.getenv("STRICT") ~= nil
local SETTLE = tonumber(os.getenv("SETTLE") or "30")

local hist = {}
local last, lastbank, n, bad = nil, 0, 0, 0

local sp = manager.machine.devices[":maincpu"].spaces["program"]

local function report()
    local keys = {}
    for k in pairs(hist) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = string.format("%d:%d", k, hist[k])
    end
    print("LINES " .. table.concat(out, " "))
    if n == 0 then
        print("FRAMES: FAIL -- no frames seen at all")
    elseif bad == 0 then
        print(string.format("FRAMES: PASS -- %d frames, every one 262 lines",
                            n))
    else
        print(string.format("FRAMES: FAIL -- %d of %d frames were not 262",
                            bad, n))
    end
end

_G._frames = sp:install_write_tap(0x00, 0x00, "vsync", function(off, data, mask)
    if (data & 0x02) == 0 then return end          -- VSYNC going ON only
    local t = manager.machine.time:as_double()
    local bank = sp:readv_u8(0x1F0E)               -- FN_B_BANK
    if last then
        local gap = t - last
        local lines = math.floor(gap / LINE + 0.5)
        n = n + 1
        hist[lines] = (hist[lines] or 0) + 1
        -- The first frames follow a cold start that has already spent time on
        -- the mailbox, so they are histogrammed but not judged.
        local excused = (not STRICT)
                        and (bank == BANKFT or lastbank == BANKFT)
        if lines ~= 262 and n > SETTLE and not excused then
            bad = bad + 1
            if bad <= 20 then
                print(string.format(
                    "BAD FRAME #%d: %d lines at %.2fs, bank %d -> %d",
                    bad, lines, t, lastbank, bank))
            end
        end
        if n % 600 == 0 then report() end
    end
    last, lastbank = t, bank
end)

_G._frames_stop = emu.add_machine_stop_notifier(function() report() end)
