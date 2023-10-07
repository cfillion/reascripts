local ImGui = {}
for name, func in pairs(reaper) do
  name = name:match('^ImGui_(.+)$')
  if name then ImGui[name] = func end
end

local SCRIPT_NAME = 'Lua profiler'
local FLT_MIN = ImGui.NumericLimits_Float()

local profiler, data, report = {}
local attachments, wrappers, locations, clippers = {}, {}, {}, {}
local active, auto_active, show_metrics = false, false, false
local called_defer = false
local getTime = reaper.time_precise -- faster than os.clock

-- cache stdlib constants and funcs to not break if the host script changes them
-- + don't count the profiler's own use of them in measurements
local math_huge = math.huge
local assert, error, type, pairs, print = assert, error, type, pairs, print
local tostring, select, getmetatable  = tostring, select, getmetatable
local debug_getlocal, debug_setlocal  = debug.getlocal, debug.setlocal
local debug_getinfo,  table_sort      = debug.getinfo,  table.sort
local math_min,       math_max        = math.min,       math.max
local math_log,       math_floor      = math.log,       math.floor
local string_gsub,    string_match    = string.gsub,    string.match
local string_find,    string_format   = string.find,    string.format
local string_sub,     string_rep      = string.sub,     string.rep
local utf8_len,       utf8_offset     = utf8.len,       utf8.offset
local reaper_defer,   CF_ShellExecute = reaper.defer,   reaper.CF_ShellExecute
local reaper_get_action_context = reaper.get_action_context

local function makeOpts(opts)
  if not opts then opts = {} end

  local defaults = {
    recursive    = true,
    pattern      = nil,
    search_above = true,
    metatable    = true,
  }
  for key, value in pairs(defaults) do
    if opts[key] == nil then opts[key] = value end
  end

  return opts
end

local function formatTime(time, pad)
  local units, unit = { 's', 'ms', 'us', 'ns' }, 1
  while time < 0.1 and unit < #units do
    time, unit = time * 1000, unit + 1
  end
  return string_format(pad and '%5.02f%-2s' or '%.02f%s', time, units[unit])
end

local function formatNumber(num)
  if not num then return end
  repeat
    local matches
    num, matches = string_gsub(num, '^(%d+)(%d%d%d)', '%1,%2')
  until matches < 1
  return num
end

local function utf8_sub(s, i, j)
  i = utf8_offset(s, i)
  if not i then return '' end -- i is out of bounds

  if j and (j > 0 or j < -1) then
    j = utf8_offset(s, j + 1)
    if j then j = j - 1 end
  end

  return string_sub(s, i, j)
end

local function ellipsis(ctx, text, length)
  local avail = ImGui.GetContentRegionAvail(ctx)
  if avail >= ImGui.CalcTextSize(ctx, text) then return text end

  local steps = 0
  local fit, l, r, m = '...', 0, utf8_len(text) - 1
  while l <= r do
    m = (l + r) // 2
    local cut = '...' .. utf8_sub(text, -m)
    if ImGui.CalcTextSize(ctx, cut) > avail then
      r = m - 1
    else
      l = m + 1
      fit = cut
    end
  end
  return fit
end

local function basename(filename)
  return string_match(filename, '[^/\\]+$') or filename
end

local function centerNextWindow(ctx)
  local center_x, center_y = ImGui.Viewport_GetCenter(ImGui.GetWindowViewport(ctx))
  ImGui.SetNextWindowPos(ctx, center_x, center_y, ImGui.Cond_Appearing(), 0.5, 0.5)
end

local function alignNextItemRight(ctx, label, spacing)
  local item_spacing_w = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing())
  ImGui.SetCursorPosX(ctx, math_max(ImGui.GetCursorPosX(ctx),
    ImGui.GetContentRegionMax(ctx) - (spacing and item_spacing_w or 0) -
    ImGui.CalcTextSize(ctx, label, nil, nil, true)))
end

local function enter(what, alias)
  report.dirty = true

  local line = data[what]
  if not line then
    line = {
      name = alias, count = 0, time = 0,
      enter_time = 0, enter_count = 0,
      frames = 0, prev_count = 0,
    }
    data[what] = line
  end

  if not locations[what] then
    local location
    if type(what) == 'function' then
      location = debug_getinfo(what, 'S')
    else -- user-provided name
      location = debug_getinfo(3, 'Sl')
      location.linedefined = location.currentline
    end
    locations[what] = location
  end

  line.count, line.enter_count = line.count + 1, line.enter_count + 1

  local now = getTime()
  if line.enter_count > 1 then
    line.time = line.time + (now - line.enter_time)
  end
  line.enter_time = now
end

local function leave(what)
  local now = getTime()
  local line = data[what]
  if not line or line.enter_count < 1 then
    error('unbalanced leave (missing call to enter)')
  end
  local time = now - line.enter_time
  if not line.min_time or time < line.min_time then
    line.min_time = time
  end
  if not line.max_time or time > line.max_time then
    line.max_time = time
  end
  line.time = line.time + time
  line.enter_time, line.enter_count = now, line.enter_count - 1
end

local function updateReport()
  if active then
    -- update active time
    profiler.stop()
    profiler.start()
  end

  report = {
    time = report.time,
    total_time = getTime() - report.first_start_time,
    start_time = report.start_time, first_start_time = report.first_start_time,
  }

  for key, line in pairs(data) do
    assert(line.enter_count == 0, 'unbalanced enter (missing call to leave)')
    local location = locations[key]
    local src, src_short, src_line = '<unknown>',  '<unknown>', -1
    if location then
      src = string_gsub(location.source, '^[@=]', '')
      src_short = basename(location.short_src)
      src_line = location.linedefined
    end
    report[#report + 1] = { -- immutable copy of the line
      name = line.name, time = line.time, count = line.count,
      min_time  = line.min_time, max_time = line.max_time,
      avg_time  = line.time / line.count, frames = line.frames,
      min_frame = line.min_frame, max_frame = line.max_frame,
      avg_frame = line.frames > 0 and line.count // line.frames,
      time_frac = line.time / report.time,
      src = src, src_short = src_short, src_line = src_line,
    }
  end

  table_sort(report, function(a, b) return a.time > b.time end)
end

local function callLeave(func, ...)
  -- faster than capturing func's return values in a table + table.unpack
  leave(func)
  return ...
end

local function makeWrapper(name, func)
  -- prevent double attachments from showing the wrapper in measurements
  if attachments[func] then return func end
  -- reuse already created wrappers
  local wrapper = wrappers[func]
  if wrapper then return wrapper end

  wrapper = function(...)
    if not active then return func(...) end
    enter(func, name)
    return callLeave(func, func(...))
  end

  attachments[wrapper], wrappers[func] = func, wrapper

  return wrapper
end

local function eachLocals(level, search_above)
  level = level + 1
  local i = 1
  return function()
    while debug_getinfo(level, '') do
      local name, value = debug_getlocal(level, i)
      if name then
        i = i + 1
        return level - 1, i - 1, name, value
      elseif not search_above then
        return
      end
      level, i = level + 1, 1
    end
  end
end

local function getHostVar(path, level)
  assert(type(path) == 'string', 'variable name must be a string')

  local off, sep = 1, string_find(path, '.', nil, true)
  local seg = string_sub(path, off, sep and sep - 1)
  local match, local_idx, parent

  for l, i, name, value in eachLocals(level, true) do
    if name == seg then
      level, local_idx, match = l, i, value
      break
    end
  end

  if not match then match = _ENV[seg] end

  while match and sep do
    assert(type(match) == 'table',
      string_format('%s is not a table', string_sub(path, 1, sep and sep - 1)))
    off = sep + 1
    sep = string_find(path, '.', off, true)
    seg = string_sub(path, off, sep and sep - 1)
    parent, match, local_idx = match, match[seg], nil
  end

  assert(match, string_format('variable not found: %s',
    string_sub(path, 1, sep and sep - 1)))

  return match, level - 1, local_idx, parent, seg
end

local attachToTable

local function attach(is_attach, name, value, opts, depth)
  -- prevent infinite recursion
  for k, v in pairs(profiler) do
    if value == v then return end
  end

  depth = depth or 0

  local t = type(value)
  if t == 'function' then
    if not opts.pattern or string_match(name, opts.pattern) then
      if is_attach then
        return true, makeWrapper(name, value)
      else
        local original = attachments[value]
        if original then return true, original end
      end
    end
  elseif opts.recursive and t == 'table' and depth < 8 and value ~= _G then
    attachToTable(is_attach, name, value, opts, depth + 1)
    return true
  end

  return false
end

attachToTable = function(is_attach, prefix, array, opts, depth)
  assert(type(array) == 'table', string_format('%s is not a table', prefix))

  if array == package.loaded then return end

  for name, value in pairs(array) do
    local path = name
    if prefix then path = string_format('%s.%s', prefix, name) end
    local ok, wrapper = attach(is_attach, path, value, opts, depth)
    if wrapper then array[name] = wrapper end
  end

  local metatable = getmetatable(array)
  if metatable and opts.metatable then
    attachToTable(is_attach, prefix .. '[meta]', metatable, opts, depth)
  end
end

local function attachToLocals(is_attach, opts)
  for level, idx, name, value in eachLocals(3, opts.search_above) do
    local ok, wrapper = attach(is_attach, name, value, opts)
    if wrapper then debug_setlocal(level, idx, wrapper) end
  end
end

local function attachToVar(is_attach, var, opts)
  local val, level, idx, parent, parent_key = getHostVar(var, 4)
  if type(val) == 'table' then
    return attachToTable(is_attach, var, val, opts)
  end
  local ok, wrapper = attach(is_attach, var, val, opts)
  assert(ok, string_format('%s is not %s',
    var, is_attach and 'attachable' or 'deatachable'))
  if wrapper then
    if idx then debug_setlocal(level, idx, wrapper) end
    if parent then parent[parent_key] = wrapper end
  end
end

function profiler.attachTo(var, opts)
  attachToVar(true, var, makeOpts(opts))
end

function profiler.detachFrom(var, opts)
  attachToVar(false, var, makeOpts(opts))
end

function profiler.attachToLocals(opts)
  attachToLocals(true, makeOpts(opts))
end

function profiler.detachFromLocals(opts)
  attachToLocals(false, makeOpts(opts))
end

function profiler.attachToWorld()
  local opts = makeOpts()
  attachToLocals(true, opts)
  attachToTable(true, nil, _G, opts)
end

function profiler.detachFromWorld()
  local opts = makeOpts()
  attachToLocals(false, opts)
  attachToTable(false, nil, _G, opts)
end

function profiler.reset()
  data, report = {}, { time = 0, total_time = 0 }
end

function profiler.start()
  assert(not active, 'profiler is already active')
  active = true
  report.start_time = getTime()
  if not report.first_start_time then
    report.first_start_time = report.start_time
  end
end

function profiler.stop()
  assert(active, 'profiler is not active')
  active = false
  report.time = report.time + (getTime() - report.start_time)
end

function profiler.frame()
  for key, line in pairs(data) do
    if line.enter_count > 0 then error('frame was called before leave') end
    if line.count > line.prev_count then
      local count = line.count - line.prev_count
      line.frames, line.prev_count = line.frames + 1, line.count
      if not line.min_frame or count < line.min_frame then
        line.min_frame = count
      end
      if not line.max_frame or count > line.max_frame then
        line.max_frame = count
      end
    end
  end
end

function profiler.enter(what)
  if not active then return end
  what = tostring(what)
  enter(what, what)
end

function profiler.leave(what)
  if not active then return end
  leave(tostring(what))
end

function profiler.showWindow(ctx, p_open, flags)
  flags = (flags or 0) |
    ImGui.WindowFlags_MenuBar()

  ImGui.SetNextWindowSize(ctx, 800, 500, ImGui.Cond_FirstUseEver())

  local host = select(2, reaper_get_action_context())
  local self = string_sub(debug_getinfo(1, 'S').source, 2)
  local title = string_format('%s - %s', SCRIPT_NAME, basename(host))
  local label = string_format('%s###%s', title, SCRIPT_NAME)

  local can_close, visible = p_open ~= nil
  visible, p_open = ImGui.Begin(ctx, label, p_open, flags)
  if not visible then return p_open end

  local open_no_defer_popup = false

  if ImGui.BeginMenuBar(ctx) then
    if ImGui.BeginMenu(ctx, 'File') then
      if ImGui.MenuItem(ctx, 'Close', nil, nil, can_close) then
        p_open = false
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx, 'Acquisition') then
      local is_active = active or auto_active
      if ImGui.MenuItem(ctx, 'Start', nil, nil, not is_active) then
        if called_defer then
          auto_active = true
        else
          open_no_defer_popup = true
        end
      end
      if ImGui.MenuItem(ctx, 'Stop', nil, nil, is_active) then
        auto_active = false
        if active then profiler.stop() end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx, 'Profile') then
      local has_data = report.start_time ~= nil
      if ImGui.MenuItem(ctx, 'Reset', nil, nil, has_data) then
        reaper_defer(profiler.reset)
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx, 'Help', CF_ShellExecute ~= nil) then
      if ImGui.MenuItem(ctx, 'Donate...') then
        CF_ShellExecute('https://reapack.com/donate')
      end
      if ImGui.MenuItem(ctx, 'Forum thread', nil, nil, false) then
        -- CF_ShellExecute('')
      end
      ImGui.EndMenu(ctx)
    end
    local fps = string_format('%04.01f FPS##fps', ImGui.GetFramerate(ctx))
    alignNextItemRight(ctx, fps, true)
    show_metrics = select(2, ImGui.MenuItem(ctx, fps, nil, show_metrics))
    ImGui.EndMenuBar(ctx)
  end

  if show_metrics then
    show_metrics = ImGui.ShowMetricsWindow(ctx, true)
  end

  if open_no_defer_popup then
    ImGui.OpenPopup(ctx, 'Active time measurement')
  end
  centerNextWindow(ctx)
  if ImGui.BeginPopupModal(ctx, 'Active time measurement', true,
      ImGui.WindowFlags_AlwaysAutoResize()) then
    ImGui.Text(ctx,
     'Active time measurement requires usage of a proxy defer function.\n\z
      Add the snippet below to the host script to enable this feature.\n\n\z
      \z
      Do you wish to enable acquisition without active time measurement?\n\z
      Realtime will be measured instead of active time.')
    ImGui.Spacing(ctx)

    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx)
    end
    local snippet = 'reaper.defer = profiler.defer'
    ImGui.InputTextMultiline(ctx, '##snippet', snippet,
      -FLT_MIN, ImGui.GetFontSize(ctx) * 3, ImGui.InputTextFlags_ReadOnly())
    ImGui.Spacing(ctx)

    if ImGui.Button(ctx, 'Continue') then
      profiler.start()
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Cancel') then
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  profiler.showReport(ctx, 'report', 0, 0)

  ImGui.End(ctx)
  return p_open
end

function profiler.showReport(ctx, label, width, height)
  if not ImGui.BeginChild(ctx, label, width, height) then return end

  local was_dirty = report.dirty
  if was_dirty then
    report.dirty = false
    updateReport()
  end

  local summary
  if #report < 1 then
    summary = 'No profiling data has been acquired yet.'
  else
    summary = string_format('Total active time: %s / %s (%.02f%%)',
      formatTime(report.time), formatTime(report.total_time),
      (report.time / report.total_time) * 100)
  end
  ImGui.Text(ctx, summary)
  if was_dirty then
    ImGui.SameLine(ctx, nil, 0)
    ImGui.Text(ctx, string_format('%-3s',
      string_rep('.', ImGui.GetTime(ctx) // 1 % 3 + 1)))
  end
  ImGui.SameLine(ctx)

  local export = false
  alignNextItemRight(ctx, 'Copy to clipboard', true)
  if ImGui.SmallButton(ctx, 'Copy to clipboard') then
    export = true
    ImGui.LogToClipboard(ctx)
    ImGui.LogText(ctx, summary .. '\n\n')
  end
  ImGui.Spacing(ctx)

  local flags =
    ImGui.TableFlags_Resizable() | ImGui.TableFlags_Reorderable() |
    ImGui.TableFlags_Hideable()  | ImGui.TableFlags_Sortable()    |
    ImGui.TableFlags_ScrollX()   | ImGui.TableFlags_ScrollY()     |
    ImGui.TableFlags_Borders()   | ImGui.TableFlags_RowBg()
  if not ImGui.BeginTable(ctx, 'table', 13, flags) then
    return ImGui.EndChild(ctx)
  end
  ImGui.TableSetupScrollFreeze(ctx, 0, 1)
  ImGui.TableSetupColumn(ctx, 'Name')
  ImGui.TableSetupColumn(ctx, 'Source')
  ImGui.TableSetupColumn(ctx, 'Line')
  ImGui.TableSetupColumn(ctx, '%',
    ImGui.TableColumnFlags_WidthStretch() |
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'Time',
    ImGui.TableColumnFlags_DefaultSort() |
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'Calls',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'Frames',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'MinT/c',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'AvgT/c',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'MaxT/c',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'MinC/f',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'AvgC/f',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'MaxC/f',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableHeadersRow(ctx)

  local clipper = clippers[ctx]
  if not ImGui.ValidatePtr(clipper, 'ImGui_ListClipper*') then
    clipper = ImGui.CreateListClipper(ctx)
    clippers[ctx] = clipper
  end

  local cut_src_cache = {}

  ImGui.ListClipper_Begin(clipper, #report)
  while ImGui.ListClipper_Step(clipper) do
    local display_start, display_end = ImGui.ListClipper_GetDisplayRange(clipper)
    for i = display_start + 1, display_end do
      local line = report[i]
      ImGui.TableNextRow(ctx)
      ImGui.PushID(ctx, i)

      ImGui.TableNextColumn(ctx)
      ImGui.Text(ctx, string_format('%s', line.name))

      ImGui.TableNextColumn(ctx)
      local src_short = cut_src_cache[line.src_short]
      if not src_short then
        src_short = ellipsis(ctx, line.src_short)
        cut_src_cache[line.src_short] = src_short
      end
      ImGui.Text(ctx, src_short)
      if src_short ~= line.src and
          ImGui.IsItemHovered(ctx) and ImGui.BeginTooltip(ctx) then
        ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 42)
        ImGui.Text(ctx, line.src)
        ImGui.PopTextWrapPos(ctx)
        ImGui.EndTooltip(ctx)
      end

      ImGui.TableNextColumn(ctx)
      alignNextItemRight(ctx, line.src_line)
      ImGui.Text(ctx, line.src_line)

      ImGui.TableNextColumn(ctx)
      ImGui.ProgressBar(ctx, line.time_frac, nil, ImGui.GetFontSize(ctx),
        string_format('%.02f%%', line.time_frac * 100))

      ImGui.TableNextColumn(ctx)
      local time = formatTime(line.time, true)
      alignNextItemRight(ctx, time)
      ImGui.Text(ctx, time)

      ImGui.TableNextColumn(ctx)
      local count = formatNumber(line.count)
      alignNextItemRight(ctx, count)
      ImGui.Text(ctx, count)

      ImGui.TableNextColumn(ctx)
      local frames = formatNumber(line.frames)
      alignNextItemRight(ctx, frames)
      ImGui.Text(ctx, frames)

      ImGui.TableNextColumn(ctx)
      local time = formatTime(line.min_time, true)
      alignNextItemRight(ctx, time)
      ImGui.Text(ctx, time)

      ImGui.TableNextColumn(ctx)
      local time = formatTime(line.avg_time, true)
      alignNextItemRight(ctx, time)
      ImGui.Text(ctx, time)

      ImGui.TableNextColumn(ctx)
      local time = formatTime(line.max_time, true)
      alignNextItemRight(ctx, time)
      ImGui.Text(ctx, time)

      ImGui.TableNextColumn(ctx)
      local min_frame = formatNumber(line.min_frame)
      alignNextItemRight(ctx, min_frame)
      ImGui.Text(ctx, min_frame)

      ImGui.TableNextColumn(ctx)
      local avg_frame = formatNumber(line.avg_frame)
      alignNextItemRight(ctx, avg_frame)
      ImGui.Text(ctx, avg_frame)

      ImGui.TableNextColumn(ctx)
      local max_frame = formatNumber(line.max_frame)
      alignNextItemRight(ctx, max_frame)
      ImGui.Text(ctx, max_frame)

      ImGui.PopID(ctx)
    end
  end
  ImGui.EndTable(ctx)

  if export then ImGui.LogFinish(ctx) end

  ImGui.EndChild(ctx)
end

function profiler.defer(callback)
  called_defer = true
  if not auto_active then return reaper_defer(callback) end

  reaper_defer(function()
    called_defer = false
    profiler.start()
    callback()
    profiler.stop()
    profiler.frame()
  end)
end

function profiler.run()
  local ctx = ImGui.CreateContext(SCRIPT_NAME)
  local function loop()
    if profiler.showWindow(ctx, true) then
      reaper_defer(loop)
    end
  end
  reaper_defer(loop)
end

profiler.reset()

return profiler
