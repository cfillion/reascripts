dofile(reaper.GetResourcePath() ..
       '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.7')

local SCRIPT_NAME = 'Song switcher'

local EXT_SECTION     = 'cfillion_song_switcher'
local EXT_SWITCH_MODE = 'onswitch'
local EXT_LAST_DOCK   = 'last_dock'
local EXT_STATE       = 'state'

local FLT_MIN, FLT_MAX = reaper.ImGui_NumericLimits_Float()

local SWITCH_SEEK   = 1<<0
local SWITCH_STOP   = 1<<1
local SWITCH_SCROLL = 1<<2

local UNDO_STATE_TRACKCFG = 1

dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.7')

local scrollTo, setDock
-- initialized in reset()
local currentIndex, nextIndex, invalid, filterPrompt

local fonts = {
  small = reaper.ImGui_CreateFont('sans-serif', 13),
  large = reaper.ImGui_CreateFont('sans-serif', 28),
  huge  = reaper.ImGui_CreateFont('sans-serif', 38),
}

local ctx = reaper.ImGui_CreateContext(SCRIPT_NAME, reaper.ImGui_ConfigFlags_DockingEnable())

for key, font in pairs(fonts) do
  reaper.ImGui_AttachFont(ctx, font)
end

local function parseSongName(trackName)
  local number, separator, name = string.match(trackName, '^(%d+)(%W+)(.+)$')
  number = tonumber(number)

  if number and separator and name then
    return {number=number, separator=separator, name=name}
  end
end

local function compareSongs(a, b)
  local aparts, bparts = parseSongName(a.name), parseSongName(b.name)

  if aparts.number == bparts.number then
    return aparts.name < bparts.name
  else
    return aparts.number < bparts.number
  end
end

local function loadTracks()
  local songs = {}
  local depth = 0
  local isSong = false

  for index=0,reaper.GetNumTracks()-1 do
    local track = reaper.GetTrack(0, index)

    local track_depth = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')

    if depth == 0 and track_depth == 1 then
      local _, name = reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)

      if parseSongName(name) then
        isSong = true
        table.insert(songs, {name=name, folder=track, tracks={track}, uniqId=#songs})
      else
        isSong = false
      end
    elseif depth >= 1 and isSong then
      local song = songs[#songs]
      song.tracks[#song.tracks + 1] = track

      for itemIndex=0,reaper.CountTrackMediaItems(track)-1 do
        local item = reaper.GetTrackMediaItem(track, itemIndex)
        local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local endTime = pos + reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')

        if not song.startTime or song.startTime > pos then
          song.startTime = pos
        end
        if not song.endTime or song.endTime < endTime then
          song.endTime = endTime
        end
      end
    end

    depth = depth + track_depth
  end

  for _,song in ipairs(songs) do
    if not song.startTime then song.startTime = 0 end
    if not song.endTime then song.endTime = reaper.GetProjectLength() end
  end

  table.sort(songs, compareSongs)
  return songs
end

local function isSongValid(song)
  for _,track in ipairs(song.tracks) do
    if not reaper.ValidatePtr(track, 'MediaTrack*') then
      return false
    end
  end

  return true
end

local function setSongEnabled(song, enabled)
  if song == nil then return end

  invalid = not isSongValid(song)
  if invalid then return false end

  local on, off = 1, 0

  if not enabled then
    on, off = 0, 1
  end

  reaper.SetMediaTrackInfo_Value(song.folder, 'B_MUTE', off)

  for _,track in ipairs(song.tracks) do
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', on)
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', on)
  end

  return true
end

local function updateState()
  local song = songs[currentIndex] or {name='', startTime=0, endTime=0}

  local state = string.format("%d\t%d\t%s\t%f\t%f\t%s",
    currentIndex, #songs, song.name, song.startTime, song.endTime,
    tostring(invalid)
  )
  reaper.SetExtState(EXT_SECTION, EXT_STATE, state, false)
end

local function getSwitchMode()
  local mode = tonumber(reaper.GetExtState(EXT_SECTION, EXT_SWITCH_MODE))
  return mode and mode or 0
end

local function setSwitchMode(mode)
  reaper.SetExtState(EXT_SECTION, EXT_SWITCH_MODE, tostring(mode), true)
end

local function setNextIndex(index)
  if songs[index] then
    nextIndex = index
    scrollTo = index
    highlightTime = reaper.ImGui_GetTime(ctx)
  end
end

local function setCurrentIndex(index)
  reaper.PreventUIRefresh(1)

  if currentIndex < 1 then
    for _,song in ipairs(songs) do
      setSongEnabled(song, false)
    end
  elseif index ~= currentIndex then
    setSongEnabled(songs[currentIndex], false)
  end

  local mode = getSwitchMode()

  if mode & SWITCH_STOP ~= 0 then
    reaper.CSurf_OnStop()
  end

  local song = songs[index]
  local disableOk = not invalid
  local enableOk = setSongEnabled(song, true)

  if enableOk or disableOk then
    currentIndex = index
    setNextIndex(index)

    if mode & SWITCH_SEEK ~= 0 then
      reaper.SetEditCurPos(song.startTime, true, true)
    end

    if mode & SWITCH_SCROLL ~= 0 then
      reaper.GetSet_ArrangeView2(0, true, 0, 0, song.startTime, song.endTime + 5)
    end
  end

  reaper.PreventUIRefresh(-1)

  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()

  filterPrompt = false
  updateState()
end

local function trySetCurrentIndex(index)
  if songs[index] then
    setCurrentIndex(index)
  end
end

local function moveSong(from, to)
  local target = songs[from]
  songs[from] = songs[to]
  songs[to]   = target

  if currentIndex == from then
    currentIndex = to
  elseif to <= currentIndex and from > currentIndex then
    currentIndex = currentIndex + 1
  elseif from < currentIndex and to >= currentIndex then
    currentIndex = currentIndex - 1
  end

  if nextIndex == from then
    nextIndex = to
  elseif to <= nextIndex and from > nextIndex then
    nextIndex = nextIndex + 1
  elseif from < nextIndex and to >= nextIndex then
    nextIndex = nextIndex - 1
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local maxNumLength = math.max(2, tostring(#songs):len())
  for index, song in ipairs(songs) do
    local nameParts = parseSongName(song.name)
    local newName = string.format('%0' .. maxNumLength .. 'd%s%s',
      index, nameParts.separator, nameParts.name)
    song.name = newName

    if reaper.ValidatePtr(song.folder, 'MediaTrack*') then
      reaper.GetSetMediaTrackInfo_String(song.folder, 'P_NAME', newName, true)
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock('Song switcher: Change song order', UNDO_STATE_TRACKCFG)
end

local function findSong(buffer)
  if string.len(buffer) == 0 then return end
  buffer = string.upper(buffer)

  local index = 0
  local song = songs[index]

  for index, song in ipairs(songs) do
    local name = string.upper(song.name)

    if string.find(name, buffer, 0, true) ~= nil then
      return index, song
    end
  end
end

local SIGNALS = {
  relative_move=function(move)
    move = tonumber(move)

    if move then
      trySetCurrentIndex(currentIndex + move)
    end
  end,
  absolute_move=function(index)
    trySetCurrentIndex(tonumber(index))
  end,
  activate_queued=function()
    if currentIndex ~= nextIndex then
      setCurrentIndex(nextIndex)
    end
  end,
  filter=function(filter)
    local index = findSong(filter)

    if index then
      setCurrentIndex(index)
    end
  end,
  reset=function() reset() end,
}

local function reset()
  songs = loadTracks()

  local activeIndex, activeCount, visibleCount = nil, 0, 0

  for index,song in ipairs(songs) do
    local muted = reaper.GetMediaTrackInfo_Value(song.folder, 'B_MUTE')

    if muted == 0 then
      if activeIndex == nil then
        activeIndex = index
      end

      activeCount = activeCount + 1
    end

    if activeIndex ~= index then
      for _,track in ipairs(song.tracks) do
        local tcp = reaper.GetMediaTrackInfo_Value(track, 'B_SHOWINTCP')
        local mixer = reaper.GetMediaTrackInfo_Value(track, 'B_SHOWINMIXER')

        if tcp == 1 or mixer == 1 then
          visibleCount = visibleCount + 1
        end
      end
    end
  end

  filterPrompt, invalid = false, false
  currentIndex, nextIndex, scrollTo = 0, 0, 0
  highlightTime = reaper.ImGui_GetTime(ctx)

  -- clear previous pending external commands
  for signal, _ in pairs(SIGNALS) do
    reaper.DeleteExtState(EXT_SECTION, signal, false)
  end

  if activeCount == 1 then
    if visibleCount == 0 then
      currentIndex = activeIndex
      nextIndex = activeIndex
      scrollTo = activeIndex

      updateState()
    else
      setCurrentIndex(activeIndex)
    end
  else
    updateState()
  end
end

local function execRemoteActions()
  for signal, handler in pairs(SIGNALS) do
    if reaper.HasExtState(EXT_SECTION, signal) then
      local value = reaper.GetExtState(EXT_SECTION, signal)
      reaper.DeleteExtState(EXT_SECTION, signal, false);
      handler(value)
    end
  end
end

function drawName(song)
  local name = song and song.name or 'No song selected'

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),
    reaper.ImGui_GetStyleColor(ctx, (song and reaper.ImGui_Col_Text or reaper.ImGui_Col_TextDisabled)()))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), invalid and 0xff0000ff or 0)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x323232ff)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  0x3232327f)
  if reaper.ImGui_Button(ctx, ('%s###song_name'):format(name), -FLT_MIN) then
    filterPrompt = true
  end
  reaper.ImGui_PopStyleColor(ctx, 4)
end

local function drawFilter()
  reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
  reaper.ImGui_SetKeyboardFocusHere(ctx)
  local rv, filter = reaper.ImGui_InputText(ctx, '##name_fiter', '', reaper.ImGui_InputTextFlags_EnterReturnsTrue())
  if reaper.ImGui_IsItemDeactivated(ctx) then
    filterPrompt = false
  end
  if rv then
    local index, _ = findSong(filter)

    if index then
      setCurrentIndex(index)
    end
  end
end

local function formatTime(time)
  return reaper.format_timestr(time, '')
end

local function songList(y)
  local flags = reaper.ImGui_TableFlags_Borders()   |
                reaper.ImGui_TableFlags_RowBg()     |
                reaper.ImGui_TableFlags_ScrollY()   |
                reaper.ImGui_TableFlags_Hideable()  |
                reaper.ImGui_TableFlags_Resizable() |
                reaper.ImGui_TableFlags_Reorderable()
  if not reaper.ImGui_BeginTable(ctx, 'song_list', 4, flags, -FLT_MIN, -FLT_MIN) then return end

  reaper.ImGui_TableSetupColumn(ctx, '#. Name',   reaper.ImGui_TableColumnFlags_WidthStretch())
  reaper.ImGui_TableSetupColumn(ctx, 'Start',  reaper.ImGui_TableColumnFlags_WidthFixed())
  reaper.ImGui_TableSetupColumn(ctx, 'End',    reaper.ImGui_TableColumnFlags_WidthFixed())
  reaper.ImGui_TableSetupColumn(ctx, 'Length', reaper.ImGui_TableColumnFlags_WidthFixed())
  reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
  reaper.ImGui_TableHeadersRow(ctx)

  local swap
  for index, song in ipairs(songs) do
    reaper.ImGui_TableNextRow(ctx)

    reaper.ImGui_TableNextColumn(ctx)
    local color = reaper.ImGui_GetStyleColor(ctx, reaper.ImGui_Col_Header())
    local isCurrent, isNext = index == currentIndex, index == nextIndex
    if isNext and not isCurrent then
      -- swap blue <-> green
      color = (color & 0xFF0000FF) | (color & 0x00FF0000) >> 8 | (color & 0x0000FF00) << 8
      if (math.floor(highlightTime - reaper.ImGui_GetTime(ctx)) & 1) == 0 then
        color = (color & ~0xff) | 0x1a
      end
    end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), color)
    if reaper.ImGui_Selectable(ctx, ('%s###%d'):format(song.name, song.uniqId),
        isCurrent or isNext,
        reaper.ImGui_SelectableFlags_SpanAllColumns()) then
      setCurrentIndex(index)
    end
    if reaper.ImGui_IsItemActive(ctx) and not reaper.ImGui_IsItemHovered(ctx) then
      local mouseDelta = select(2, reaper.ImGui_GetMouseDragDelta(ctx, reaper.ImGui_MouseButton_Left()))
      local newIndex = index + (mouseDelta < 0 and -1 or 1)
      if newIndex > 0 and newIndex <= #songs then
        swap = { from=index, to=newIndex }
        reaper.ImGui_ResetMouseDragDelta(ctx, reaper.ImGui_MouseButton_Left())
      end
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, formatTime(song.startTime))

    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, formatTime(song.endTime))

    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, formatTime(song.endTime - song.startTime))

    if index == scrollTo then
      reaper.ImGui_SetScrollHereY(ctx, 1)
    end
  end

  reaper.ImGui_EndTable(ctx)
  scrollTo = nil

  if swap then
    moveSong(swap.from, swap.to)
  end
end

local function switchModeMenu()
  local mode = getSwitchMode()
  if reaper.ImGui_MenuItem(ctx, 'Stop playback', nil, mode & SWITCH_STOP ~= 0) then
    setSwitchMode(mode ~ SWITCH_STOP)
  end
  if reaper.ImGui_MenuItem(ctx, 'Seek to first item', nil, mode & SWITCH_SEEK ~= 0) then
    setSwitchMode(mode ~ SWITCH_SEEK)
  end
  if reaper.ImGui_MenuItem(ctx, 'Scroll to first item', nil, mode & SWITCH_SCROLL ~= 0) then
    setSwitchMode(mode ~ SWITCH_SCROLL)
  end
end

local function switchModeButton()
  reaper.ImGui_SmallButton(ctx, 'onswitch')
  if reaper.ImGui_BeginPopupContextItem(ctx, 'onswitch_menu', reaper.ImGui_PopupFlags_MouseButtonLeft()) then
    switchModeMenu()
    reaper.ImGui_EndPopup(ctx)
  end
end

local function toggleDock(dockId)
  dockId = dockId or reaper.ImGui_GetWindowDockID(ctx)
  if dockId == 0 then
    local lastDock = tonumber(reaper.GetExtState(EXT_SECTION, EXT_LAST_DOCK))
    if not lastDock or lastDock < 0 or lastDock > 16 then lastDock = 0 end
    setDock = ~lastDock
  else
    reaper.SetExtState(EXT_SECTION, EXT_LAST_DOCK, tostring(~dockId), true)
    setDock = 0
  end
end

local function contextMenu()
  local dockId = reaper.ImGui_GetWindowDockID(ctx)
  if not reaper.ImGui_BeginPopupContextWindow(ctx, 'context_menu') then return end

  if reaper.ImGui_MenuItem(ctx, 'Dock window', nil, dockId ~= 0) then
    toggleDock(dockId)
  end
  if reaper.ImGui_MenuItem(ctx, 'Reset data') then
    reset()
  end
  if reaper.ImGui_BeginMenu(ctx, 'When switching to a song...') then
    switchModeMenu()
    reaper.ImGui_EndMenu(ctx)
  end
  reaper.ImGui_Separator(ctx)
  if #songs > 0 then
    for index, song in ipairs(songs) do
      if reaper.ImGui_MenuItem(ctx, song.name, nil, index == currentIndex) then
        setCurrentIndex(index)
      end
    end
    reaper.ImGui_Separator(ctx)
  end
  if reaper.ImGui_MenuItem(ctx, 'Help') then
    about()
  end

  reaper.ImGui_EndPopup(ctx)
end

function about()
  local owner = reaper.ReaPack_GetOwner((select(2, reaper.get_action_context())))
  if owner then
    reaper.ReaPack_AboutInstalledPackage(owner)
    reaper.ReaPack_FreeEntry(owner)
  else
    reaper.ShowMessageBox('Song switcher must be installed through ReaPack to use this feature.', SCRIPT_NAME, 0)
  end
end

local function navButtons(size)
  local pad_x, pad_y = 8, 8
  local dl = reaper.ImGui_GetWindowDrawList(ctx)

  local col_text   = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_Text())
  local col_hover  = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_ButtonHovered())
  local col_active = reaper.ImGui_GetColor(ctx, reaper.ImGui_Col_ButtonActive())

  local function btn(isPrev)
    reaper.ImGui_TableSetColumnIndex(ctx, isPrev and 0 or 2)

    if reaper.ImGui_InvisibleButton(ctx, isPrev and 'prev' or 'next', size, size) then
      setCurrentIndex(currentIndex + (isPrev and -1 or 1))
    end

    local color = reaper.ImGui_IsItemActive(ctx)  and col_active
               or reaper.ImGui_IsItemHovered(ctx) and col_hover
               or col_text

    local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
    local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
    local mid_y = min_y + ((max_y - min_y) / 2)
    min_x, min_y = min_x + pad_x, min_y + pad_y
    max_x, max_y = max_x - pad_x, max_y - pad_y

    if isPrev then
      reaper.ImGui_DrawList_AddTriangleFilled(dl,
        min_x, mid_y, max_x, min_y, max_x, max_y, color)
    else
      reaper.ImGui_DrawList_AddTriangleFilled(dl,
        min_x, min_y, max_x, mid_y, min_x, max_y, color)
    end
  end

  if currentIndex > 1        then btn(true) end
  if songs[currentIndex + 1] then btn(false) end
end

local function keyInput(input)
  if not reaper.ImGui_IsWindowFocused(ctx) or reaper.ImGui_IsAnyItemActive(ctx) then return end

  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) or
     reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow()) then
    setNextIndex(nextIndex - 1)
  elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) or
         reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow()) then
    setNextIndex(nextIndex + 1)
  elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_PageUp(), false) or
         reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadSubtract(), false) then
    trySetCurrentIndex(currentIndex - 1)
  elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_PageDown(), false) or
         reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadAdd(), false) then
    trySetCurrentIndex(currentIndex + 1)
  -- elseif input == KEY_CLEAR then
  --   reset()
  elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false) or
         reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false) then
    if nextIndex == currentIndex then
      filterPrompt = true
    else
      setCurrentIndex(nextIndex)
    end
  end
end

local function toolbar()
  local frame_padding_x, frame_padding_y = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding())
  local item_spacing_x,  item_spacing_y  = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), frame_padding_x, math.floor(frame_padding_y * 0.60))
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),  item_spacing_x,  math.floor(item_spacing_y  * 0.60))
  reaper.ImGui_PushFont(ctx, nil)

  switchModeButton()
  reaper.ImGui_SameLine(ctx)

  local dockLabel = reaper.ImGui_IsWindowDocked(ctx) and 'undock' or 'dock'
  if reaper.ImGui_SmallButton(ctx, ('%s###dock'):format(dockLabel)) then
    toggleDock()
  end
  reaper.ImGui_SameLine(ctx)

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xff4242ff)
  if reaper.ImGui_SmallButton(ctx, 'reset') then reset() end
  reaper.ImGui_PopStyleColor(ctx)
  reaper.ImGui_SameLine(ctx)

  if reaper.ImGui_SmallButton(ctx, 'help') then about() end

  reaper.ImGui_PopFont(ctx)
  reaper.ImGui_PopStyleVar(ctx, 2)
end

local function mainWindow()
  contextMenu()
  keyInput()

  local avail_y = select(2, reaper.ImGui_GetContentRegionAvail(ctx))
  local fullUI = avail_y > 50 and reaper.ImGui_GetScrollMaxY(ctx) <= avail_y

  filterPrompt = filterPrompt and reaper.ImGui_IsWindowFocused(ctx)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_CellPadding(), 0, 0)
  if reaper.ImGui_BeginTable(ctx, 'topbar', fullUI and 1 or 3) then
    reaper.ImGui_PushFont(ctx, fullUI and fonts.large or fonts.huge)

    if fullUI then
      reaper.ImGui_TableNextColumn(ctx)
    else
      local width = reaper.ImGui_GetFontSize(ctx)
      reaper.ImGui_TableSetupColumn(ctx, 'prev', reaper.ImGui_TableColumnFlags_WidthFixed(), width)
      reaper.ImGui_TableSetupColumn(ctx, 'name', reaper.ImGui_TableColumnFlags_WidthStretch())
      reaper.ImGui_TableSetupColumn(ctx, 'next', reaper.ImGui_TableColumnFlags_WidthFixed(), width)
      reaper.ImGui_TableNextRow(ctx)
      navButtons(width)
      reaper.ImGui_TableSetColumnIndex(ctx, 1)
    end

    if filterPrompt then
      drawFilter()
    else
      drawName(songs[currentIndex])
    end

    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_EndTable(ctx)
  end
  reaper.ImGui_PopStyleVar(ctx)
  if fullUI then
    toolbar()
    reaper.ImGui_Spacing(ctx)
    songList()
  end
end

local function loop()
  execRemoteActions()

  reaper.ImGui_PushFont(ctx, fonts.small)
  reaper.ImGui_SetNextWindowSize(ctx, 500, 300, setDock and reaper.ImGui_Cond_Always() or reaper.ImGui_Cond_FirstUseEver())
  if setDock then
    reaper.ImGui_SetNextWindowDockID(ctx, setDock)
    setDock = nil
  end
  local visible, open = reaper.ImGui_Begin(ctx, SCRIPT_NAME, true, reaper.ImGui_WindowFlags_NoScrollbar())
  if visible then
    mainWindow()
    reaper.ImGui_End(ctx)
  end
  reaper.ImGui_PopFont(ctx)

  if open then
    reaper.defer(loop)
  else
    reaper.ImGui_DestroyContext(ctx)
  end
end

-- GO!!
reset()
reaper.defer(loop)

reaper.atexit(function()
  reaper.DeleteExtState(EXT_SECTION, EXT_STATE, false)
end)
