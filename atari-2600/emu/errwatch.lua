-- errwatch.lua -- snapshot the transport AT THE INSTANT a failure is recorded.
--
-- Sampling LBERR once a frame is a frame too late: by then the failed request
-- has been closed and the next one has already overwritten LBREQ, so the
-- report names the wrong request. Tapping the store catches the state that
-- actually explains it.
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local function u16(lo) return sp:readv_u8(lo) + 256 * sp:readv_u8(lo + 1) end
local n = 0
_G._ew = sp:install_write_tap(0xB1, 0xB1, "lberr", function(off, data, mask)
  if data == 0 then return end
  n = n + 1
  if n > 8 then return end
  print(string.format(
    "FAIL#%d err=%02X req=%02X | avail=%d min=%d rxlen=%d got=%02X chunk=%02X "
    .. "tries=%02X page=%02X | ackseq=%02X rcmd=%02X carterr=%02X",
    n, data, sp:readv_u8(0xBB), u16(0xBD), u16(0xC3), u16(0xC1),
    sp:readv_u8(0xC7), sp:readv_u8(0xC8), sp:readv_u8(0xC5), sp:readv_u8(0xAE),
    sp:readv_u8(0x1F00), sp:readv_u8(0x1F03), sp:readv_u8(0x1F02)))
end)
