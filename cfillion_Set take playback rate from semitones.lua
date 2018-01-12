-- @description Set take playback rate from semitones
-- @version 1.0
-- @author cfillion
-- @links
--   cfillion.ca https://cfillion.ca/
--   Request Thread https://forum.cockos.com/showthread.php?t=201842
-- @donate https://www.paypal.com/cgi-bin/webscr?business=T3DEWBQJAV7WL&cmd=_donations&currency_code=CAD&item_name=ReaScript%3A+Set+take+playback+rate+from+semitones
-- @about
--   # Set take playback rate from semitones
--
--   This script sets the playback rate of selected takes from semitones input
--   without preserving pitch.

local UNDO_STATE_ITEMS = 4

function rate2pitch(mul)
  return 12 * math.log(mul, 2)
end

function pitch2rate(semitones)
  return 2 ^ (semitones / 12)
end

function currentSemitones()
  local item = reaper.GetSelectedMediaItem(0, 0)
  local take = reaper.GetActiveTake(item)
  local rate = reaper.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')

  return tostring(rate2pitch(rate))
end

if reaper.CountSelectedMediaItems() < 1 then
  reaper.defer(function() end)
  return
end

local script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local retval, csv = reaper.GetUserInputs(script_name, 1, 'Semitones:', currentSemitones())
local semitones = tonumber(csv)

if not retval or not semitones then
  reaper.defer(function() end)
  return
end

local rate = pitch2rate(semitones)

reaper.Undo_BeginBlock()

for i=0, reaper.CountSelectedMediaItems() - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local take = reaper.GetActiveTake(item)
  
  reaper.SetMediaItemTakeInfo_Value(take, 'D_PLAYRATE', rate)
  reaper.SetMediaItemTakeInfo_Value(take, 'B_PPITCH', 0)
end

reaper.Undo_EndBlock(script_name, UNDO_STATE_ITEMS)
reaper.UpdateArrange()
