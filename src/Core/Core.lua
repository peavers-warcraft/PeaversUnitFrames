local addonName, PUF = ...

--------------------------------------------------------------------------------
-- Core
--
-- Owns the four unit frames, routes game events to them, and keeps every
-- protected operation (position, size, unit watch) out of combat.
--------------------------------------------------------------------------------

local Style = PUF.Style
local UnitFrame = PUF.UnitFrame

local Core = {}
PUF.Core = Core

Core.frames = {}

-- Events that carry a unit token as their first argument.
local UNIT_EVENTS = {
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE",
    "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER",
    "UNIT_NAME_UPDATE",
    "UNIT_FACTION",
    "UNIT_CONNECTION",
    "UNIT_FLAGS",
    "UNIT_AURA",
}

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function Core:Initialize()
    for _, key in ipairs(PUF.Config.UNIT_ORDER) do
        self.frames[key] = UnitFrame:New(key, key)
    end

    self:BuildEventFrame()
    self:RefreshAll()
    self:StartTicker()
end

function Core:BuildEventFrame()
    local frame = CreateFrame("Frame")
    self.eventFrame = frame

    for _, event in ipairs(UNIT_EVENTS) do
        frame:RegisterEvent(event)
    end
    for _, event in ipairs(CAST_EVENTS) do
        frame:RegisterEvent(event)
    end

    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_TARGET")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    frame:SetScript("OnEvent", function(_, event, unit, ...)
        self:OnEvent(event, unit, ...)
    end)
end

function Core:StartTicker()
    if self.ticker then
        self.ticker:Cancel()
    end
    self.ticker = C_Timer.NewTicker(PUF.Config.refreshRate or 0.1, function()
        self:Tick()
    end)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Core:OnEvent(event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        self:FullUpdate("target")
        self:FullUpdate("targettarget")
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        self:FullUpdate("focus")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        PUF.Blizzard:Apply()
        self:RefreshAll()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        PUF.Blizzard:OnCombatEnd()
        if self.pendingLayout then
            self.pendingLayout = false
            self:RefreshAll()
        end
        return
    end

    if event == "UNIT_TARGET" then
        -- The only reliable hint that target-of-target changed.
        if unit == "target" then
            self:FullUpdate("targettarget")
        end
        return
    end

    local frame = self.frames[unit]
    if not frame or not frame.enabled then return end

    if event == "UNIT_AURA" then
        -- The event's third argument (updateInfo) is deliberately never read.
        -- Since 12.1 that payload is fully secret: updateInfo.isFullUpdate is a
        -- secret *boolean*, and boolean-testing one is a hard error, which is
        -- what breaks aura handling in oUF-derived frames. The row is simply
        -- rebuilt instead.
        frame:UpdateAuras()
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        frame:UpdateHealth()
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        frame:UpdatePower()
    elseif event == "UNIT_DISPLAYPOWER" then
        frame:UpdateColors()
        frame:UpdatePower()
    elseif event == "UNIT_NAME_UPDATE" then
        frame:UpdateName()
    elseif event == "UNIT_FACTION" or event == "UNIT_CONNECTION" or event == "UNIT_FLAGS" then
        frame:UpdateColors()
        frame:UpdateHealth()
    else
        -- Everything left is a spellcast event.
        frame.castBar:OnEvent(event)
    end
end

function Core:FullUpdate(key)
    local frame = self.frames[key]
    if not frame or not frame.enabled then return end

    if Style.Exists(frame.unit) then
        frame:UpdateAll()
    else
        frame.castBar:Hide()
    end
end

function Core:Tick()
    for _, key in ipairs(PUF.Config.UNIT_ORDER) do
        local frame = self.frames[key]
        if frame and frame.enabled then
            if key == "targettarget" then
                -- No unit events fire for this token, so it is refreshed whole.
                if frame.button:IsShown() and Style.Exists(frame.unit) then
                    frame:UpdateAll()
                end
            else
                frame:Tick()
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Configuration changes
--------------------------------------------------------------------------------

-- Rebuild every frame from the current config. Protected work is skipped while
-- in combat and replayed the moment it ends.
-- Lay one frame out without letting its failure take the others with it.
--
-- These run from settings callbacks, and WoW suppresses Lua errors by default,
-- so an unprotected throw here used to look exactly like "the settings do
-- nothing": every frame after the failing one silently stopped refreshing. The
-- error is kept for /puf debug and announced once so it cannot pass unnoticed.
function Core:ApplyFrame(key)
    local frame = self.frames[key]
    if not frame then return end

    frame:SetEnabled(PUF.Config:GetUnit(key).enabled and true or false)

    local ok, err = pcall(frame.ApplyLayout, frame)
    if not ok then
        self.lastError = key .. ": " .. tostring(err)
        if not self.reportedError then
            self.reportedError = true
            print("|cffff6666PeaversUnitFrames|r layout error on '" .. key ..
                "' - run /puf debug for details: " .. tostring(err))
        end
    end
end

function Core:RefreshAll()
    if not self.frames.player then return end

    if InCombatLockdown() then
        self.pendingLayout = true
        self.deferredForCombat = true
        return
    end

    for _, key in ipairs(PUF.Config.UNIT_ORDER) do
        self:ApplyFrame(key)
    end

    self.refreshCount = (self.refreshCount or 0) + 1
    self:SetUnlocked(PUF.Config.unlocked and true or false)
end

function Core:RefreshUnit(key)
    if not self.frames[key] then return end

    if InCombatLockdown() then
        self.pendingLayout = true
        self.deferredForCombat = true
        return
    end

    self:ApplyFrame(key)
    self.refreshCount = (self.refreshCount or 0) + 1
end

function Core:SetUnlocked(unlocked)
    self.unlocked = unlocked
    for _, key in ipairs(PUF.Config.UNIT_ORDER) do
        local frame = self.frames[key]
        if frame then
            frame:SetMoverShown(unlocked and PUF.Config:GetUnit(key).enabled)
        end
    end
end

function Core:ToggleUnlocked()
    local unlocked = not PUF.Config.unlocked
    PUF.Config.unlocked = unlocked
    PUF.Config:Save()
    self:SetUnlocked(unlocked)
    return unlocked
end

-- Put every frame back where it started without touching the rest of the profile.
function Core:ResetPositions()
    local defaults = PUF.Config.defaults and PUF.Config.defaults.units
    if not defaults then return end

    for key, unitDefaults in pairs(defaults) do
        local unitConfig = PUF.Config:GetUnit(key)
        unitConfig.x = unitDefaults.x
        unitConfig.y = unitDefaults.y
    end

    PUF.Config:Save()
    self:RefreshAll()

    if PUF.ConfigUI and PUF.ConfigUI.SyncPositionInputs then
        for _, key in ipairs(PUF.Config.UNIT_ORDER) do
            PUF.ConfigUI:SyncPositionInputs(key)
        end
    end
end

return Core
