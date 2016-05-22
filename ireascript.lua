local ireascript = {
  -- settings
  TITLE = 'Interactive ReaScript',
  BANNER = 'Interactive ReaScript v1.0 by cfillion',
  MARGIN = 3,
  MAXLINES = 512,
  INDENT = 2,
  INDENT_THRESHOLD = 10,

  COLOR_BLACK = {12, 12, 12},
  COLOR_BLUE = {88, 124, 212},
  COLOR_DEFAULT = {190, 190, 190},
  COLOR_GREEN = {90, 173, 87},
  COLOR_MAGENTA = {175, 95, 95},
  COLOR_RED = {255, 85, 85},
  COLOR_WHITE = {255, 255, 255},
  COLOR_YELLOW = {199, 199, 0},

  -- internal constants
  SG_NEWLINE = 1,
  SG_CURSOR = 2,

  FONT_NORMAL = 1,
  FONT_BOLD = 2,

  EXT_SECTION = 'cfillion_ireascripts',

  KEY_BACKSPACE = 8,
  KEY_CLEAR = 144,
  KEY_CTRLD = 4,
  KEY_CTRLL = 12,
  KEY_CTRLU = 21,
  KEY_DOWN = 1685026670,
  KEY_END = 6647396,
  KEY_ENTER = 13,
  KEY_HOME = 1752132965,
  KEY_INPUTRANGE_FIRST = 32,
  KEY_INPUTRANGE_LAST = 125,
  KEY_LEFT = 1818584692,
  KEY_RIGHT = 1919379572,
  KEY_UP = 30064,
}

function ireascript.help()
  ireascript.resetFormat()
  ireascript.push('Built-in commands:')
  ireascript.nl()

  local colWidth = 8

  for name,command in pairs(ireascript.BUILTIN) do
    local spaces = string.rep(' ', colWidth - name:len())

    ireascript.foreground = ireascript.COLOR_WHITE
    ireascript.push(string.format('.%s', name))

    ireascript.resetFormat()
    ireascript.push(spaces .. command.desc)

    ireascript.nl()
  end
end

function ireascript.clear()
  ireascript.reset(false)
  ireascript.update()
end

function ireascript.exit()
  gfx.quit()
end

ireascript.BUILTIN = {
  clear = {desc="Clear the line buffer", func=ireascript.clear},
  exit = {desc="Close iReaScript", func=ireascript.exit},
  help = {desc="Print this help text", func=ireascript.help},
}

function ireascript.reset(banner)
  ireascript.buffer = {}
  ireascript.wrappedBuffer = {w = 0}
  ireascript.input = ''
  ireascript.lines = 0
  ireascript.cursor = 0

  ireascript.resetFormat()

  if banner then
    ireascript.push('Interactive ReaScript v0.1 by cfillion')
    ireascript.nl()
    ireascript.push("Type Lua code or .help")
    ireascript.nl()
  end

  ireascript.prompt()
end

function ireascript.keyboard()
  local char = gfx.getchar()

  if char < 0 then
    -- bye bye!
    ireascript.saveDockedState()
    return false
  end

  -- if char ~= 0 then
  --   reaper.ShowConsoleMsg(char)
  --   reaper.ShowConsoleMsg("\n")
  -- end

  if char == ireascript.KEY_BACKSPACE then
    local before = ireascript.input:sub(0, ireascript.cursor)
    local after = ireascript.input:sub(ireascript.cursor + 1)
    ireascript.input = string.sub(before, 0, -2) .. after
    ireascript.cursor = math.max(0, ireascript.cursor - 1)
    ireascript.prompt()
    ireascript.update()
  elseif char == ireascript.KEY_CLEAR then
    ireascript.input = ''
    ireascript.cursor = 0
    ireascript.prompt()
    ireascript.update()
  elseif char == ireascript.KEY_CTRLU then
    ireascript.input = ireascript.input:sub(ireascript.cursor + 1)
    ireascript.cursor = 0
    ireascript.prompt()
    ireascript.update()
  elseif char == ireascript.KEY_ENTER then
    ireascript.eval()
  elseif char == ireascript.KEY_CTRLL then
    ireascript.clear()
  elseif char == ireascript.KEY_CTRLD then
    ireascript.exit()
  elseif char == ireascript.KEY_HOME then
    ireascript.cursor = 0
    ireascript.prompt()
    ireascript.update()
  elseif char == ireascript.KEY_LEFT then
    ireascript.cursor = math.max(0, ireascript.cursor - 1)
    ireascript.prompt()
    ireascript.update()
  elseif char == ireascript.KEY_RIGHT then
    ireascript.cursor = math.min(ireascript.input:len(), ireascript.cursor + 1)
    ireascript.prompt()
    ireascript.update()
  elseif char == ireascript.KEY_END then
    ireascript.cursor = ireascript.input:len()
    ireascript.prompt()
    ireascript.update()
  elseif char >= ireascript.KEY_INPUTRANGE_FIRST and char <= ireascript.KEY_INPUTRANGE_LAST then
    local before = ireascript.input:sub(0, ireascript.cursor)
    local after = ireascript.input:sub(ireascript.cursor + 1)
    ireascript.input = before .. string.char(char) .. after
    ireascript.cursor = ireascript.cursor + 1
    ireascript.prompt()
    ireascript.update()
  end

  return true
end

function ireascript.draw()
  ireascript.useColor(ireascript.COLOR_BLACK)
  gfx.rect(0, 0, gfx.w, gfx.h)

  gfx.x = ireascript.MARGIN
  gfx.y = ireascript.MARGIN

  local height, cursor = 0, nil

  for i=1,#ireascript.wrappedBuffer do
    local segment = ireascript.wrappedBuffer[i]

    if segment == ireascript.SG_NEWLINE then
      gfx.x = ireascript.MARGIN
      gfx.y = gfx.y + height
      height = 0
    elseif segment == ireascript.SG_CURSOR then
      if os.time() % 2 == 0 then
        cursor = {x=gfx.x, y=gfx.y, h=height}
      end
    else
      gfx.setfont(segment.font)

      ireascript.useColor(segment.bg)
      gfx.rect(gfx.x, gfx.y, segment.w, segment.h)

      ireascript.useColor(segment.fg)

      gfx.drawstr(segment.text)
      height = math.max(height, segment.h)
    end
  end

  if cursor then
    gfx.line(cursor.x, cursor.y, cursor.x, cursor.y + cursor.h)
  end
end

function ireascript.update()
  ireascript.wrappedBuffer = {}
  ireascript.wrappedBuffer.w = gfx.w

  local leftmost = ireascript.MARGIN
  local left = leftmost

  for i=1,#ireascript.buffer do
    segment = ireascript.buffer[i]

    if type(segment) ~= 'table' then
      ireascript.wrappedBuffer[#ireascript.wrappedBuffer + 1] = segment

      if segment == ireascript.SG_NEWLINE then
        left = leftmost
      end
    else
      gfx.setfont(segment.font)

      local text = segment.text

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

        local newSeg = ireascript.dup(segment)
        newSeg.text = text:sub(0, count)
        newSeg.w = w
        newSeg.h = h
        ireascript.wrappedBuffer[#ireascript.wrappedBuffer + 1] = newSeg

        if resized then
          ireascript.wrappedBuffer[#ireascript.wrappedBuffer + 1] = ireascript.SG_NEWLINE
          left = leftmost
        end

        text = text:sub(count + 1)
      end
    end
  end
end

function ireascript.loop()
  if ireascript.keyboard() then
    reaper.defer(ireascript.loop)
  end

  if ireascript.wrappedBuffer.w ~= gfx.w then
    ireascript.update()
  end

  ireascript.draw()

  gfx.update()
end

function ireascript.resetFormat()
  ireascript.font = ireascript.FONT_NORMAL
  ireascript.foreground = ireascript.COLOR_DEFAULT
  ireascript.background = ireascript.COLOR_BLACK
end

function ireascript.errorFormat()
  ireascript.font = ireascript.FONT_BOLD
  ireascript.foreground = ireascript.COLOR_WHITE
  ireascript.background = ireascript.COLOR_RED
end

function ireascript.nl()
  if ireascript.lines >= ireascript.MAXLINES then
    local first = ireascript.buffer[1]

    while first ~= nil do
      table.remove(ireascript.buffer, 1)

      if first == ireascript.SG_NEWLINE then
        break
      end

      first = ireascript.buffer[1]
    end
  else
    ireascript.lines = ireascript.lines + 1
  end

  ireascript.buffer[#ireascript.buffer + 1] = ireascript.SG_NEWLINE
end

function ireascript.push(contents)
  if contents == nil then
    error('content is nil')
  end

  ireascript.buffer[#ireascript.buffer + 1] = {
    font=ireascript.font,
    fg=ireascript.foreground, bg=ireascript.background,
    text=contents,
  }
end

function ireascript.prompt()
  ireascript.resetFormat()
  ireascript.backtrack()
  ireascript.push('> ')
  ireascript.push(ireascript.input:sub(0, ireascript.cursor))
  ireascript.buffer[#ireascript.buffer + 1] = ireascript.SG_CURSOR
  ireascript.push(ireascript.input:sub(ireascript.cursor + 1))
end

function ireascript.backtrack()
  local i = #ireascript.buffer
  while i >= 1 do
    if ireascript.buffer[i] == ireascript.SG_NEWLINE then
      return
    end

    table.remove(ireascript.buffer)
    i = i - 1
  end
end

function ireascript.removeCursor()
  local i = #ireascript.buffer
  while i >= 1 do
    local segment = ireascript.buffer[i]

    if segment == ireascript.SG_NEWLINE then
      return
    elseif segment == ireascript.SG_CURSOR then
      table.remove(ireascript.buffer, i)
    end

    i = i - 1
  end
end

function ireascript.eval()
  ireascript.removeCursor()
  ireascript.nl()

  if ireascript.input:sub(0, 1) == '.' then
    local name = ireascript.input:sub(2)
    local command = ireascript.BUILTIN[name:lower()]
    if command then
      command.func()

      if ireascript.input:len() == 0 then
        return -- buffer got reset
      end
    else
      ireascript.errorFormat()
      ireascript.push('command not found: ' .. name)
      ireascript.nl()
    end
  elseif ireascript.input:len() > 0 then
    local _, err = pcall(function()
      ireascript.lua(ireascript.input)
    end)

    if err then
      ireascript.errorFormat()
      ireascript.push(ireascript.makeError(err))
    end

    ireascript.nl()
  end

  ireascript.input = ''
  ireascript.cursor = 0
  ireascript.prompt()
  ireascript.update()
end

function ireascript.makeError(err)
  return err:sub(20)
end

function ireascript.lua(code)
  local func, err = load(code, 'eval')

  if err then
    ireascript.errorFormat()
    ireascript.push(ireascript.makeError(err))
  else
    local values = {func()}

    if #values <= 1 then
      ireascript.format(values[1])
    else
      ireascript.format(values)
    end
  end
end

function ireascript.format(value)
  ireascript.resetFormat()

  local t = type(value)

  if t == 'table' then
    local i, array = 1, #value > 0

    for k,v in pairs(value) do
      if k ~= i then
        array = false
      end

      i = i + 1
    end

    if array then
      ireascript.formatArray(value)
    else
      ireascript.formatTable(value, i)
    end

    return
  elseif value == nil then
    ireascript.foreground = ireascript.COLOR_YELLOW
  elseif t == 'number' then
    ireascript.foreground = ireascript.COLOR_BLUE
  elseif t == 'function' then
    ireascript.foreground = ireascript.COLOR_MAGENTA
    value = string.format('<%s>', value)
  elseif t == 'string' then
    ireascript.foreground = ireascript.COLOR_GREEN
    value = string.format('"%s"',
      value:gsub('\\', '\\\\'):gsub("\n", '\\n'):gsub('"', '\\"')
    )
  end

  ireascript.push(tostring(value))
end

function ireascript.formatArray(value)
  local i = 1

  ireascript.push('[')
  for k,v in ipairs(value) do
    if i > 1 then
      ireascript.resetFormat()
      ireascript.push(', ')
    end

    ireascript.format(v)
    i = i + 1
  end
  ireascript.resetFormat()
  ireascript.push(']')
end

function ireascript.formatTable(value, size)
  local i, indent = 1, size > ireascript.INDENT_THRESHOLD

  if indent then
    if ireascript.ilevel == nil then
      ireascript.ilevel = 1
    else
      ireascript.ilevel = ireascript.ilevel + 1
    end
  end

  local doIndent = function()
    if indent then
      ireascript.nl()
      ireascript.push(string.rep(' ', ireascript.INDENT * ireascript.ilevel))
    end
  end

  ireascript.push('{')
  doIndent()

  for k,v in pairs(value) do
    if i > 1 then
      ireascript.resetFormat()
      ireascript.push(', ')
      doIndent()
    end

    ireascript.format(k)
    ireascript.resetFormat()
    ireascript.push('=')
    ireascript.format(v)

    i = i + 1
  end

  if indent then
    ireascript.nl()
    ireascript.ilevel = ireascript.ilevel - 1
    ireascript.push(string.rep(' ', ireascript.INDENT * ireascript.ilevel))
  end

  ireascript.resetFormat()
  ireascript.push('}')
end

function ireascript.useColor(color)
  gfx.r = color[1] / 255
  gfx.g = color[2] / 255
  gfx.b = color[3] / 255
end

function ireascript.dup(table)
  local copy = {}
  for k,v in pairs(table) do copy[k] = v end
  return copy
end

function ireascript.restoreDockedState()
  local docked_state = tonumber(reaper.GetExtState(
    ireascript.EXT_SECTION, 'docked_state'))

  if docked_state then
    gfx.dock(docked_state)
  end
end

function ireascript.saveDockedState()
  reaper.SetExtState(ireascript.EXT_SECTION,
    'docked_state', tostring(dockState), true)
end

ireascript.reset(true)

gfx.init(ireascript.TITLE, 500, 300)
gfx.setfont(ireascript.FONT_NORMAL, 'Courier', 14)
gfx.setfont(ireascript.FONT_BOLD, 'Courier', 14, 'b')

ireascript.restoreDockedState()

-- GO!!
ireascript.loop()
