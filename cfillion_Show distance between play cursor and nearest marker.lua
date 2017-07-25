-- @description Show distance between play cursor and nearest marker
-- @version 0.2
-- @author cfillion

local next_index, offset = 0, nil

local cur_pos = (function()
  if (reaper.GetPlayState() & 1) == 1 then
    return reaper.GetPlayPosition()
  else
    return reaper.GetCursorPosition()
  end
end)()

while true do
  local retval, isregion, pos = reaper.EnumProjectMarkers(next_index)
  next_index = retval
  if next_index == 0 then break end

  if not isregion then
    this_offset = cur_pos - pos
    if not offset or math.abs(this_offset) < math.abs(offset) then
      offset = this_offset
    end
  end
end

if not offset then return end

reaper.ShowConsoleMsg(string.format('Distance between edit/play cursor to nearest marker is %fs.\n', offset))
