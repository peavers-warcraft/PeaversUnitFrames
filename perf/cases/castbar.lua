--------------------------------------------------------------------------------
-- Ultra Performance case: the unit frame cast bars.
--
-- The cast bars are the only thing in this addon that runs every frame - health,
-- power and auras are all event driven - so they are the whole per-frame story.
-- Four bars can be live at once (player, target, target of target, focus), and
-- the budget is written against one bar; the runner reports the per-bar figure
-- because that is what scales with how many frames the user has enabled.
--------------------------------------------------------------------------------

local Stubs = dofile(HARNESS_LIB .. "/wow-stubs.lua").Install()

--------------------------------------------------------------------------------
-- Addon-side scaffolding
--------------------------------------------------------------------------------

-- Only the surface CastBar.lua touches at load time. A perf case measures one file,
-- so stubbing the whole framework here would be scaffolding nothing reads.
---@diagnostic disable-next-line: missing-fields
_G.PeaversCommons = {
    Utils = {
        GetDefaultFont = function() return "Fonts\\FRIZQT__.TTF" end,
        SafeSetFont = function() end,
    },
}

local PUF = { name = "PeaversUnitFrames" }

-- Style.lua is loaded for real: its secret-value guards sit on the per-frame
-- path, so stubbing them out would measure something the addon does not do.
assert(loadfile(ADDON_DIR .. "/src/Core/Style.lua"))("PeaversUnitFrames", PUF)

local CastBar = assert(loadfile(ADDON_DIR .. "/src/UI/CastBar.lua"))("PeaversUnitFrames", PUF)

local CFG = {
    bgAlpha = 0.85,
    barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
    fontFace = "Fonts\\FRIZQT__.TTF",
    fontSize = 10,
}

--------------------------------------------------------------------------------

local cast, channel

_G.UnitCastingInfo = function()
    if not cast then return nil end
    return cast.name, cast.name, "icon", cast.startMs, cast.endMs, false, 1, false, 100
end
_G.UnitChannelInfo = function()
    if not channel then return nil end
    return channel.name, channel.name, "icon", channel.startMs, channel.endMs,
        false, false, 100, false, nil
end

local function NewBar()
    local parent = Stubs.NewFrame()
    local bar = CastBar.New(nil, parent, "player")
    bar:Layout(parent, CFG, 200, 18, true)
    bar:SetEnabled(true)
    return bar
end

local function MeasureCast(label, seconds, fps, isChannel)
    local bar = NewBar()
    Stubs.time = 1000

    local payload = {
        name = "Measured Spell",
        startMs = Stubs.time * 1000,
        endMs = (Stubs.time + seconds) * 1000,
    }
    if isChannel then channel, cast = payload, nil else cast, channel = payload, nil end

    bar:Refresh()

    local frames = math.floor(seconds * fps) - 2
    local perFrame = Stubs.Drive(function(dt) bar:OnUpdate(dt) end, frames, 1 / fps)

    cast, channel = nil, nil
    return {
        name = label,
        callsPerFrame = perFrame,
        notes = string.format("%d frames driven, one bar", frames),
    }
end

-- Nothing casting: the bar frame is hidden and WoW does not tick hidden frames.
local function MeasureIdle(fps)
    local bar = NewBar()
    Stubs.ResetCounts()
    local ticked = 0
    for _ = 1, fps do
        Stubs.time = Stubs.time + 1 / fps
        if bar.frame:IsShown() then
            bar:OnUpdate(1 / fps)
            ticked = ticked + 1
        end
    end
    return {
        name = "idle, nothing casting",
        callsPerFrame = 0,
        idleCallsPerSecond = Stubs.TotalCalls(),
        notes = ticked == 0 and "frame hidden, never ticked" or (ticked .. " frames ticked"),
    }
end

return {
    MeasureCast("cast bar, 2.5s at 144fps", 2.5, 144, false),
    MeasureCast("cast bar, 2.5s at 60fps", 2.5, 60, false),
    MeasureCast("channel, 3s at 144fps", 3.0, 144, true),
    MeasureIdle(144),
}
