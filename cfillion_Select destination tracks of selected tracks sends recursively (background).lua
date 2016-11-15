-- @description Select destination tracks of selected tracks sends recursively (background)
-- @version 1.0
-- @author cfillion
-- @link Forum Thread http://forum.cockos.com/showthread.php?t=183638

local selected = {}

local function wasSelected(match)
  for i,track in ipairs(selected) do
    if track == match then
      return true
    end
  end

  return false
end

local function highlight(track, select)
  for i=0,reaper.GetTrackNumSends(track, 0)-1 do
    local target = reaper.BR_GetMediaTrackSendInfo_Track(track, 0, i, 1)

    reaper.SetTrackSelected(target, select)

    if select then
      highlight(target, select)
    end
  end
end

local function main()
  for i,track in ipairs(selected) do
    local valid = reaper.ValidatePtr(track, 'MediaTrack*')
    local isSelected = valid and reaper.IsTrackSelected(track)

    if not isSelected then
      table.remove(selected, i)

      if valid then
        highlight(track, false)
      end
    end
  end

  for i=0,reaper.CountSelectedTracks(0)-1 do
    local track = reaper.GetSelectedTrack(0, i)

    if wasSelected(track) then
      highlight(track, true)
    else
      selected[#selected + 1] = track
    end
  end

  reaper.defer(main)
end

main()
