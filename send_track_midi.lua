-- send_track_midi.lua v0.1 by Christian Fillion (cfillion)
-- https://forum.cockos.com/showpost.php?p=1580440

local selectionSize = reaper.CountSelectedTracks(0)

if selectionSize < 1 then
  reaper.Main_OnCommand(40001, 0) -- Track: Insert new track
  return
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

local insertPos, index = reaper.GetNumTracks(), 0
reaper.InsertTrackAtIndex(insertPos, true)
local track = reaper.GetTrack(0, insertPos)

while index < selectionSize do
  reaper.SNM_AddReceive(track, reaper.GetSelectedTrack(0, index), 0)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_SRCCHAN", true, -1)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_MIDI_SRCCHAN", true, 0)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_MIDI_DSTCHAN", true, 0)

  index = index + 1
end

reaper.SetOnlyTrackSelected(track)

reaper.Undo_EndBlock("Create MIDI Send Track", 1)

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
