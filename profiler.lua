local ImGui = (function()
  local host_reaper = reaper
  reaper = {}
  for k,v in pairs(host_reaper) do reaper[k] = v end
  dofile(reaper.GetResourcePath() ..
    '/Scripts/ReaTeam Extensions/API/imgui.lua')('0.8.7')
  local ImGui = {}
  for name, func in pairs(reaper) do
    name = name:match('^ImGui_(.+)$')
    if name then ImGui[name] = func end
  end
  reaper = host_reaper
  return ImGui
end)()

local SCRIPT_NAME = 'Lua profiler'
local FLT_MIN = ImGui.NumericLimits_Float()
local PROFILES_SIZE = 8

local profiler, profiles, current = {}, {}, 1
local attachments, wrappers, locations, clippers = {}, {}, {}, {}
local active, auto_active, show_metrics = false, false, false
local defer_called, scroll_to_top = false, false
local getTime = reaper.time_precise -- faster than os.clock
local profile, profile_data -- references to profiles[current] for quick access

-- cache stdlib constants and funcs to not break if the host script changes them
-- + don't count the profiler's own use of them in measurements
local math_huge = math.huge
local assert, error, type, pairs, print = assert, error, type, pairs, print
local tostring, select, getmetatable  = tostring, select, getmetatable
local debug_getlocal, debug_setlocal  = debug.getlocal, debug.setlocal
local debug_getinfo,  collectgarbage  = debug.getinfo,  collectgarbage
local math_min,       math_max        = math.min,       math.max
local math_log,       math_floor      = math.log,       math.floor
local string_gsub,    string_match    = string.gsub,    string.match
local string_find,    string_format   = string.find,    string.format
local string_sub,     string_rep      = string.sub,     string.rep
local utf8_len,       utf8_offset     = utf8.len,       utf8.offset
local table_sort                      = table.sort
local reaper_defer,   CF_ShellExecute = reaper.defer,   reaper.CF_ShellExecute
local reaper_get_action_context = reaper.get_action_context

assert(debug_getinfo(debug_getlocal, 'S').what == 'C',
  'global environment is tainted, stack depths will be incorrect')

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
  if not time then return end
  if pad == nil then pad = true end
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

local function alignGroupRight(ctx, callback)
  local pos_x, right_x = ImGui.GetCursorPosX(ctx), ImGui.GetContentRegionMax(ctx)

  ImGui.BeginGroup(ctx)
  ImGui.PushID(ctx, 'width')
  ImGui.PushClipRect(ctx, 0, 0, 1, 1, false)
  callback()
  ImGui.PopClipRect(ctx)
  ImGui.PopID(ctx)
  ImGui.EndGroup(ctx)

  local want_pos = right_x - ImGui.GetItemRectSize(ctx)
  if want_pos >= pos_x then
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, want_pos)
  end

  ImGui.BeginGroup(ctx)
  callback()
  ImGui.EndGroup(ctx)
end

local function tooltip(ctx, text)
  if not ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort()) or
    not ImGui.BeginTooltip(ctx) then return end
  ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 42)
  ImGui.Text(ctx, text)
  ImGui.PopTextWrapPos(ctx)
  ImGui.EndTooltip(ctx)
end

local function textCell(ctx, value, right_align, custom_tooltip)
  if right_align == nil then right_align = true end
  if right_align then alignNextItemRight(ctx, value) end
  ImGui.Text(ctx, value)
  if (custom_tooltip and custom_tooltip ~= value) or
      ImGui.CalcTextSize(ctx, value) > ImGui.GetContentRegionAvail(ctx) then
    tooltip(ctx, custom_tooltip or value)
  end
end

local function enter(what, alias)
  profile.dirty = true

  local line = profile_data[what]
  if not line then
    line = {
      name = alias, count = 0, time = 0,
      enter_time = 0, enter_count = 0,
      frames = 0, prev_count = 0, prev_time = 0,
      time_per_call = {}, time_per_frame = {}, calls_per_frame = {},
    }
    profile_data[what] = line
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
  local line = profile_data[what]
  if not line or line.enter_count < 1 then
    error('unbalanced leave (missing call to enter)')
  end
  local time = now - line.enter_time
  if not line.time_per_call.min or time < line.time_per_call.min then
    line.time_per_call.min = time
  end
  if not line.time_per_call.max or time > line.time_per_call.max then
    line.time_per_call.max = time
  end
  line.time = line.time + time
  line.enter_time, line.enter_count = now, line.enter_count - 1
end

local function setActive(activate)
  if activate then
    if defer_called then
      auto_active = true
      profile.user_start_time = getTime()
    else
      profiler.start()
      profile.user_start_time = profile.start_time
    end
  else
    if active then
      profiler.stop()
    else
      auto_active = false
    end
  end
end

local function setCurrentProfile(i)
  local now = getTime()

  current = i
  if not profiles[i] then
    profiler.reset()
  else
    profile, profile_data = profiles[i], profiles[i].data
  end

  if active then
    profile.start_time, profile.user_start_time = now, now
  elseif auto_active then
    profile.user_start_time = now
  end

  scroll_to_top = true
end

local function updateProfile()
  local now = getTime()

  -- update active time
  if active then
    profile.time = profile.time + (now - profile.start_time)
    profile.start_time = now
  end

  -- update wall time
  local total_time = profile.total_time
  if total_time then
    profile.total_time = total_time + (now - profile.user_start_time)
  else
    -- don't include defer timer interval in single-shot reports
    profile.total_time = profile.time
  end
  profile.user_start_time = now

  profile.report = {}

  for key, line in pairs(profile_data) do
    assert(line.enter_count == 0, 'unbalanced enter (missing call to leave)')

    local location = locations[key]
    local src, src_short, src_line = '<unknown>',  '<unknown>', -1
    if location then
      src = string_gsub(location.source, '^[@=]', '')
      src_short = basename(location.short_src)
      src_line = location.linedefined
    end

    profile.report[#profile.report + 1] = { -- immutable copy of the line
      name = line.name, time = line.time, count = line.count,
      time_frac = line.time / profile.time,
      src = src, src_short = src_short, src_line = src_line,
      frames = line.frames > 0 and line.frames,

      time_per_call = {
        min = line.time_per_call.min, max = line.time_per_call.max,
        avg = line.time / line.count,
      },
      time_per_frame = {
        min = line.time_per_frame.min, max = line.time_per_frame.max,
        avg = line.frames > 0 and line.time / line.frames,
      },
      calls_per_frame = {
        min = line.calls_per_frame.min, max = line.calls_per_frame.max,
        avg = line.frames > 0 and line.count // line.frames,
      },
    }
  end

  table_sort(profile.report, function(a, b) return a.time > b.time end)
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

  local off, sep = 1, string_find(path, '[%.`]')
  local seg = string_sub(path, off, sep and sep - 1)
  local match, local_idx, parent

  for l, i, name, value in eachLocals(level, true) do
    if name == seg then
      level, local_idx, match = l, i, value
      break
    end
  end

  if not match then parent, match = _G, _G[seg] end

  while match and sep do
    local is_special = string_sub(path, sep, sep) ~= '.'

    off = sep + 1
    sep = string_find(path, '[%.`]', off)
    seg = string_sub(path, off, sep and sep - 1)
    local_idx = nil

    if is_special then
      if seg == 'meta' then
        parent, match = nil, getmetatable(match)
      else
        match = nil
        break
      end
    else
      assert(type(match) == 'table',
        string_format('%s is not a table', string_sub(path, 1, sep and sep - 1)))
      parent, match = match, match[seg]
    end
  end

  assert(match, string_format('variable not found: %s',
    string_sub(path, 1, sep and sep - 1)))

  return match, level - 1, local_idx, parent, seg
end

local attachToTable

local function attach(is_attach, name, value, opts, depth, in_metatable)
  -- prevent infinite recursion
  for k, v in pairs(profiler) do
    if value == v then return end
  end

  if opts.metatable then
    local metatable = getmetatable(value)
    if metatable then
      attachToTable(is_attach, name .. '`meta', metatable, opts, depth, true)
    end
  end

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
  elseif t == 'table' and depth < 8 and not in_metatable and
      (depth == 0 or (opts.recursive and value ~= _G)) then
    -- don't dig into metatables to avoid listing (for example) string.byte
    -- as some_string_value`meta.__index.byte
    attachToTable(is_attach, name, value, opts, depth + 1)
    return true
  end

  return false
end

attachToTable = function(is_attach, prefix, array, opts, depth, in_metatable)
  assert(type(array) == 'table', string_format('%s is not a table', prefix))

  if array == package.loaded then return end

  for name, value in pairs(array) do
    local path = name
    if prefix then path = string_format('%s.%s', prefix, name) end
    local ok, wrapper = attach(is_attach, path, value, opts, depth, in_metatable)
    if wrapper then array[name] = wrapper end
  end
end

local function attachToLocals(is_attach, opts)
  for level, idx, name, value in eachLocals(3, opts.search_above) do
    local ok, wrapper = attach(is_attach, name, value, opts, 1)
    if wrapper then debug_setlocal(level, idx, wrapper) end
  end
end

local function attachToVar(is_attach, var, opts)
  local val, level, idx, parent, parent_key = getHostVar(var, 4)
  -- start at depth=0 to attach to tables by name with opts.recursion=false
  local ok, wrapper = attach(is_attach, var, val, opts, 0)
  assert(ok, string_format('%s is not %s',
    var, is_attach and 'attachable' or 'detachable'))
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
  attachToTable(true, nil, _G, opts, 1)
end

function profiler.detachFromWorld()
  local opts = makeOpts()
  attachToLocals(false, opts)
  attachToTable(false, nil, _G, opts, 1)
end

function profiler.reset()
  profiles[current] = {
    time   = 0,
    data   = {},
    report = {},
    start_time = active and getTime(),
    -- no need to initialize user_start_time because total_time isn't initialized
  }
  profile, profile_data = profiles[current], profiles[current].data
end

function profiler.start()
  assert(not active, 'profiler is already active')
  active = true

  -- prevent the garbage collector from affecting measurement repeatability
  collectgarbage('stop')

  local now = getTime()
  profile.start_time = now
  if not profile.user_start_time then
    profile.user_start_time = now
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

function profiler.stop()
  assert(active, 'profiler is not active')
  profile.time = profile.time + (getTime() - profile.start_time)
  profile.dirty = true -- have updateProfile refresh total_time and update %
  active = false

  collectgarbage('restart')
end

function profiler.frame()
  for key, line in pairs(profile_data) do
    if line.enter_count > 0 then error('frame was called before leave') end
    if line.count > line.prev_count then
      local count = line.count - line.prev_count
      line.frames, line.prev_count = line.frames + 1, line.count
      if not line.calls_per_frame.min or count < line.calls_per_frame.min then
        line.calls_per_frame.min = count
      end
      if not line.calls_per_frame.max or count > line.calls_per_frame.max then
        line.calls_per_frame.max = count
      end

      local time = line.time - line.prev_time
      line.prev_time = line.time
      if not line.time_per_frame.min or time < line.time_per_frame.min then
        line.time_per_frame.min = time
      end
      if not line.time_per_frame.max or time > line.time_per_frame.max then
        line.time_per_frame.max = time
      end
    end
  end
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
        if defer_called then
          setActive(true)
        else
          open_no_defer_popup = true
        end
      end
      if ImGui.MenuItem(ctx, 'Stop', nil, nil, is_active) then
        setActive(false)
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx, 'Profile') then
      local has_data = profile.start_time ~= nil
      if ImGui.MenuItem(ctx, 'Reset', nil, nil, has_data) then
        profiler.reset()
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
    ImGui.OpenPopup(ctx, 'Frame measurement')
  end
  centerNextWindow(ctx)
  if ImGui.BeginPopupModal(ctx, 'Frame measurement', true,
      ImGui.WindowFlags_AlwaysAutoResize()) then
    ImGui.Text(ctx,
      'Frame measurement requires usage of a proxy defer function.')
    ImGui.Spacing(ctx)

    ImGui.Text(ctx, 'The following measurements are affected:')
    ImGui.Bullet(ctx); ImGui.Text(ctx, 'Active time')
    ImGui.Bullet(ctx); ImGui.Text(ctx, 'Frame count')
    ImGui.Bullet(ctx); ImGui.Text(ctx, 'Time per frame (min/avg/max)')
    ImGui.Bullet(ctx); ImGui.Text(ctx, 'Calls per frame (min/avg/max)')
    ImGui.Spacing(ctx)

    ImGui.Text(ctx,
      'Add the following snippet to the host script:')
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx)
    end
    local snippet = 'reaper.defer = profiler.defer'
    ImGui.InputTextMultiline(ctx, '##snippet', snippet,
      -FLT_MIN, ImGui.GetFontSize(ctx) * 3, ImGui.InputTextFlags_ReadOnly())
    ImGui.Spacing(ctx)

    ImGui.Text(ctx, 'Do you wish to enable acquisition anyway?')
    ImGui.Spacing(ctx)

    if ImGui.Button(ctx, 'Continue') then
      setActive(true)
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Inject proxy and continue') then
      reaper.defer, defer_called = profiler.defer, true
      setActive(true)
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Cancel') then
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  if ImGui.IsWindowFocused(ctx) then
    ImGui.SetNextWindowFocus(ctx)
  end
  profiler.showReport(ctx, 'report', 0, 0)

  ImGui.End(ctx)
  return p_open
end

function profiler.showReport(ctx, label, width, height)
  if not ImGui.BeginChild(ctx, label, width, height) then return end

  if ImGui.IsWindowAppearing(ctx) then
    ImGui.SetKeyboardFocusHere(ctx)
  end
  if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_ChildWindows()) then
    local key_0, pad_0 = ImGui.Key_0(), ImGui.Key_Keypad0()
    for i = 1, PROFILES_SIZE do
      if ImGui.IsKeyPressed(ctx, key_0 + i) or
          ImGui.IsKeyPressed(ctx, pad_0 + i) then
        setCurrentProfile(i)
      end
    end
  end

  local was_dirty = profile.dirty
  if was_dirty then
    profile.dirty = false
    updateProfile()
  end

  local summary
  if #profile.report < 1 then
    summary = 'No profiling data has been acquired yet.'
  else
    summary = string_format('Active time / wall time: %s / %s (%.02f%%)',
      formatTime(profile.time, false), formatTime(profile.total_time, false),
      (profile.time / profile.total_time) * 100)
  end
  ImGui.Text(ctx, summary)
  if was_dirty then
    ImGui.SameLine(ctx, nil, 0)
    ImGui.Text(ctx, string_format('%-3s',
      string_rep('.', ImGui.GetTime(ctx) // 1 % 3 + 1)))
  end
  ImGui.SameLine(ctx)

  local export = false
  alignGroupRight(ctx, function()
    for i = 1, PROFILES_SIZE do
      if i > 1 then ImGui.SameLine(ctx, nil, 4) end
      local was_current = i == current
      if was_current then
        ImGui.PushStyleColor(ctx, ImGui.Col_Button(),
          ImGui.GetStyleColor(ctx, ImGui.Col_HeaderActive()))
      end
      if ImGui.SmallButton(ctx, i) then
        setCurrentProfile(i)
      end
      if was_current then
        ImGui.PopStyleColor(ctx)
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, 'Copy to clipboard') then
      export = true
      ImGui.LogToClipboard(ctx)
      ImGui.LogText(ctx, summary .. '\n\n')
    end
  end, true)
  ImGui.Spacing(ctx)

  if scroll_to_top then
    ImGui.SetNextWindowScroll(ctx, 0, 0)
    scroll_to_top = false
  end
  local flags =
    ImGui.TableFlags_Resizable() | ImGui.TableFlags_Reorderable() |
    ImGui.TableFlags_Hideable()  | ImGui.TableFlags_Sortable()    |
    ImGui.TableFlags_ScrollX()   | ImGui.TableFlags_ScrollY()     |
    ImGui.TableFlags_Borders()   | ImGui.TableFlags_RowBg()
  if not ImGui.BeginTable(ctx, 'table', 16, flags) then
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
  ImGui.TableSetupColumn(ctx, 'MinT/c',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'AvgT/c',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'MaxT/c',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'Frames',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'MinT/f',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'AvgT/f',
    ImGui.TableColumnFlags_PreferSortDescending())
  ImGui.TableSetupColumn(ctx, 'MaxT/f',
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
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding(), 1, 1)
  ImGui.ListClipper_Begin(clipper, #profile.report)
  while ImGui.ListClipper_Step(clipper) do
    local display_start, display_end = ImGui.ListClipper_GetDisplayRange(clipper)
    for i = display_start + 1, display_end do
      local line = profile.report[i]
      ImGui.TableNextRow(ctx)
      ImGui.PushID(ctx, i)

      ImGui.TableNextColumn(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      textCell(ctx, line.name, false)

      ImGui.TableNextColumn(ctx)
      local src_short = cut_src_cache[line.src_short]
      if not src_short then
        src_short = ellipsis(ctx, line.src_short)
        cut_src_cache[line.src_short] = src_short
      end
      textCell(ctx, src_short, false, line.src)

      ImGui.TableNextColumn(ctx)
      textCell(ctx, line.src_line)

      ImGui.TableNextColumn(ctx)
      ImGui.ProgressBar(ctx, line.time_frac, nil, nil,
        string_format('%.02f%%', line.time_frac * 100))

      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatTime(line.time))
      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatNumber(line.count))

      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatTime(line.time_per_call.min))
      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatTime(line.time_per_call.avg))
      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatTime(line.time_per_call.max))

      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatNumber(line.frames))

      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatTime(line.time_per_frame.min))
      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatTime(line.time_per_frame.avg))
      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatTime(line.time_per_frame.max))

      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatNumber(line.calls_per_frame.min))
      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatNumber(line.calls_per_frame.avg))
      ImGui.TableNextColumn(ctx)
      textCell(ctx, formatNumber(line.calls_per_frame.max))

      ImGui.PopID(ctx)
    end
  end
  ImGui.PopStyleVar(ctx)
  ImGui.EndTable(ctx)

  if export then ImGui.LogFinish(ctx) end

  ImGui.EndChild(ctx)
end

function profiler.defer(callback)
  defer_called = true
  if not auto_active then return reaper_defer(callback) end

  return reaper_defer(function()
    defer_called = false
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
