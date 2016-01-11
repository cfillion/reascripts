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
  reaper.PreventUIRefresh(1)

  if currentIndex == -1 then
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
  gfx.y = line.ty + line.rect.h
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

    if mouseState > 0 and isUnderMouse(line.rect.x, line.rect.y, line.rect.w, line.rect.h) then
      useColor(COLOR_HIGHLIGHT)
      gfx.rect(line.rect.x, line.rect.y, line.rect.w, line.rect.h)
      useColor(COLOR_BLACK)
    else
      useColor(COLOR_LGRAY)
    end

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
    onClick()
  end

  mouseState = gfx.mouse_cap
end

function onClick()
end

function loop()
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

songs = loadTracks()

-- initial state: disable every tracks
currentIndex = -1
setCurrentIndex(-1)

-- graphic initialization
FONT_DEFAULT = 0
FONT_LARGE = 1
FONT_SMALL = 2

COLOR_WHITE = {255, 255, 255}
COLOR_LGRAY = {200, 200, 200}
COLOR_DGRAY = {178, 178, 178}
COLOR_HIGHLIGHT = {164, 204, 255}
COLOR_BLACK = {0, 0, 0}

KEY_ESCAPE = 27
KEY_SPACE = 32

PADDING = 3

mouseState = 0

gfx.init("cfillion's Song Switcher", 500, 300)
gfx.setfont(FONT_LARGE, "sans-serif", 28, 'b')
gfx.setfont(FONT_SMALL, "sans-serif", 13)

-- GO!!
reaper.defer(loop)
loop()
