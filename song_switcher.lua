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

function printName(song)
  local name = "##. No Song Selected"

  if song ~= nil then
    name = song.name
  end

  gfx.setfont(FONT_LARGE)
  useColor(COLOR_WHITE)

  local w, h = gfx.measurestr(name)
  gfx.x = math.max(0, (gfx.w - w) / 2)

  gfx.drawstr(name)
  gfx.y = gfx.y + h
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

function loop()
  gfx.y = 10
  printName(songs[currentIndex])

  gfx.y = gfx.y + 10
  useColor(COLOR_GRAY)
  gfx.line(0, gfx.y, gfx.w, gfx.y)

  gfx.update()

  keyboard()
end

songs = loadTracks()

-- initial state: disable every tracks
currentIndex = -1
setCurrentIndex(-1)

-- graphic initialization
FONT_LARGE = 1
FONT_SMALL = 2

COLOR_WHITE = {255, 255, 255}
COLOR_GRAY = {178, 178, 178}

KEY_ESCAPE = 27
KEY_SPACE = 32

gfx.init("cfillion's Song Switcher", 500, 300)
gfx.setfont(FONT_LARGE, "sans-serif", 28, 'b')
gfx.setfont(FONT_SMALL, "sans-serif", 10)

-- GO!!
reaper.defer(loop)
loop()
