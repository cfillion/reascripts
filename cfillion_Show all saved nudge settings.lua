-- @description Show all saved nudge settings
-- @version 2.0.1
-- @changelog
--   close the nudge dialog without saving when clicking on the edit button
--   highlight the corresponding button when triggering a keyboard shortcut
--   show value of the copies setting in nudge/duplicate mode
-- @author cfillion
-- @link cfillion.ca https://cfillion.ca
-- @donation https://www.paypal.me/cfillion
-- @screenshot https://i.imgur.com/5o3OIyf.png
-- @about
--   # Show all saved nudge settings
--
--   This script allows viewing, editing and using all nudge setting presets in
--   a single window.
--
--   The edit feature opens the native nudge settings dialog with the current
--   settings filled. The new settings are automatically saved into the selected
--   1-8 slot once the native dialog is closed. Trigger the edit feature a second
--   time to close the native dialog without saving.
--
--   ## Keyboard Shortcuts
--
--   - Switch to a different nudge setting with the **0-8** keys
--   - Edit the current nudge setting by pressing **Space**
--   - Nudge with the **left/right arrow** keys
--   - Close the window with **Escape**
--
--   ## Caveats
--
--   The "Last" tab may be out of sync with the effective last nudge settings.
--   This is because the native "Nudge left/right by saved nudge dialog settings X"
--   actions do not save the nudge settings in reaper.ini when they change the
--   last used settings.
--
--   There is no reliable way for a script to detect whether the last nudge
--   settings are out of sync. A workaround for forcing REAPER to save its
--   settings is to open and close the native nudge dialog.
--
--   Furthermore, REAPER does not store the nudge amout when using the "Set" mode
--   in the native nudge dialog. The script displays "N/A" in this case.

local WHAT_MAP = {'position', 'left trim', 'left edge', 'right trim', 'contents',
  'duplicate', 'edit cursor', 'end position'}

local UNIT_MAP =  {'milliseconds', 'seconds', 'grid units', 'notes',
  [17]='measures.beats', [18]='samples', [19]='frames', [20]='pixels',
  [21]='item lengths', [22]='item selections'}

local NOTE_MAP = {'1/256', '1/128', '1/64', '1/32T', '1/32', '1/16T', '1/16',
  '1/8T', '1/8', '1/4T', '1/4', '1/2', 'whole'}

local NUDGEDLG_ACTION = 41228
local SAVE_ACTIONS = {last=0, bank1=41271, bank2=41283}
local LNUDGE_ACTIONS = {last=41250, bank1=41279, bank2=41291}
local RNUDGE_ACTIONS = {last=41249, bank1=41275, bank2=41287}

local WIN_PADDING = 10
local BOX_PADDING = 7

local KEY_SPACE = 0x20
local KEY_ESCAPE = 0x1b
local KEY_LEFT = 0x6c656674
local KEY_RIGHT = 0x72676874
local KEY_F1 = 0x6631

local EXT_SECTION = 'cfillion_show_nudge_settings'
local EXT_WINDOW_STATE = 'windowState'

local exit = false
local mouseDown = false
local mouseClick = false
local iniFile = reaper.get_ini_file()
local setting = {}
local isEditing = false

local scriptName = ({reaper.get_action_context()})[2]:match("([^/\\_]+).lua$")

function iniRead(key, n)
  if n > 0 then
    key = string.format('%s_%d', key, n)
  end

  return tonumber(({reaper.BR_Win32_GetPrivateProfileString(
    'REAPER', key, '0', iniFile)})[2])
end

function boolValue(val, off, on)
  if not off then off = 'OFF' end
  if not on then on = 'ON' end

  if val == 0 then
    return off
  else
    return on
  end
end

function mapValue(val, strings)
  return strings[val] or string.format('%d (Unknown)', val)
end

function isAny(val, array)
  for _,n in ipairs(array) do
    if val == n then
      return true
    end
  end

  return false
end

function snapTo(unit)
  if isAny(unit, {3, 21, 22}) then
    return 'grid'
  elseif unit == 17 then -- measures.beats
    return 'bar'
  end

  return 'unit'
end

function loadSetting(n, reload)
  local changed = setting.n ~= n
  if not changed and not reload then return end

  setting = {n=n}

  local nudge = iniRead('nudge', n)
  setting.mode = nudge & 1
  setting.what = (nudge >> 12) + 1
  setting.unit = (nudge >> 4 & 0xFF) + 1
  setting.snap = nudge & 2
  setting.rel = nudge & 4

  if setting.unit >= 4 and setting.unit <= 16 then
    setting.note = setting.unit - 3
    setting.unit = 4
  end

  if setting.mode == 0 then
    setting.amount = iniRead('nudgeamt', n)
  else
    setting.amount = '(N/A)'
  end

  setting.copies = iniRead('nudgecopies', n)
end

function action(ids)
  local base

  if setting.n == 0 then
    return ids.last
  elseif setting.n < 5 then
    base = ids.bank1
  else
    base = ids.bank2
  end

  return base + ((setting.n - 1) % 4)
end

function nudgeLeft()
  reaper.Main_OnCommand(action(LNUDGE_ACTIONS), 0)
end

function nudgeRight()
  reaper.Main_OnCommand(action(RNUDGE_ACTIONS), 0)
end

function setAsLast()
  local count = reaper.CountSelectedMediaItems(0)
  local selection = {}
  for i=0,count - 1 do
    local item = reaper.GetSelectedMediaItem(0, 0)
    table.insert(selection, item)
    reaper.SetMediaItemSelected(item, false)
  end

  nudgeRight()

  for _,item in ipairs(selection) do
    reaper.SetMediaItemSelected(item, true)
  end
end

function editCurrent()
  if setting.n > 0 then
    setAsLast()
  end

  reaper.Main_OnCommand(NUDGEDLG_ACTION, 0)
end

function saveCurrent()
  reaper.Main_OnCommand(action(SAVE_ACTIONS), 0)
  loadSetting(setting.n, true)
end

function help()
  if not reaper.ReaPack_GetOwner then
    reaper.MB('This feature requires ReaPack v1.2 or newer.', scriptName, 0)
    return
  end

  local owner = reaper.ReaPack_GetOwner(({reaper.get_action_context()})[2])

  if not owner then
    reaper.MB(string.format(
      'This feature is unavailable because "%s" was not installed using ReaPack.',
      scriptName), scriptName, 0)
    return
  end

  reaper.ReaPack_AboutInstalledPackage(owner)
  reaper.ReaPack_FreeEntry(owner)
end

function boxRect(box)
  local x, y = gfx.x, gfx.y
  local w, h = gfx.measurestr(box.text)

  w = w + (BOX_PADDING * 2)
  h = h + BOX_PADDING

  if box.w then w = box.w end
  if box.h then h = box.h end

  return {x=x, y=y, w=w, h=h}
end

function drawBox(box)
  if not box.color then box.color = {255, 255, 255} end

  setColor(box.color)
  gfx.rect(box.rect.x + 1, box.rect.y + 1, box.rect.w - 2, box.rect.h - 2, true)

  gfx.x = box.rect.x
  setColor({42, 42, 42})
  if not box.noborder then
    gfx.rect(box.rect.x, box.rect.y, box.rect.w, box.rect.h, false)
  end
  gfx.x = box.rect.x + BOX_PADDING
  gfx.drawstr(box.text, 4, gfx.x + box.rect.w - (BOX_PADDING * 2), gfx.y + box.rect.h + 2)

  gfx.x = box.rect.x + box.rect.w + BOX_PADDING
end

function box(box)
  box.rect = boxRect(box)
  drawBox(box)
end

function button(box)
  if not box.rect then box.rect = boxRect(box) end

  local underMouse =
    gfx.mouse_x >= box.rect.x and
    gfx.mouse_x < box.rect.x + box.rect.w and
    gfx.mouse_y >= box.rect.y and
    gfx.mouse_y < box.rect.y + box.rect.h

  local kbTrigger = key == box.shortcut

  if (mouseClick and underMouse) or kbTrigger then
    box.callback()
    if box.active ~= nil then
      box.active = true
    end
  end

  if box.active then
    box.color = {150, 175, 225}
  elseif (underMouse and mouseDown) or kbTrigger then
    box.color = {120, 120, 120}
  else
    box.color = {220, 220, 220}
  end

  drawBox(box)
end

function rtlToolbar(x, btns)
  local leftmost = gfx.x
  gfx.x = (gfx.w - x)

  for i=#btns,1,-1 do
    local btn = btns[i]
    btn.rect = boxRect(btn)
    gfx.x = btn.rect.x - btn.rect.w - BOX_PADDING
  end

  gfx.x = math.max(leftmost, gfx.x + BOX_PADDING)

  for _,btn in ipairs(btns) do
    btn.rect.x = gfx.x
    button(btn)
  end
end

function draw()
  gfx.x, gfx.y = WIN_PADDING, WIN_PADDING
  button({text='Last', active=setting.n == 0, shortcut=string.byte('0'),
    callback=function() loadSetting(0) end})
  for i=1,8 do
    button({text=i, active=setting.n == i, shortcut=string.byte(i),
      callback=function() loadSetting(i) end})
  end

  rtlToolbar(WIN_PADDING, {
    {text='Edit', active=isEditing, shortcut=KEY_SPACE, callback=editCurrent},
    {text='?', shortcut=KEY_F1, callback=help},
  })

  gfx.x, gfx.y = WIN_PADDING, 38
  box({w=70, text=boolValue(setting.mode, 'Nudge', 'Set')})
  box({w=100, text=mapValue(setting.what, WHAT_MAP)})
  box({noborder=true, text=boolValue(setting.mode, 'by:', 'to:')})
  box({w=70, text=setting.amount})
  if setting.note then
    box({w=50, text=mapValue(setting.note, NOTE_MAP)})
  end
  box({w=gfx.w - gfx.x - WIN_PADDING, text=mapValue(setting.unit, UNIT_MAP)})

  gfx.x, gfx.y = WIN_PADDING - BOX_PADDING, 66
  box({text=string.format('Snap to %s: %s', snapTo(setting.unit),
    boolValue(setting.snap)), noborder=true})

  gfx.x = 110
  if setting.mode == 1 and isAny(setting.what, {1, 6, 8}) then
    box({text=string.format('Relative set: %s', boolValue(setting.rel)), noborder=true})
  elseif setting.what == 6 then
    box({text=string.format('Copies: %s', setting.copies), noborder=true})
  end

  rtlToolbar(WIN_PADDING, {
    {text='< Nudge left', shortcut=KEY_LEFT, callback=nudgeLeft},
    {text='Nudge right >', shortcut=KEY_RIGHT, callback=nudgeRight},
  })
end

function setColor(color)
  gfx.r = color[1] / 255.0
  gfx.g = color[2] / 255.0
  gfx.b = color[3] / 255.0
end

function keyboardInput()
  key = gfx.getchar()

  if key < 0 then
    exit = true
  elseif key == KEY_ESCAPE then
    gfx.quit()
  end
end

function detectEdit()
  local state = reaper.GetToggleCommandState(NUDGEDLG_ACTION) == 1
  if isEditing and not state then
    saveCurrent()
  end

  isEditing = state
end

function mouseInput()
  if mouseClick then
    mouseClick = false
  elseif gfx.mouse_cap == 1 then
    mouseDown = true
  elseif mouseDown then
    mouseClick = true
    mouseDown = false
  elseif mouseClick then
    mouseClick = false
  end
end

function loop()
  detectEdit()
  keyboardInput()
  mouseInput()

  if exit then return end

  gfx.clear = 16777215
  draw()
  gfx.update()

  if not exit then
    reaper.defer(loop)
  else
    gfx.quit()
  end
end

function previousWindowState()
  local state = tostring(reaper.GetExtState(EXT_SECTION, EXT_WINDOW_STATE))
  return state:match("^(%d+) (%d+) (%d+) (-?%d+) (-?%d+)$")
end

function saveWindowState()
  local dockState, xpos, ypos = gfx.dock(-1, 0, 0, 0, 0)
  local w, h = gfx.w, gfx.h
  if dockState > 0 then
    w, h = previousWindowState()
  end

  reaper.SetExtState(EXT_SECTION, EXT_WINDOW_STATE,
    string.format("%d %d %d %d %d", w, h, dockState, xpos, ypos), true)
end

local w, h, dockState, x, y = previousWindowState()

if w then
  gfx.init(scriptName, w, h, dockState, x, y)
else
  gfx.init(scriptName, 475, 97)
end

if reaper.GetAppVersion():match('OSX') then
  gfx.setfont(1, 'sans-serif', 12)
else
  gfx.setfont(1, 'sans-serif', 15)
end

reaper.atexit(saveWindowState)

loadSetting(0)
loop()
