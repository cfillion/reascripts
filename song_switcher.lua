function loadSongs()
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
      tracks[0] = index

      songs[sIndex] = {name=name, folder=index, tracks=tracks, tracks_size=1}
    elseif depth >= 1 then
      songs[sIndex].tracks[songs[sIndex].tracks_size] = index
      songs[sIndex].tracks_size = songs[sIndex].tracks_size + 1
    end

    depth = depth + track_depth
  end

  lastLoad = os.time()

  return songs
end

function reloadSongs()
  local deleted = false
  if lastLoad == os.time() then return end

  for _,song in pairs(songs) do
    local folder = reaper.GetTrack(0, song.folder)
    if folder == nil then
      deleted = true
      break
    end

    local _, name = reaper.GetSetMediaTrackInfo_String(folder, "P_NAME", "", false)

    if name ~= song.name then
      deleted = true
      break
    end

    for index=1,song.tracks_size do
      if reaper.GetTrack(0, index) == nil then
        deleted = true
        break
      end
    end
  end

  songs = loadSongs()

  if deleted then
    currentIndex = -2
    setCurrentIndex(-1)
  end
end

function setSongEnabled(song, enabled)
  if song == nil then return end

  local on = 1
  if not enabled then on = 0 end

  local off = 0
  if not enabled then off = 1 end

  local folder = reaper.GetTrack(0, song.folder)

  if folder then
    reaper.SetMediaTrackInfo_Value(folder, "B_MUTE", off)
  end

  for _,trackIndex in pairs(song.tracks) do
    local track = reaper.GetTrack(0, trackIndex)

    if track then
      reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", on)
      reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", on)
    end
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

  local tx, ty = x, y

  if padding ~= nil then
    x = x - padding
    w = w + (padding * 2)

    ty = y + padding
    h = h + (padding * 2)
  end

  local rect = {x=0, y=y, w=gfx.w, h=h}
  return {text=text, rect=rect, tx=tx, ty=ty}
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

function drawSongList()
  gfx.setfont(FONT_DEFAULT)

  local index = 0
  local song = songs[index]

  while song ~= nil do
    local line = textLine(song.name, 10, PADDING)
    local x, y, w, h = line.rect

    color = COLOR_LGRAY

    if index == currentIndex then
      useColor(COLOR_ACTIVE)
      gfx.rect(line.rect.x, line.rect.y, line.rect.w, line.rect.h)
      color = COLOR_WHITE
    end

    if isUnderMouse(line.rect.x, line.rect.y, line.rect.w, line.rect.h) then
      if mouseState > 0 then
        useColor(COLOR_HIGHLIGHT)
        gfx.rect(line.rect.x, line.rect.y, line.rect.w, line.rect.h)
        color = COLOR_BLACK
      elseif mouseClick then
        setCurrentIndex(index)
      end
    end

    useColor(color)
    drawTextLine(line)

    index = index + 1
    song = songs[index]
  end
end

function keyboard()
  local input = gfx.getchar()

  if input < 0 or input == KEY_ESCAPE then
    gfx.quit()
  else
    reaper.defer(loop)
  end

  if input == KEY_SPACE then
    local playing = reaper.GetPlayState() == 1

    if playing then
      reaper.OnStopButton()
    else
      reaper.OnPlayButton()
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
  reloadSongs()

  gfx.y = 10
  drawName(songs[currentIndex])

  gfx.y = gfx.y + 10
  useColor(COLOR_DGRAY)
  gfx.line(0, gfx.y, gfx.w, gfx.y)

  gfx.y = gfx.y + 10
  drawSongList()

  gfx.update()

  keyboard()
  mouse()
end

songs = loadSongs()

-- initial state: disable every tracks
currentIndex = -2
setCurrentIndex(-1)

-- graphic initialization
FONT_DEFAULT = 0
FONT_LARGE = 1
FONT_SMALL = 2

COLOR_WHITE = {255, 255, 255}
COLOR_LGRAY = {200, 200, 200}
COLOR_DGRAY = {178, 178, 178}
COLOR_HIGHLIGHT = {164, 204, 255}
COLOR_ACTIVE = {70, 70, 70}
COLOR_BLACK = {0, 0, 0}

KEY_ESCAPE = 27
KEY_SPACE = 32

PADDING = 3

mouseState = 0
mouseClick = false
lastLoad = 0

gfx.init("cfillion's Song Switcher", 500, 300)
gfx.setfont(FONT_LARGE, "sans-serif", 28, 'b')
gfx.setfont(FONT_SMALL, "sans-serif", 13)

-- GO!!
reaper.defer(loop)
loop()
