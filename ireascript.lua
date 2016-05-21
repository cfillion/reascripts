function reset()
  buffer = {}
  wrappedBuffer = {w = 0}

  resetFormat()

  push('Interactive ReaScript v0.1 by cfillion')
  nl()
  push("Type Lua code or 'help'")
  nl()

  prompt()
end

function keyboard()
  local char = gfx.getchar()

  if char < 0 then
    -- bye bye!
    saveDockedState()
    return false
  end

  -- if char ~= 0 then
  --   reaper.ShowConsoleMsg(char)
  --   reaper.ShowConsoleMsg("\n")
  -- end

  if char == KEY_BACKSPACE then
    input = string.sub(input, 0, -2)
    prompt()
  elseif char == KEY_CLEAR or char == KEY_CTRLU then
    input = ''
    prompt()
  elseif char >= KEY_INPUTRANGE_FIRST and char <= KEY_INPUTRANGE_LAST then
    input = input .. string.char(char)
    prompt()
  end

  return true
end

function draw()
  gfx.x = MARGIN
  gfx.y = MARGIN

  local height = 0

  for i=1,#wrappedBuffer do
    local segment = wrappedBuffer[i]

    if segment == SG_NEWLINE then
      gfx.x = MARGIN
      gfx.y = gfx.y + height
    elseif segment == SG_CURSOR then
      if os.time() % 2 == 0 then
        gfx.line(gfx.x, gfx.y, gfx.x, gfx.y + height)
      end
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
  buffer[#buffer + 1] = SG_NEWLINE
end

function push(contents)
  buffer[#buffer + 1] = {font=font, fg=foreground, bg=background, text=contents}
  wrap()
end

function prompt()
  resetFormat()
  backtrack()
  push('> ')
  push(input)
  buffer[#buffer + 1] = SG_CURSOR
end

function backtrack()
  local i = #buffer
  while i > 1 do
    if buffer[i] == SG_NEWLINE then
      return
    end

    table.remove(buffer)
    i = i - 1
  end

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

    if type(segment) ~= 'table' then
      wrappedBuffer[#wrappedBuffer + 1] = segment

      if segment == SG_NEWLINE then
        left = leftmost
      end
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
          wrappedBuffer[#wrappedBuffer + 1] = SG_NEWLINE
          left = leftmost
        end

        text = text:sub(count + 1)
      end
    end
  end
end

function loop()
  if keyboard() then
    reaper.defer(loop)
  end

  wrap()
  draw()

  gfx.update()

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

TITLE = 'Interactive ReaScript'
BANNER = 'Interactive ReaScript v1.0 by cfillion'
MARGIN = 3

input = ''

FONT_NORMAL = 1
FONT_BOLD = 2

COLOR_DEFAULT = {190, 190, 190}
COLOR_BLUE = {90, 90, 190}
COLOR_RED = {190, 90, 90}
COLOR_BLACK = {0, 0, 0}

SG_NEWLINE = 1
SG_CURSOR = 2

EXT_SECTION = 'cfillion_ireascripts'

KEY_BACKSPACE = 8
KEY_CTRLU = 21
KEY_CLEAR = 144
KEY_INPUTRANGE_FIRST = 32
KEY_INPUTRANGE_LAST = 122

reset()

gfx.init(TITLE, 500, 300)
gfx.setfont(FONT_NORMAL, 'Courier', 14)
gfx.setfont(FONT_BOLD, 'Courier', 14, 'b')

restoreDockedState()

-- GO!!
loop()
