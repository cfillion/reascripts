-- @description Move left/right edge of selected automation items to start/end of time selection

local UNDO_STATE_TRACKCFG = 1

local script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+).lua$")
local right_edge = script_name:match('right edge')

reaper.defer(function() end)

local tstart, tend = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
if tstart == tend then return end

local env = reaper.GetSelectedTrackEnvelope(nil)
if not env then return end

local bucket = {}

for i=0,reaper.CountAutomationItems(env)-1 do
  local selected = 1 == reaper.GetSetAutomationItemInfo(env, i, 'D_UISEL', 0, false)
  local startTime = reaper.GetSetAutomationItemInfo(env, i, 'D_POSITION', 0, false)
  local length = reaper.GetSetAutomationItemInfo(env, i, 'D_LENGTH', 0, false)

  if selected and startTime < tend then
    if right_edge then
      table.insert(bucket, {id=i, len=tend - startTime})
    else
      table.insert(bucket, {id=i, pos=tstart, len=length + (startTime - tstart)})
    end
  end
end

if #bucket < 1 then return end

reaper.Undo_BeginBlock()

for _,ai in ipairs(bucket) do
  if ai.pos then
    reaper.GetSetAutomationItemInfo(env, ai.id, 'D_POSITION', ai.pos, true)
  end

  reaper.GetSetAutomationItemInfo(env, ai.id, 'D_LENGTH', ai.len, true)
end

reaper.Undo_EndBlock(script_name, UNDO_STATE_TRACKCFG)
