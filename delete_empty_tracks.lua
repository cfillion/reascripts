-- delete_empty_tracks.lua v0.1 by Christian Fillion (cfillion)

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()

local track_index, track_count = 0, reaper.CountTracks()
local bucket, bucket_index = {}, 0

while track_index < track_count do
  local track = reaper.GetTrack(0, track_index)

  local fx_count   = reaper.TrackFX_GetCount(track)
  local item_count = reaper.CountTrackMediaItems(track)
  local env_count  = reaper.CountTrackEnvelopes(track)
  local depth      = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
  local is_armed   = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")

  if fx_count + item_count + env_count + math.abs(depth) + is_armed == 0 then
    bucket[bucket_index] = track
    bucket_index = bucket_index + 1
  end

  track_index = track_index + 1
end

if bucket_index > 0 then
  local dialog_btn = reaper.ShowMessageBox(
    string.format("Delete %d empty tracks?", bucket_index),
    "Confirmation", 1
  )

  if dialog_btn == 1 then
    local track_index = 0

    while track_index < bucket_index do
      reaper.DeleteTrack(bucket[track_index])
      track_index = track_index + 1
    end
  end
end

reaper.Undo_EndBlock("Delete Empty Tracks", 1)
reaper.PreventUIRefresh(-1)
