local addonName, PUF = ...

--------------------------------------------------------------------------------
-- Blizzard frame suppression
--
-- The default player, target, target-of-target, focus and cast bars are secure
-- frames, so they are retired once at login and never touched again: reparenting
-- or hiding a protected frame during combat is blocked by the client and taints
-- everything downstream of it.
--
-- Turning the option back off deliberately requires a reload rather than trying
-- to restore protected frames mid-session.
--------------------------------------------------------------------------------

local Blizzard = {}
PUF.Blizzard = Blizzard

local hiddenParent

local function GetHiddenParent()
    if not hiddenParent then
        hiddenParent = CreateFrame("Frame", nil, UIParent)
        hiddenParent:Hide()
    end
    return hiddenParent
end

-- Outcome per frame, surfaced by /puf debug. Everything here is wrapped, because
-- these are protected frames and a refusal must not abort the rest of the sweep -
-- but a silent refusal is exactly how a stray Blizzard frame ends up on screen
-- with nothing to explain it, so the result is recorded rather than discarded.
Blizzard.status = {}

local hooked = {}

local function Disable(name)
    local frame = _G[name]
    if not frame then
        Blizzard.status[name] = "missing"
        return
    end

    -- Stop the frame driving itself before it is parked out of sight, otherwise
    -- Blizzard's own event handlers keep showing it again.
    if frame.UnregisterAllEvents then
        pcall(frame.UnregisterAllEvents, frame)
    end

    -- Secure unit frames are shown by a state driver rather than by Show().
    if frame.GetAttribute and frame:GetAttribute("unit") ~= nil then
        pcall(UnregisterUnitWatch, frame)
    end

    pcall(frame.Hide, frame)

    -- Edit Mode and Blizzard's own layout passes will happily Show() these again
    -- later in the session. A permanent OnShow hook is what actually keeps them
    -- down, and unlike reparenting it cannot be refused on a protected frame.
    if not hooked[name] then
        hooked[name] = true
        pcall(frame.HookScript, frame, "OnShow", function(f) f:Hide() end)
    end

    local reparented = pcall(frame.SetParent, frame, GetHiddenParent())

    local shown = frame.IsShown and frame:IsShown()
    if shown then
        Blizzard.status[name] = "STILL SHOWN"
    else
        Blizzard.status[name] = reparented and "hidden" or "hidden (not reparented)"
    end
end

-- Frames replaced by this addon. Anything not in this list (pet, party, boss,
-- nameplates) is left alone.
local FRAMES = {
    "PlayerFrame",
    "TargetFrame",
    "TargetFrameToT",
    "FocusFrame",
    "FocusFrameToT",
    "PlayerCastingBarFrame",
    "CastingBarFrame",
    "PetCastingBarFrame",
    -- The target's and focus's cast bars. Nominally children of their unit
    -- frame, but they are listed explicitly because Edit Mode can reparent them,
    -- at which point hiding the unit frame no longer takes them with it.
    "TargetFrameSpellBar",
    "FocusFrameSpellBar",
}

function Blizzard:Apply()
    if not PUF.Config.hideBlizzardFrames then return end
    if InCombatLockdown() then
        -- Login should never land here, but if it does the work is simply
        -- deferred rather than throwing a protected-frame error.
        self.pending = true
        return
    end

    self.pending = false

    for _, name in ipairs(FRAMES) do
        Disable(name)
    end

    -- Blizzard's buff frame is left in place; this addon only owns the four unit
    -- frames, so the player's own buff list stays where the user expects it.
end

function Blizzard:OnCombatEnd()
    if self.pending then
        self:Apply()
    end
end

return Blizzard
