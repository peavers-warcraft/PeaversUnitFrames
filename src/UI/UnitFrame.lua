local addonName, PUF = ...

--------------------------------------------------------------------------------
-- UnitFrame
--
-- One secure button per unit: health bar, an optional thin power strip, name and
-- health text, a cast bar, and a buff and debuff row.
--
-- The button itself is a SecureUnitButtonTemplate so left click targets and
-- right click opens the unit menu. Everything that has to change while the
-- player is in combat (bar values, text, colours) is plain unprotected work;
-- everything protected (position, size, unit watch) is deferred by Core until
-- combat drops.
--------------------------------------------------------------------------------

local Style = PUF.Style
local CastBar = PUF.CastBar
local AuraRow = PUF.AuraRow

local UnitFrame = {}
PUF.UnitFrame = UnitFrame
UnitFrame.__index = UnitFrame

local INSET = 1

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UnitFrame.New(_, key, unit)
    local self = setmetatable({}, UnitFrame)
    self.key = key
    self.unit = unit

    local button = CreateFrame(
        "Button",
        "PeaversUnitFrames" .. key:gsub("^%l", string.upper),
        UIParent,
        "SecureUnitButtonTemplate,BackdropTemplate"
    )
    button:SetFrameStrata("LOW")
    button:SetAttribute("unit", unit)
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnEnter", function(frame) self:OnEnter(frame) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.button = button

    local health = CreateFrame("StatusBar", nil, button)
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)
    self.health = health

    -- Empty portion of the bar, tinted from the same colour so a wounded unit
    -- still reads as "that class" rather than as a black gap.
    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints(health)
    self.healthBg = healthBg

    local power = CreateFrame("StatusBar", nil, button)
    power:SetMinMaxValues(0, 100)
    power:SetValue(0)
    self.power = power

    local powerBg = power:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints(power)
    powerBg:SetColorTexture(0, 0, 0, 0.7)
    self.powerBg = powerBg

    local nameText = health:CreateFontString(nil, "OVERLAY")
    nameText:SetJustifyH("LEFT")
    self.nameText = nameText

    local healthText = health:CreateFontString(nil, "OVERLAY")
    healthText:SetJustifyH("RIGHT")
    self.healthText = healthText

    self.castBar = CastBar:New(button, unit)
    self.buffs = AuraRow:New(button, unit, "HELPFUL")
    self.debuffs = AuraRow:New(button, unit, "HARMFUL")
    -- A single slot pinned to the right of the buff row, so the mount stays put
    -- regardless of how the buffs themselves are filtered or how many there are.
    self.mount = AuraRow:New(button, unit, "HELPFUL")

    self:BuildMover()

    return self
end

function UnitFrame:OnEnter(frame)
    local mode = PUF.Config:GetUnit(self.key).tooltip or "always"

    if mode == "never" then return end
    if mode == "ooc" and InCombatLockdown() then return end

    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(self.unit)
    GameTooltip:Show()
end

-- Drop a tooltip that is already up when combat starts. Without this, hovering a
-- frame as the pull happens leaves the tooltip on screen for the whole fight,
-- which is exactly what the "out of combat" setting is meant to avoid.
function UnitFrame:HideTooltipForCombat()
    if (PUF.Config:GetUnit(self.key).tooltip or "always") ~= "ooc" then return end
    if GameTooltip:GetOwner() == self.button then
        GameTooltip:Hide()
    end
end

--------------------------------------------------------------------------------
-- Mover
--
-- Dragging the secure button itself would fight its click handlers, so
-- positioning happens through a separate overlay that is only visible while the
-- frames are unlocked.
--------------------------------------------------------------------------------

function UnitFrame:BuildMover()
    local mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    mover:SetBackdrop(Style.BACKDROP)
    mover:SetBackdropColor(0.29, 0.56, 0.89, 0.35)
    mover:SetBackdropBorderColor(0.29, 0.56, 0.89, 1)

    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(PUF.Config.UNIT_LABELS[self.key] or self.key)
    mover.label = label

    mover:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    mover:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        self:CommitMoverPosition()
    end)

    self.mover = mover
end

-- Translate the mover's screen position into a centre-relative offset and push
-- it onto the real frame.
function UnitFrame:CommitMoverPosition()
    local mover = self.mover
    local moverX, moverY = mover:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not moverX or not parentX then return end

    local scale = mover:GetEffectiveScale() / UIParent:GetEffectiveScale()

    local unitConfig = PUF.Config:GetUnit(self.key)
    unitConfig.x = math.floor((moverX * scale) - parentX + 0.5)
    unitConfig.y = math.floor((moverY * scale) - parentY + 0.5)
    PUF.Config:Save()

    self:ApplyPosition()
    self:SyncMover()

    -- The typed offsets are a group in the Edit Mode panel now, so a drag has
    -- to write back into them if that group happens to be the one open.
    local Commons = _G.PeaversCommons
    if Commons and Commons.EditModePanel then
        Commons.EditModePanel:Refresh()
    end
end

function UnitFrame:SyncMover()
    local mover = self.mover
    mover:ClearAllPoints()

    if PUF.EditMode and PUF.EditMode:IsEditing() then
        -- Free-standing while Edit Mode owns the dragging. Anchored to the
        -- button instead, the mover's point would read as CENTER 0,0 no matter
        -- where the frame actually sat, so Edit Mode would think every frame was
        -- at its default position and never enable its Reset Position button.
        local cfg = PUF.Config:GetUnit(self.key)
        mover:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 0)
    else
        mover:SetPoint("CENTER", self.button, "CENTER", 0, 0)
    end

    mover:SetSize(self.button:GetWidth(), self.button:GetHeight())
end

function UnitFrame:SetMoverShown(shown)
    if shown then
        self:SyncMover()
        self.mover:Show()
    else
        self.mover:Hide()
    end
end

-- Hand the mover over to Edit Mode, or take it back.
--
-- Edit Mode drags through its own selection overlay, which is a mouse-enabled
-- child covering the whole mover. Leaving the mover's own drag handlers attached
-- means two systems answer the same drag, so they are removed for the duration
-- and put back on the way out - which keeps /puf unlock working exactly as it
-- did for anyone who never opens Edit Mode.
function UnitFrame:SetEditModeShown(shown)
    local mover = self.mover

    if shown then
        -- Edit Mode's selection overlay is a child of this frame, and Blizzard
        -- hard-codes it to MEDIUM strata (EditModeSystemTemplates.xml:
        -- frameStrata="MEDIUM" frameLevel="1000" toplevel="true"). The mover
        -- normally sits at DIALOG so it floats over everything while unlocked,
        -- which puts it *above* its own selection child - a mouse-enabled frame
        -- covering the overlay that is supposed to be receiving the clicks. It
        -- drops to MEDIUM and stops taking mouse input for the duration.
        mover:SetFrameStrata("MEDIUM")
        mover:EnableMouse(false)
        mover:RegisterForDrag()
        mover:SetScript("OnDragStart", nil)
        mover:SetScript("OnDragStop", nil)
        -- The overlay draws the system name itself, so the mover's own label
        -- would only print it twice.
        mover.label:Hide()
        self:SyncMover()
        mover:Show()
    else
        mover:SetFrameStrata("DIALOG")
        mover:EnableMouse(true)
        mover.label:Show()
        -- Edit Mode clears movable on every frame it had selected as it closes,
        -- so this has to be put back or the drag handles stop dragging for
        -- anyone who opened Edit Mode once and then went back to /puf unlock.
        mover:SetMovable(true)
        mover:RegisterForDrag("LeftButton")
        mover:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
        mover:SetScript("OnDragStop", function(frame)
            frame:StopMovingOrSizing()
            self:CommitMoverPosition()
        end)
        self:SyncMover()
        mover:Hide()
    end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

function UnitFrame:ApplyPosition()
    if InCombatLockdown() then return false end

    local unitConfig = PUF.Config:GetUnit(self.key)
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", UIParent, "CENTER", unitConfig.x or 0, unitConfig.y or 0)
    return true
end

function UnitFrame:ApplyLayout()
    -- Everything below comes from this frame's own settings; nothing is shared
    -- with the other three.
    local cfg = PUF.Config:GetUnit(self.key)
    local button = self.button

    if not InCombatLockdown() then
        button:SetSize(cfg.width or 200, cfg.height or 40)
        self:ApplyPosition()
    end

    Style.ApplyBackdrop(button, cfg.bgAlpha)

    local width = cfg.width or 200
    local showPower = cfg.showPower and true or false
    local powerHeight = showPower and (cfg.powerHeight or 5) or 0
    local texture = Style.GetTexture(cfg)

    -- Health fills everything above the power strip.
    self.health:ClearAllPoints()
    self.health:SetPoint("TOPLEFT", button, "TOPLEFT", INSET, -INSET)
    self.health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -INSET,
        INSET + (showPower and (powerHeight + 1) or 0))
    self.health:SetStatusBarTexture(texture)
    self.healthBg:SetTexture(texture)

    self.power:ClearAllPoints()
    self.power:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", INSET, INSET)
    self.power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -INSET, INSET)
    self.power:SetHeight(powerHeight > 0 and powerHeight or 1)
    self.power:SetStatusBarTexture(texture)
    self.power:SetShown(showPower)

    Style.ApplyFont(self.nameText, cfg)
    Style.ApplyFont(self.healthText, cfg)

    self.nameText:ClearAllPoints()
    self.nameText:SetPoint("LEFT", self.health, "LEFT", 4, 0)
    self.nameText:SetPoint("RIGHT", self.healthText, "LEFT", -4, 0)
    self.nameText:SetShown(cfg.showName and true or false)

    self.healthText:ClearAllPoints()
    self.healthText:SetPoint("RIGHT", self.health, "RIGHT", -4, 0)
    self.healthText:SetShown(cfg.healthText ~= "none")

    local text = Style.Colors.text
    self.nameText:SetTextColor(text.r, text.g, text.b)
    self.healthText:SetTextColor(text.r, text.g, text.b)

    -- Cast bar sits directly under the frame; debuffs clear it.
    local castHeight = cfg.castBarHeight or 18
    local showCast = (cfg.showCastBar and true or false)
    self.castBar:SetEnabled(showCast)
    self.castBar:Layout(button, cfg, width, castHeight, cfg.castBarIcon and true or false)

    local auraSize = cfg.auraSize or 20
    local auraSpacing = cfg.auraSpacing or 2

    self.buffs:SetConfig(cfg)
    self.debuffs:SetConfig(cfg)

    -- Filtering is expressed as a filter string and handed to the client, since
    -- the addon is never allowed to inspect an aura to decide for itself.
    self.buffs:SetFilter(AuraRow.ComposeFilter("HELPFUL", cfg.buffSource, cfg.buffCategory))
    self.debuffs:SetFilter(AuraRow.ComposeFilter("HARMFUL", cfg.debuffSource, cfg.debuffCategory))

    -- Layout before SetEnabled: the rows need their capacity before they can
    -- populate themselves.
    self.buffs:Layout(button, "BOTTOMLEFT", "TOPLEFT", 0, 4,
        cfg.maxBuffs or 8, auraSize, auraSpacing)
    self.buffs:SetEnabled(cfg.showBuffs and true or false)

    -- One row above the buffs, left-aligned with the first buff icon. Anchored to
    -- the buff row rather than the frame so it tracks the buffs' own position and
    -- can never overlap them, however many there are.
    local showMount = cfg.showMount and true or false
    self.mount:SetConfig(cfg)
    self.mount:SetCandidateFilters(showMount
        and { includeSpellIDs = AuraRow.GetMountSpellIDs() }
        or nil)
    self.mount:Layout(self.buffs.frame, "BOTTOMLEFT", "TOPLEFT", 0, auraSpacing,
        1, auraSize, auraSpacing)
    self.mount:SetEnabled(showMount)

    local debuffOffset = -4 - (showCast and (castHeight + 4) or 0)
    self.debuffs:Layout(button, "TOPLEFT", "BOTTOMLEFT", 0, debuffOffset,
        cfg.maxDebuffs or 8, auraSize, auraSpacing)
    self.debuffs:SetEnabled(cfg.showDebuffs and true or false)

    self:SyncMover()
    self:UpdateAll()
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

function UnitFrame:UpdateHealth()
    Style.ApplyHealthToBar(self.health, self.unit)

    if self.healthText:IsShown() then
        -- The text may be a secret string built from a restricted health value;
        -- SetText accepts that, but both calls stay guarded so a future change in
        -- what is permitted degrades to a blank field instead of an error.
        local ok, text = pcall(Style.BuildHealthText, self.unit, PUF.Config:GetUnit(self.key).healthText)
        pcall(self.healthText.SetText, self.healthText, ok and text or "")
    end
end

function UnitFrame:UpdatePower()
    if not self.power:IsShown() then return end
    Style.ApplyPowerToBar(self.power, self.unit)
end

function UnitFrame:UpdateName()
    if not self.nameText:IsShown() then return end
    -- SetText accepts a secret string, which is what UnitName returns for
    -- most units while in combat.
    pcall(self.nameText.SetText, self.nameText, Style.GetUnitName(self.unit))
end

function UnitFrame:UpdateColors()
    local cfg = PUF.Config:GetUnit(self.key)
    local color = Style.GetUnitColor(self.unit, cfg)
    self.health:SetStatusBarColor(color.r, color.g, color.b)
    self.healthBg:SetVertexColor(color.r, color.g, color.b, cfg.healthBgAlpha or 0.22)

    local powerColor = Style.GetPowerColor(self.unit)
    self.power:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
end

function UnitFrame:UpdateAuras()
    self.buffs:Update()
    self.debuffs:Update()
    self.mount:Update()
end

-- Runs whether or not the unit exists: appearance changes have to land on a
-- frame that is currently empty too, otherwise tweaking colours or fonts with no
-- target selected appears to do nothing. Each individual update already copes
-- with a missing unit. Callers on the hot path still check Style.Exists first.
function UnitFrame:UpdateAll()
    self:UpdateColors()
    self:UpdateName()
    self:UpdateHealth()
    self:UpdatePower()
    self:UpdateAuras()
    self.castBar:Refresh()
end

-- Cheap per-tick refresh: everything that can change without an event of its own.
function UnitFrame:Tick()
    if not self.button:IsShown() or not Style.Exists(self.unit) then return end
    self:UpdateHealth()
    self:UpdatePower()
end

--------------------------------------------------------------------------------
-- Enable / disable
--------------------------------------------------------------------------------

function UnitFrame:SetEnabled(enabled)
    if InCombatLockdown() then return false end
    if self.enabled == enabled then return true end

    if enabled then
        RegisterUnitWatch(self.button)
    else
        UnregisterUnitWatch(self.button)
        self.button:Hide()
        self.castBar:Hide()
    end

    self.enabled = enabled
    return true
end

return UnitFrame
