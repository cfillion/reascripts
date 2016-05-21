function reset()
  buffer = {}
  wrappedBuffer = {w = 0}

  resetFormat()
  push('test test test test test test test test test test test test test test')
  foreground = COLOR_BLUE
  push('blue')
  nl()
  font = FONT_BOLD
  foreground = COLOR_DEFAULT
  background = COLOR_RED
  push('error')
end

function keyboard()
  local input = gfx.getchar()

  if input < 0 then
    -- bye bye!
    saveDockedState()
    return false
  end

  return true
end

function draw()
  gfx.x = MARGIN
  gfx.y = MARGIN

  local height = 0

  for i=1,#wrappedBuffer do
    local segment = wrappedBuffer[i]

    if segment == NEWLINE then
      gfx.x = MARGIN
      gfx.y = gfx.y + height
    else
      gfx.setfont(segment.font)

      useColor(segment.bg)
      gfx.rect(gfx.x, gfx.y, segment.w, segment.h)

      useColor(segment.fg)

      gfx.drawstr(segment.text)
      height = math.max(height, segment.h)
    end
  end
end

function resetFormat()
  font = FONT_NORMAL
  foreground = COLOR_DEFAULT
  background = COLOR_BLACK
end

function nl()
  buffer[#buffer + 1] = NEWLINE
end

function push(contents)
  buffer[#buffer + 1] = {font=font, fg=foreground, bg=background, text=contents}
  wrap()
end

function dup(table)
  local copy = {}
  for k,v in pairs(table) do copy[k] = v end
  return copy
end

function wrap()
  if wrappedBuffer.w == gfx.w then
    return false
  end

  wrappedBuffer = {}

  local leftmost = MARGIN
  local left = leftmost

  for i=1,#buffer do
    local segment = buffer[i]

    if segment == NEWLINE then
      wrappedBuffer[#wrappedBuffer + 1] = NEWLINE
      left = leftmost
    else
      gfx.setfont(segment.font)

      text = segment.text

      while text:len() > 0 do
        local w, h = gfx.measurestr(text)
        local count = segment.text:len()
        local resized = false

        while w + left > gfx.w do
          count = count - 1
          w, _ = gfx.measurestr(segment.text:sub(0, count))
          resized = true
        end

        left = left + w

        local newSeg = dup(segment)
        newSeg.text = text:sub(0, count)
        newSeg.w = w
        newSeg.h = h
        wrappedBuffer[#wrappedBuffer + 1] = newSeg

        if resized then
          wrappedBuffer[#wrappedBuffer + 1] = NEWLINE
          left = leftmost
        end

        text = text:sub(count + 1)
      end
    end
  end
end

function loop()
  wrap()
  draw()

  gfx.update()

  if keyboard() then
    reaper.defer(loop)
  end
end

function useColor(color)
  gfx.r = color[1] / 255
  gfx.g = color[2] / 255
  gfx.b = color[3] / 255
end

function restoreDockedState()
  local docked_state = tonumber(reaper.GetExtState(EXT_SECTION, 'docked_state'))

  if docked_state then
    gfx.dock(docked_state)
  end
end

function saveDockedState()
  reaper.SetExtState(EXT_SECTION, 'docked_state', tostring(dockState), true)
end

MARGIN = 3

FONT_NORMAL = 1
FONT_BOLD = 2

COLOR_DEFAULT = {190, 190, 190}
COLOR_BLUE = {90, 90, 190}
COLOR_RED = {190, 90, 90}
COLOR_BLACK = {0, 0, 0}

NEWLINE = 1
EXT_SECTION = 'cfillion_ireascripts'

reset()

gfx.init('Interactive ReaScript', 500, 300)
gfx.setfont(FONT_NORMAL, 'Courier', 14)
gfx.setfont(FONT_BOLD, 'Courier', 14, 'b')

restoreDockedState()

-- GO!!
loop()
