function loadTracks()
  local size = reaper.GetNumTracks()
  local songs, sIndex = {}, 0
  local depth = 0

  for index=0,size-1 do
    local track = reaper.GetTrack(0, index)

    local track_depth = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')

    if depth == 0 and track_depth == 1 then
      sIndex = sIndex + 1

      local _, name = reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)

      if string.len(name) == 0 then
        name = string.format("%02d. No Name", sIndex)
      end

      songs[sIndex] = {name=name, folder=track, tracks={track}, tracks_size=1}
    elseif depth >= 1 then
      songs[sIndex].tracks_size = songs[sIndex].tracks_size + 1
      songs[sIndex].tracks[songs[sIndex].tracks_size] = track
    end

    depth = depth + track_depth
  end

  table.sort(songs, compareSongs)
  return songs
end

function getSongNum(song)
  return tonumber(string.match(song.name, '^%d+'))
end

function compareSongs(a, b)
  local anum, bnum = getSongNum(a), getSongNum(b)

  if anum and bnum then
    return anum < bnum
  else
    return a.name < b.name
  end
end

function setSongEnabled(song, enabled)
  if song == nil then return end

  local on = 1
  if not enabled then on = 0 end

  local off = 0
  if not enabled then off = 1 end

  reaper.SetMediaTrackInfo_Value(song.folder, 'B_MUTE', off)

  for _,track in ipairs(song.tracks) do
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', on)
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', on)
  end
end

function setCurrentIndex(index)
  if index == currentIndex then return end

  reaper.PreventUIRefresh(1)

  if currentIndex < 1 then
    for _,song in ipairs(songs) do
      setSongEnabled(song, false)
    end
  else
    setSongEnabled(songs[currentIndex], false)
  end

  setSongEnabled(songs[index], true)
  currentIndex = index
  setNextIndex(index)

  reaper.PreventUIRefresh(-1)

  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

function setNextIndex(index)
  if songs[index] then
    nextIndex = index
    scrollTo = index
    highlightTime = os.time()
  end
end

function findSong(buffer)
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

function useColor(color)
  gfx.r = color[1] / 255
  gfx.g = color[2] / 255
  gfx.b = color[3] / 255
end

function textLine(text, x, padding)
  local w, h = gfx.measurestr(text)
  local y = gfx.y

  if x == nil then
    x = math.max(0, (gfx.w - w) / 2)
  end

  local tx, ty, tw = x, y, w

  if padding ~= nil then
    x = x - padding
    w = w + (padding * 2)

    ty = y + padding
    h = h + (padding * 2)
  end

  local rect = {x=0, y=y, w=gfx.w, h=h}
  return {text=text, rect=rect, tx=tx, ty=ty, tw=tw}
end

function drawTextLine(line)
  gfx.x = line.tx
  gfx.y = line.ty

  gfx.drawstr(line.text)
  gfx.y = line.rect.y + line.rect.h
end

function drawName(song)
  local name = '## No Song Selected ##'

  if song ~= nil then
    name = song.name
  end

  gfx.setfont(FONT_LARGE)
  useColor(COLOR_WHITE)

  drawTextLine(textLine(name))
end

function drawFilter()
  gfx.setfont(FONT_LARGE)
  useColor(COLOR_LGRAY)

  local buffer = filterBuffer

  if string.len(buffer) == 0 then
    buffer = "\x20"
  end

  local line = textLine(buffer)
  drawTextLine(line)

  if os.time() % 2 == 0 then
    local topRight = line.tx + line.tw
    gfx.line(topRight, line.ty, topRight, line.ty + line.rect.h)
  end
end

function songList(y)
  gfx.setfont(FONT_DEFAULT)
  gfx.y = y - scrollOffset

  local lastIndex, line, bottom, newScrollOffset

  for index, song in ipairs(songs) do
    lastIndex = index
    line = textLine(song.name, MARGIN, PADDING)
    bottom = line.rect.y + line.rect.h

    if line.rect.y >= y - line.rect.h and bottom < gfx.h + line.rect.h then
      if button(line, index == currentIndex, index == nextIndex) then
        setCurrentIndex(index)
      end
    else
      gfx.y = bottom
    end

    if index == scrollTo then
      if bottom + line.rect.h > gfx.h then
        -- scroll down
        newScrollOffset = scrollOffset + (bottom - gfx.h) + line.rect.h
      elseif line.rect.y <= y + line.rect.h then
        -- scroll up
        newScrollOffset = scrollOffset - ((y - line.rect.y) + line.rect.h)
      end
    end
  end

  scrollTo = 0

  if lastIndex then
    maxScrollOffset = math.max(0,
      scrollOffset + (bottom - gfx.h) + PADDING)

    scrollbar(y, gfx.h - y)
  end

  if newScrollOffset then
    scrollOffset = math.max(0, math.min(newScrollOffset, maxScrollOffset))
  end
end

function scrollbar(top, height)
  if maxScrollOffset < 1 then return end

  height = height - MARGIN

  local bottom = height + maxScrollOffset
  local percent = height / bottom

  useColor(COLOR_DGRAY)
  gfx.rect((gfx.w - MARGIN), top + (scrollOffset * percent), 4, height * percent)
end

function resetButton()
  gfx.setfont(FONT_DEFAULT)
  gfx.x = 0
  gfx.y = 0

  btn = textLine('reset')
  btn.tx = btn.rect.w - btn.tw
  btn.rect.w = btn.tw
  btn.rect.x = btn.tx

  if button(btn, false, false, true) then
    reset()
  end
end

function button(line, active, highlight, danger)
  local color, triggered = COLOR_LGRAY, false

  if active then
    useColor(COLOR_ACTIVEBG)
    gfx.rect(line.rect.x, line.rect.y, line.rect.w, line.rect.h)
    color = COLOR_ACTIVEFG
  end

  if isUnderMouse(line.rect.x, line.rect.y, line.rect.w, line.rect.h) then
    if mouseState > 0 then
      if danger then
        useColor(COLOR_DANGERBG)
        color = COLOR_DANGERFG
      else
        useColor(COLOR_HIGHLIGHTBG)
        color = COLOR_HIGHLIGHTFG
      end
    elseif not active then
      useColor(COLOR_HOVERBG)
      color = COLOR_HOVERFG
    end

    gfx.rect(line.rect.x, line.rect.y, line.rect.w, line.rect.h)

    if mouseClick then
      triggered = true
    end
  end

  -- draw highlight rect after mouse colors
  -- so that hover don't override it
  if highlight and not active and shouldShowHighlight() then
    useColor(COLOR_HIGHLIGHTBG)
    color = COLOR_HIGHLIGHTFG
    gfx.rect(line.rect.x, line.rect.y, line.rect.w, line.rect.h)
  end

  useColor(color)
  drawTextLine(line)

  return triggered
end

function shouldShowHighlight()
  local time = os.time() - highlightTime
  return time < 2 or time % 2 == 0
end

function keyboard()
  local input = gfx.getchar()

  if input < 0 or input == KEY_ESCAPE then
    gfx.quit()
  else
    reaper.defer(loop)
  end

  -- if input ~= 0 then
  --   reaper.ShowConsoleMsg(input)
  --   reaper.ShowConsoleMsg("\n")
  -- end

  if filterPrompt then
    filterKey(input)
  else
    normalKey(input)
  end
end

function filterKey(input)
  if input == KEY_BACKSPACE then
    filterBuffer = string.sub(filterBuffer, 0, -2)
  elseif input == KEY_CLEAR or input == KEY_CTRLU then
    filterBuffer = ''
  elseif input == KEY_ENTER then
    local index, _ = findSong(filterBuffer)

    if index then
      setCurrentIndex(index)
    end

    filterPrompt = false
    filterBuffer = ''
  elseif input >= KEY_INPUTRANGE_FIRST and input <= KEY_INPUTRANGE_LAST then
    filterBuffer = filterBuffer .. string.char(input)
  end
end

function normalKey(input)
  if input == KEY_SPACE then
    local playing = reaper.GetPlayState() == 1

    if playing then
      reaper.OnStopButton()
    else
      reaper.OnPlayButton()
    end
  elseif input == KEY_UP or input == KEY_LEFT then
    setNextIndex(nextIndex - 1)
  elseif input == KEY_DOWN or input == KEY_RIGHT then
    setNextIndex(nextIndex + 1)
  elseif input == KEY_ENTER then
    if nextIndex == currentIndex then
      filterPrompt = true
    else
      setCurrentIndex(nextIndex)
    end
  end
end

function isUnderMouse(x, y, w, h)
  local hor, ver = false, false

  if gfx.mouse_x > x and gfx.mouse_x < x + w then
    hor = true
  end

  if gfx.mouse_y > y and gfx.mouse_y < y + h then
    ver = true
  end

  if hor and ver then return true else return false end
end

function mouse()
  if gfx.mouse_wheel ~= 0 then
    local offset = math.max(0, scrollOffset - gfx.mouse_wheel)
    scrollOffset = math.min(offset, maxScrollOffset)

    gfx.mouse_wheel = 0
  end

  if mouseState == 0 and gfx.mouse_cap ~= 0 then
    -- NOTE: mouse press handling here
  end

  if mouseState == 1 and gfx.mouse_cap == 0 then
    mouseClick = true
  else
    mouseClick = false
  end

  mouseState = gfx.mouse_cap
end

function loop()
  local listStart = 60
  songList(listStart)

  -- solid header background, to hide scrolled list items
  gfx.y = MARGIN
  useColor(COLOR_BLACK)
  gfx.rect(0, 0, gfx.w, listStart)

  resetButton()

  if filterPrompt then
    drawFilter()
  else
    drawName(songs[currentIndex])
  end

  -- separator line
  gfx.y = gfx.y + MARGIN
  useColor(COLOR_DGRAY)
  gfx.line(0, gfx.y, gfx.w, gfx.y)

  gfx.update()

  keyboard()
  mouse()
end

function reset()
  songs = loadTracks()

  currentIndex = -1
  nextIndex = 0
  scrollOffset = 0
  maxScrollOffset = 0

  setCurrentIndex(0)
end

reset()

-- graphic initialization
FONT_DEFAULT = 0
FONT_LARGE = 1
FONT_SMALL = 2

COLOR_WHITE = {255, 255, 255}
COLOR_LGRAY = {200, 200, 200}
COLOR_DGRAY = {178, 178, 178}
COLOR_BLACK = {0, 0, 0}

COLOR_HOVERBG = {30, 30, 30}
COLOR_HOVERFG = COLOR_WHITE
COLOR_HIGHLIGHTBG = {164, 204, 255}
COLOR_HIGHLIGHTFG = COLOR_BLACK
COLOR_DANGERBG = {255, 0, 0}
COLOR_DANGERFG = COLOR_BLACK
COLOR_ACTIVEBG = {80, 80, 90}
COLOR_ACTIVEFG = COLOR_WHITE

KEY_ESCAPE = 27
KEY_SPACE = 32
KEY_UP = 30064
KEY_DOWN = 1685026670
KEY_RIGHT = 1919379572
KEY_LEFT = 1818584692
KEY_INPUTRANGE_FIRST = 32
KEY_INPUTRANGE_LAST = 122
KEY_ENTER = 13
KEY_BACKSPACE = 8
KEY_CTRLU = 21
KEY_CLEAR = 144

PADDING = 3
MARGIN = 10

mouseState = 0
mouseClick = false
filterPrompt = false
filterBuffer = ''
highlightTime = 0
scrollTo = 0
-- other variable initializations in reset()

gfx.init('Song Switcher', 500, 300)
gfx.setfont(FONT_LARGE, 'sans-serif', 28, 'b')
gfx.setfont(FONT_SMALL, 'sans-serif', 13)

-- GO!!
reaper.defer(loop)
loop()
