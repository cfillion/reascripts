-- Already exists in SWS: Xenakios/SWS: Select items to end of track

function select_items(cmpCallback)
  local targetItems = {}

  for si=0,reaper.CountSelectedMediaItems(0)-1 do
    local selectedItem = reaper.GetSelectedMediaItem(0, si)
    local track = reaper.GetMediaItemTrack(selectedItem)
    local selectedPos = get_item_pos(selectedItem)

    for i=0,reaper.CountTrackMediaItems(track)-1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local itemPos = get_item_pos(item)

      if cmpCallback(selectedPos, itemPos) then
        targetItems[#targetItems + 1] = item
      end
    end
  end

  for _,item in ipairs(targetItems) do
    reaper.SetMediaItemSelected(item, true)
  end
end

function get_item_pos(item)
  local start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  return {item_start=start, item_end=start + length}
end

reaper.Undo_BeginBlock()

select_items(function(selectedPos, targetPos)
  return targetPos.item_end < selectedPos.item_start
end)

reaper.UpdateArrange()
reaper.Undo_EndBlock("Select items to the left of selected item", 1)
