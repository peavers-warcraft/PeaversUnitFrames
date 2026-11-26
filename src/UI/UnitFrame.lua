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
    button:SetScript("OnLeave", function(frame)
        Style.SetHover(frame, false)
        GameTooltip:Hide()
    end)
    self.button = button

    local barBg = Style.Colors.barBg

    -- Square portrait, drawn on the button itself. Its backing square is what
    -- shows for the moment before the client has a portrait to hand over.
    local portraitBg = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    portraitBg:SetColorTexture(0.1, 0.1, 0.1, 1)
    self.portraitBg = portraitBg

    local portrait = button:CreateTexture(nil, "ARTWORK")
    -- Zoomed in on the face: the full portrait is a circle on a square, and its
    -- corners are empty.
    portrait:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    self.portrait = portrait

    local health = CreateFrame("StatusBar", nil, button)
    health:SetMinMaxValues(0, 100)
    health:SetValue(100)
    self.health = health

    -- Near-black under the fill, so the missing part of the bar reads as
    -- missing rather than as a dimmer copy of the colour.
    local healthBase = health:CreateTexture(nil, "BACKGROUND", nil, -1)
    healthBase:SetAllPoints(health)
    healthBase:SetColorTexture(barBg.r, barBg.g, barBg.b, 1)
    self.healthBase = healthBase

    -- Optional tint over that base from the bar's own colour, for anyone who
    -- wants a wounded unit to still read as "that class". Off by default.
    local healthBg = health:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints(health)
    self.healthBg = healthBg

    local power = CreateFrame("StatusBar", nil, button)
    power:SetMinMaxValues(0, 100)
    power:SetValue(0)
    self.power = power

    local powerBg = power:CreateTexture(nil, "BACKGROUND")
    powerBg:SetAllPoints(power)
    powerBg:SetColorTexture(barBg.r, barBg.g, barBg.b, 1)
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
    -- The border lights whatever the tooltip setting says: it is how you know
    -- which frame a click is about to land on.
    Style.SetHover(frame, true)

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

-- The mover's own blue box, for /puf unlock. In Edit Mode it is cleared:
-- Blizzard's selection overlay is the handle there, and a second coloured box
-- underneath it is two looks for one frame.
function UnitFrame:PaintMover(painted)
    local mover = self.mover
    if not mover then return end

    if painted then
        mover:SetBackdropColor(0.29, 0.56, 0.89, 0.35)
        mover:SetBackdropBorderColor(0.29, 0.56, 0.89, 1)
    else
        mover:SetBackdropColor(0, 0, 0, 0)
        mover:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function UnitFrame:BuildMover()
    local mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    mover:SetBackdrop(Style.BACKDROP)
    self.mover = mover
    self:PaintMover(true)

    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(PUF.Config.UNIT_LABELS[self.key] or self.key)
    mover.label = label

    mover:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    mover:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        self:CommitMoverPosition()
    end)
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
        self:PaintMover(false)
        self:SyncMover()
        mover:Show()
    else
        mover:SetFrameStrata("DIALOG")
        mover:EnableMouse(true)
        mover.label:Show()
        self:PaintMover(true)
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

    -- One real screen pixel. Every inset below is measured in it, so the
    -- hairline border, the portrait edge and the bars all land on whole pixels
    -- whatever the UI scale.
    local px = Style.ApplyBackdrop(button, cfg.bgAlpha)

    local width = cfg.width or 200
    local height = cfg.height or 40
    local showPower = cfg.showPower and true or false
    local powerHeight = showPower and (cfg.powerHeight or 6) or 0
    local texture = Style.GetTexture(cfg)

    -- The portrait is a square as tall as the inside of the frame, carved out
    -- of one end. The bars start a pixel past it, so the frame's own black fill
    -- shows through as the divider.
    local showPortrait = cfg.showPortrait and true or false
    local portraitSize = height - (px * 2)
    -- Never let the portrait eat the bars on a short, narrow frame.
    if portraitSize > width / 2 then showPortrait = false end

    local leftInset, rightInset = px, px
    if showPortrait then
        local onLeft = cfg.portraitSide == "left"
        local point = onLeft and "TOPLEFT" or "TOPRIGHT"
        local x = onLeft and px or -px

        self.portraitBg:ClearAllPoints()
        self.portraitBg:SetPoint(point, button, point, x, -px)
        self.portraitBg:SetSize(portraitSize, portraitSize)
        self.portrait:ClearAllPoints()
        self.portrait:SetAllPoints(self.portraitBg)

        if onLeft then
            leftInset = px + portraitSize + px
        else
            rightInset = px + portraitSize + px
        end
    end
    self.showPortrait = showPortrait
    self.portraitBg:SetShown(showPortrait)
    self.portrait:SetShown(showPortrait)

    -- Health fills everything above the power strip, flush against it: one
    -- border round the whole frame and no seams inside it.
    self.health:ClearAllPoints()
    self.health:SetPoint("TOPLEFT", button, "TOPLEFT", leftInset, -px)
    self.health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -rightInset,
        px + (showPower and powerHeight or 0))
    self.health:SetStatusBarTexture(texture)
    self.healthBg:SetTexture(texture)

    self.power:ClearAllPoints()
    self.power:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", leftInset, px)
    self.power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -rightInset, px)
    self.power:SetHeight(powerHeight > 0 and powerHeight or 1)
    self.power:SetStatusBarTexture(Style.GetPowerTexture(cfg))
    self.power:SetShown(showPower)

    Style.ApplyFont(self.nameText, cfg)
    Style.ApplyFont(self.healthText, cfg)

    self.nameText:ClearAllPoints()
    self.nameText:SetPoint("LEFT", self.health, "LEFT", 5, 0)
    self.nameText:SetPoint("RIGHT", self.healthText, "LEFT", -5, 0)
    self.nameText:SetWordWrap(false)
    self.nameText:SetShown(cfg.showName and true or false)

    self.healthText:ClearAllPoints()
    self.healthText:SetPoint("RIGHT", self.health, "RIGHT", -5, 0)
    self.healthText:SetShown(cfg.healthText ~= "none")

    local text = Style.Colors.text
    self.nameText:SetTextColor(text.r, text.g, text.b)
    self.healthText:SetTextColor(text.r, text.g, text.b)

    -- Cast bar hangs flush off the bottom of the frame, sharing its bottom
    -- hairline so the two read as one block; debuffs clear it.
    local castHeight = cfg.castBarHeight or 16
    local showCast = (cfg.showCastBar and true or false)
    self.castBar:SetEnabled(showCast)
    self.castBar:Layout(button, cfg, width, castHeight, cfg.castBarIcon and true or false, px)

    local auraSize = cfg.auraSize or 22
    local auraSpacing = cfg.auraSpacing or 1

    self.buffs:SetConfig(cfg)
    self.debuffs:SetConfig(cfg)

    -- Filtering is expressed as a filter string and handed to the client, since
    -- the addon is never allowed to inspect an aura to decide for itself.
    self.buffs:SetFilter(AuraRow.ComposeFilter("HELPFUL", cfg.buffSource, cfg.buffCategory))
    self.debuffs:SetFilter(AuraRow.ComposeFilter("HARMFUL", cfg.debuffSource, cfg.debuffCategory))

    -- Layout before SetEnabled: the rows need their capacity before they can
    -- populate themselves.
    self.buffs:Layout(button, "BOTTOMLEFT", "TOPLEFT", 0, 2,
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

    -- The cast bar overlaps the frame by its shared hairline, hence the - px.
    local debuffOffset = -2 - (showCast and (castHeight - px) or 0)
    self.debuffs:Layout(button, "TOPLEFT", "BOTTOMLEFT", 0, debuffOffset,
        cfg.maxDebuffs or 8, auraSize, auraSpacing)
    self.debuffs:SetEnabled(cfg.showDebuffs and true or false)

    self:SyncMover()
    self:UpdateAll()
end

--------------------------------------------------------------------------------
-- Updates
--------------------------------------------------------------------------------

-- Whether this update should ease the bars or snap them.
--
-- A frame that has just been pointed at a different unit always snaps: easing
-- there would slide the bar from the old target's health to the new one's,
-- which is an animation of nothing that actually happened. The flag is one-shot
-- and cleared by UpdateAll once both bars have taken it.
function UnitFrame:ShouldSmooth()
    if self.snapNext then return false end
    return PUF.Config:GetUnit(self.key).smoothBars ~= false
end

function UnitFrame:UpdateHealth()
    Style.ApplyHealthToBar(self.health, self.unit, self:ShouldSmooth())

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
    Style.ApplyPowerToBar(self.power, self.unit, self:ShouldSmooth())
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

    local powerColor = Style.GetPowerColor(self.unit, cfg)
    self.power:SetStatusBarColor(powerColor.r, powerColor.g, powerColor.b)
end

-- SetPortraitTexture takes the unit token, not any of the unit's data, so there
-- is nothing secret here to guard against; the pcall is for a client that ever
-- refuses the call outright.
function UnitFrame:UpdatePortrait()
    if not self.showPortrait then return end
    pcall(SetPortraitTexture, self.portrait, self.unit)
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
    self:UpdatePortrait()
    self:UpdateHealth()
    self:UpdatePower()
    self.snapNext = nil
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
