-- send_track.lua v0.1 by Christian Fillion (cfillion)

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

local selectionSize = reaper.CountSelectedTracks(0)
local insertPos, index = reaper.GetNumTracks(), 0
reaper.InsertTrackAtIndex(insertPos, true)
local track = reaper.GetTrack(0, insertPos)

while index < selectionSize do
  reaper.SNM_AddReceive(track, reaper.GetSelectedTrack(0, index), 0)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_SRCCHAN", true, 0)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_DSTCHAN", true, 0)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_MIDI_SRCCHAN", true, -1)

  index = index + 1
end

reaper.SetOnlyTrackSelected(track)

reaper.Undo_EndBlock("Create Send Track", 1)

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
