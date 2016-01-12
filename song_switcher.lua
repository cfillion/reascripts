function loadTracks()
  local index, size = 0, reaper.GetNumTracks()
  local songs, sIndex = {}, -1
  local depth = 0

  for index=0,size-1 do
    local track = reaper.GetTrack(0, index)

    local track_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

    if depth == 0 and track_depth == 1 then
      sIndex = sIndex + 1

      local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

      local tracks = {}
      tracks[0] = track

      songs[sIndex] = {name=name, folder=track, tracks=tracks, tracks_size=1}
    elseif depth >= 1 then
      songs[sIndex].tracks[songs[sIndex].tracks_size] = track
      songs[sIndex].tracks_size = songs[sIndex].tracks_size + 1
    end

    depth = depth + track_depth
  end

  return songs
end

function setSongEnabled(song, enabled)
  if song == nil then return end

  local on = 1
  if not enabled then on = 0 end

  local off = 0
  if not enabled then off = 1 end

  reaper.SetMediaTrackInfo_Value(song.folder, "B_MUTE", off)

  for _,track in pairs(song.tracks) do
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", on)
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", on)
  end
end

function setCurrentIndex(index)
  if index == currentIndex then return end

  reaper.PreventUIRefresh(1)

  if currentIndex < 0 then
    for _,song in pairs(songs) do
      setSongEnabled(song, false)
    end
  else
    setSongEnabled(songs[currentIndex], false)
  end

  setSongEnabled(songs[index], true)
  currentIndex = index

  reaper.PreventUIRefresh(-1)
  reaper.TrackList_AdjustWindows(false)
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
  local name = "##. No Song Selected"

  if song ~= nil then
    name = song.name
  end

  gfx.setfont(FONT_LARGE)
  useColor(COLOR_WHITE)

  drawTextLine(textLine(name))
end

function songList()
  gfx.setfont(FONT_DEFAULT)

  local index = 0
  local song = songs[index]

  while song ~= nil do
    local line = textLine(song.name, 10, PADDING)

    if button(line, index == currentIndex) then
      setCurrentIndex(index)
    end

    index = index + 1
    song = songs[index]
  end
end

function resetButton()
  gfx.x = 0
  gfx.y = 0

  btn = textLine("reset")
  btn.tx = btn.rect.w - btn.tw
  btn.rect.w = btn.tw
  btn.rect.x = btn.tx

  if button(btn, false) then
    reset()
  end
end

function button(line, active, callback)
  local color, triggered = COLOR_LGRAY, false

  if active then
    useColor(COLOR_ACTIVE)
    gfx.rect(line.rect.x, line.rect.y, line.rect.w, line.rect.h)
    color = COLOR_WHITE
  end

  if isUnderMouse(line.rect.x, line.rect.y, line.rect.w, line.rect.h) then
    if mouseState > 0 then
      useColor(COLOR_HIGHLIGHT)
      color = COLOR_BLACK
    elseif not active then
      useColor(COLOR_HOVER)
      color = COLOR_WHITE
    end

    gfx.rect(line.rect.x, line.rect.y, line.rect.w, line.rect.h)

    if mouseClick then
      triggered = true
    end
  end

  useColor(color)
  drawTextLine(line)

  return triggered
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

  if input == KEY_SPACE then
    local playing = reaper.GetPlayState() == 1

    if playing then
      reaper.OnStopButton()
    else
      reaper.OnPlayButton()
    end
  elseif input == KEY_UP or input == KEY_LEFT then
    local index = currentIndex - 1

    if songs[index] then
      setCurrentIndex(index)
    end
  elseif input == KEY_DOWN or input == KEY_RIGHT then
    local index = currentIndex + 1

    if songs[index] then
      setCurrentIndex(index)
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
  resetButton()

  gfx.y = 10
  drawName(songs[currentIndex])

  gfx.y = gfx.y + 10
  useColor(COLOR_DGRAY)
  gfx.line(0, gfx.y, gfx.w, gfx.y)

  gfx.y = gfx.y + 10
  songList()

  gfx.update()

  keyboard()
  mouse()
end

function reset()
  songs = loadTracks()

  currentIndex = -2
  setCurrentIndex(-1)
end

reset()

-- graphic initialization
FONT_DEFAULT = 0
FONT_LARGE = 1
FONT_SMALL = 2

COLOR_WHITE = {255, 255, 255}
COLOR_LGRAY = {200, 200, 200}
COLOR_DGRAY = {178, 178, 178}
COLOR_HIGHLIGHT = {164, 204, 255}
COLOR_HOVER = {30, 30, 30}
COLOR_ACTIVE = {80, 80, 90}
COLOR_BLACK = {0, 0, 0}

KEY_ESCAPE = 27
KEY_SPACE = 32
KEY_UP = 30064
KEY_DOWN = 1685026670
KEY_RIGHT = 1919379572
KEY_LEFT = 1818584692

PADDING = 3

mouseState = 0
mouseClick = false

gfx.init("cfillion's Song Switcher", 500, 300)
gfx.setfont(FONT_LARGE, "sans-serif", 28, 'b')
gfx.setfont(FONT_SMALL, "sans-serif", 13)

-- GO!!
reaper.defer(loop)
loop()
