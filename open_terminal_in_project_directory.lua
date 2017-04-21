-- escape function from shell.lua, by Peter Odding
-- https://github.com/lua-shellscript/lua-shellscript/wiki/shell.string
function escape(...)
  local command = type(...) == 'table' and ... or { ... }

  for i, s in ipairs(command) do
    s = (tostring(s) or ''):gsub('"', '\\"')

    if s:find '[^A-Za-z0-9_."/-]' then
      s = '"' .. s .. '"'
    elseif s == '' then
      s = '""'
    end

    command[i] = s
  end

  return table.concat(command, ' ')
end

-- dirname from nativeclient-sdk (chromium)
-- https://code.google.com/p/nativeclient-sdk/source/browse/trunk/src/nacltoons/data/res/path.lua
function dirname(filename)
  while true do
    if filename == "" or string.sub(filename, -1) == "/" then
      break
    end
    filename = string.sub(filename, 1, -2)
  end
  if filename == "" then
    filename = "."
  end

  return filename
end

local _, projectFile = reaper.EnumProjects(-1, '')
local path

if string.len(projectFile) == 0 then
  path = reaper.GetProjectPath('')
else
  path = dirname(projectFile)
end

os.execute("open -a Terminal.app " .. escape(path))
reaper.defer(function() end)
