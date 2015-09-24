-- send_track.lua v0.1 by Christian Fillion (cfillion)

function GetInsertionPoint()
  if g_selectionSize == 0 then
    return reaper.GetNumTracks()
  end

  track = reaper.GetSelectedTrack(0, g_selectionSize - 1)
  return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
end

g_selectionSize = reaper.CountSelectedTracks(0)

if g_selectionSize < 1 then
  return reaper.ShowMessageBox(
    "No tracks are selected.\nSelect at least one track and retry.",
    "send_track.lua by cfillion", 0
  )
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

local insertPos, index = GetInsertionPoint(), 0

reaper.InsertTrackAtIndex(insertPos, true)
local track = reaper.GetTrack(0, insertPos)

while index < g_selectionSize do
  reaper.SNM_AddReceive(track, reaper.GetSelectedTrack(0, index), 0)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_SRCCHAN", true, 0)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_DSTCHAN", true, 0)
  reaper.BR_GetSetTrackSendInfo(
    track, 0, index, "I_MIDI_SRCCHAN", true, -1)

  index = index + 1
end

-- reaper.SetOnlyTrackSelected(track)

reaper.Undo_EndBlock("Create Send Track", 1)

reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
