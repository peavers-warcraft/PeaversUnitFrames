local addonName, PUF = ...

--------------------------------------------------------------------------------
-- CastBar
--
-- One cast bar per unit frame, anchored underneath it.
--
-- Two ways of driving the fill, picked per cast:
--   * unrestricted cast times  -> ordinary OnUpdate against GetTime()
--   * secret cast times        -> a DurationObject handed to
--                                 StatusBar:SetTimerDuration, which lets the
--                                 client animate data the addon is not allowed
--                                 to read
-- If neither is available the bar still shows the spell name over a full bar,
-- which is more useful than showing nothing.
--------------------------------------------------------------------------------

local Style = PUF.Style

local CastBar = {}
PUF.CastBar = CastBar
CastBar.__index = CastBar

local IsSecret = Style.IsSecret
local Safe = Style.Safe
local ReadBool = Style.ReadBool
local Present = Style.Present

-- StatusBar:SetTimerDuration interpolation / direction constants.
local INTERPOLATION_IMMEDIATE = 0
local DIRECTION_ELAPSED = 0

local FADE_TIME = 0.4

function CastBar.New(_, parent, unit)
    local self = setmetatable({}, CastBar)
    self.unit = unit

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:Hide()
    -- Anchored here as well as in Layout. An unanchored frame does not sit
    -- quietly at 0,0 - it drifts to wherever the client decides - so it must
    -- never be possible to show one that Layout has not reached yet.
    frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -4)
    frame:SetSize(200, 18)
    -- Restyled properly by Layout once the owning frame's config is known.
    Style.ApplyBackdrop(frame, 0.85)
    self.frame = frame

    local icon = frame:CreateTexture(nil, "ARTWORK")
    -- Trim the default icon border so the art sits flush inside the hairline.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon = icon

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture(Style.GetTexture(nil))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    self.bar = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0.1, 0.1, 0.12, 0.6)
    self.bg = bg

    local spellText = bar:CreateFontString(nil, "OVERLAY")
    spellText:SetJustifyH("LEFT")
    self.spellText = spellText

    local timeText = bar:CreateFontString(nil, "OVERLAY")
    timeText:SetJustifyH("RIGHT")
    self.timeText = timeText

    frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)

    return self
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function CastBar:Layout(anchorFrame, cfg, width, height, showIcon)
    self.cfg = cfg
    local frame = self.frame

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -4)
    frame:SetSize(width, height)
    Style.ApplyBackdrop(frame, cfg.bgAlpha)

    local inset = 1
    local iconSize = height - (inset * 2)

    if showIcon then
        self.icon:Show()
        self.icon:ClearAllPoints()
        self.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        self.icon:SetSize(iconSize, iconSize)
    else
        self.icon:Hide()
    end

    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + (showIcon and (iconSize + 1) or 0), -inset)
    self.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    self.bar:SetStatusBarTexture(Style.GetTexture(cfg))

    Style.ApplyFont(self.spellText, cfg, -1)
    Style.ApplyFont(self.timeText, cfg, -1)

    self.spellText:ClearAllPoints()
    self.spellText:SetPoint("LEFT", self.bar, "LEFT", 4, 0)
    self.spellText:SetPoint("RIGHT", self.timeText, "LEFT", -4, 0)

    self.timeText:ClearAllPoints()
    self.timeText:SetPoint("RIGHT", self.bar, "RIGHT", -4, 0)

    local text = Style.Colors.text
    self.spellText:SetTextColor(text.r, text.g, text.b)
    self.timeText:SetTextColor(text.r, text.g, text.b)
end

--------------------------------------------------------------------------------
-- Cast tracking
--------------------------------------------------------------------------------

local function SetBarColor(self, color)
    self.bar:SetStatusBarColor(color.r, color.g, color.b)
end

-- Read whatever the unit is currently doing. Returns nil when it is idle.
--
-- Every field here can come back secret inside an encounter. Names and textures
-- are only truth-tested, never compared, and notInterruptible is normalised
-- through ReadBool because a secret *boolean* cannot legally be tested at all.
local function ReadCast(unit)
    local name, text, texture, startTime, endTime, _, _, notInterruptible = Safe(UnitCastingInfo, unit)
    if Present(name) then
        return {
            name = text or name,
            texture = texture,
            startTime = startTime,
            endTime = endTime,
            notInterruptible = ReadBool(notInterruptible),
            channeling = false,
        }
    end

    local cName, cText, cTexture, cStart, cEnd, _, cNotInterruptible = Safe(UnitChannelInfo, unit)
    if Present(cName) then
        return {
            name = cText or cName,
            texture = cTexture,
            startTime = cStart,
            endTime = cEnd,
            notInterruptible = ReadBool(cNotInterruptible),
            channeling = true,
        }
    end

    return nil
end

-- Drive the fill from a DurationObject so the client animates values the addon
-- is not permitted to inspect.
function CastBar:StartSecretTimer(cast)
    if not Style.Caps.timerDuration then return false end

    local duration = Safe(C_DurationUtil.CreateDuration)
    if not duration then return false end

    if not pcall(duration.SetTimeSpan, duration, cast.startTime, cast.endTime) then
        return false
    end

    -- Channels drain, casts fill.
    local direction = DIRECTION_ELAPSED
    if not pcall(self.bar.SetTimerDuration, self.bar, duration, INTERPOLATION_IMMEDIATE, direction) then
        return false
    end

    if cast.channeling then
        self.bar:SetReverseFill(true)
    else
        self.bar:SetReverseFill(false)
    end

    return true
end

function CastBar:Refresh()
    if not self.enabled then return end

    local cast = ReadCast(self.unit)
    if not cast then
        self:Stop()
        return
    end

    self.cast = cast
    self.fading = nil
    self.frame:SetAlpha(1)

    -- notInterruptible has already been normalised to true/false/nil, where nil
    -- means the client would not say. An unknown falls through to the ordinary
    -- cast colour rather than claiming the cast cannot be kicked.
    if cast.notInterruptible == true then
        SetBarColor(self, Style.Colors.castUninterruptible)
    elseif cast.channeling then
        SetBarColor(self, Style.Colors.castChannel)
    else
        SetBarColor(self, Style.Colors.cast)
    end

    if Present(cast.texture) then
        pcall(self.icon.SetTexture, self.icon, cast.texture)
    else
        self.icon:SetTexture(nil)
    end

    -- FontString:SetText accepts secret strings, so the spell name displays even
    -- when we are not allowed to read it.
    pcall(self.spellText.SetText, self.spellText, cast.name)

    local timesReadable = not IsSecret(cast.startTime) and not IsSecret(cast.endTime)
        and cast.startTime ~= nil and cast.endTime ~= nil

    if timesReadable then
        self.mode = "manual"
        self.bar:SetReverseFill(cast.channeling and true or false)
        self.bar:SetMinMaxValues(0, 1)
        self.startTime = cast.startTime / 1000
        self.endTime = cast.endTime / 1000
    elseif self:StartSecretTimer(cast) then
        self.mode = "timer"
        self.timeText:SetText("")
    else
        -- Nothing readable and no timer support: show that something is being
        -- cast without pretending to know how far along it is.
        self.mode = "indeterminate"
        self.bar:SetReverseFill(false)
        self.bar:SetMinMaxValues(0, 1)
        self.bar:SetValue(1)
        self.timeText:SetText("")
    end

    self.frame:Show()
end

function CastBar:Stop(failed)
    self.cast = nil
    self.mode = nil

    if not self.frame:IsShown() then return end

    if failed then
        SetBarColor(self, Style.Colors.castFailed)
        self.bar:SetValue(select(2, self.bar:GetMinMaxValues()))
        self.timeText:SetText("")
    end

    self.fading = FADE_TIME
end

function CastBar:Hide()
    self.fading = nil
    self.cast = nil
    self.mode = nil
    self.frame:Hide()
end

function CastBar:SetEnabled(enabled)
    self.enabled = enabled
    if not enabled then
        self:Hide()
    end
end

function CastBar:OnUpdate(elapsed)
    if self.fading then
        self.fading = self.fading - elapsed
        if self.fading <= 0 then
            self:Hide()
        else
            self.frame:SetAlpha(self.fading / FADE_TIME)
        end
        return
    end

    if self.mode ~= "manual" or not self.cast then return end

    local now = GetTime()
    local total = self.endTime - self.startTime
    if total <= 0 then
        self:Stop()
        return
    end

    local elapsedTime = now - self.startTime
    if elapsedTime >= total then
        self:Stop()
        return
    end

    self.bar:SetValue(elapsedTime / total)

    local remaining = self.endTime - now
    self.timeText:SetText(string.format("%.1f", remaining))
end

-- Every spellcast event for the unit funnels through here; re-reading the unit
-- is cheaper and far less error prone than tracking cast IDs by hand.
function CastBar:OnEvent(event)
    if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        self:Stop(true)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        self:Stop()
    else
        self:Refresh()
    end
end

return CastBar
