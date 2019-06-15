local UNDO_STATE_FX = 2 -- track/master fx

local name = ({reaper.get_action_context()})[2]:match("([^/\\_]+).lua$")
local mode = ({Bypass=false, Unbypass=true})[name:match('^(%w+)')]
local fxIndex = tonumber(name:match("FX (%d+)"))

if fxIndex then
  fxIndex = 0x1000000 + (fxIndex - 1)
else
  error('could not extract slot from filename')
end

reaper.Undo_BeginBlock()

local master = reaper.GetMasterTrack()

if mode == nil then -- toggle
  mode = not reaper.TrackFX_GetEnabled(master, fxIndex)
end

reaper.TrackFX_SetEnabled(master, fxIndex, mode)

reaper.Undo_EndBlock(name, UNDO_STATE_FX)

