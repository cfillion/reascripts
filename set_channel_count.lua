local tracks = reaper.CountSelectedTracks(0)

if tracks == 0 then
  reaper.ShowMessageBox("Select some tracks and retry.", "Selection is empty!", 0)
  return
end

local ok, channels = reaper.GetUserInputs("Set Channel Count", 1, "Channel count for selected tracks:", "2")
channels = tonumber(channels)

if ok == false or channels == nil then
  return
elseif channels % 2 ~= 0 then
  channels = channels + 1
end

channels = math.max(2, math.min(channels, 64))

for index=0,tracks-1 do
  local track = reaper.GetSelectedTrack(0, index)
  reaper.SetMediaTrackInfo_Value(track, "I_NCHAN", channels)
end
