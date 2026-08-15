local addonName, PUF = ...

--------------------------------------------------------------------------------
-- AuraRow
--
-- A single row of buff or debuff icons attached to a unit frame.
--
-- Preferred path is the AuraContainer object added in 12.1: the addon describes
-- how an aura button should look and the client fills it in, so auras keep
-- displaying inside encounters, Mythic+ and rated PvP where the underlying aura
-- data is secret and unreadable.
--
-- Older builds (and any future shape change in that API) fall back to scanning
-- C_UnitAuras directly. That scan is wrapped, because from 12.1 those functions
-- raise a Lua error outright when auras are restricted; an empty row is the
-- correct outcome there, not an error.
--------------------------------------------------------------------------------

local Style = PUF.Style

local AuraRow = {}
PUF.AuraRow = AuraRow
AuraRow.__index = AuraRow

local IsSecret = Style.IsSecret
local Safe = Style.Safe
local Present = Style.Present
local IsSecretTable = Style.IsSecretTable

--------------------------------------------------------------------------------
-- Shared button styling
--------------------------------------------------------------------------------

-- Applied both to client-created AuraButtons and to our own fallback buttons so
-- the two paths are visually identical.
local function DecorateButton(button, size, cfg)
    button:SetSize(size, size)

    if not button.pufIcon then
        local border = button:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints(button)
        border:SetColorTexture(0, 0, 0, 1)
        button.pufBorder = border

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.pufIcon = icon

        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(icon)
        cooldown:SetDrawEdge(false)
        cooldown:SetHideCountdownNumbers(false)
        button.pufCooldown = cooldown

        local count = button:CreateFontString(nil, "OVERLAY")
        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.pufCount = count
    end

    Style.ApplyFont(button.pufCount, cfg, -2)
    local text = Style.Colors.text
    button.pufCount:SetTextColor(text.r, text.g, text.b)

    return button
end

local function SetBorderColor(button, color)
    if button.pufBorder then
        button.pufBorder:SetColorTexture(color.r, color.g, color.b, 1)
    end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

-- baseFilter: "HELPFUL" or "HARMFUL". The composed filter, including any user
-- narrowing, is set separately through SetFilter.
function AuraRow:New(parent, unit, baseFilter)
    local self = setmetatable({}, AuraRow)
    self.unit = unit
    self.baseFilter = baseFilter
    self.filter = baseFilter
    self.buttons = {}

    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:Hide()

    return self
end

-- Extra filter tokens by category. Filtering has to be expressed this way and
-- handed to the client: aura data is secret, so the addon can never inspect an
-- aura to decide whether to show it.
local CATEGORY_TOKENS = {
    HELPFUL = {
        cancelable = "CANCELABLE",
        defensive = "BIG_DEFENSIVE",
    },
    HARMFUL = {
        dispellable = "RAID_PLAYER_DISPELLABLE",
        crowdcontrol = "CROWD_CONTROL",
    },
}

-- Build the pipe-separated filter string the client expects, e.g.
-- "HARMFUL|PLAYER|RAID_PLAYER_DISPELLABLE".
function AuraRow.ComposeFilter(baseFilter, source, category)
    local parts = { baseFilter }

    if source == "mine" then
        parts[#parts + 1] = "PLAYER"
    elseif source == "others" then
        parts[#parts + 1] = "!PLAYER"
    end

    local token = CATEGORY_TOKENS[baseFilter] and CATEGORY_TOKENS[baseFilter][category]
    if token then
        parts[#parts + 1] = token
    end

    local filter = table.concat(parts, "|")

    -- A token this client does not know would make AddAuraGroup fail, leaving an
    -- empty row and no clue why. Fall back to the unfiltered row instead.
    if not Style.IsValidFilter(filter) then
        return baseFilter
    end

    return filter
end

function AuraRow:SetFilter(filter)
    self.filter = filter or self.baseFilter
end

--------------------------------------------------------------------------------
-- Layout
--
-- anchorPoint/relPoint/x/y position the row against the unit frame; growUp only
-- affects which way the client-side container stacks overflow rows.
--------------------------------------------------------------------------------

function AuraRow:Layout(anchorFrame, anchorPoint, relPoint, x, y, count, size, spacing)
    self.count = count
    self.size = size
    self.spacing = spacing

    local width = count > 0 and (count * size + (count - 1) * spacing) or size

    self.frame:ClearAllPoints()
    self.frame:SetPoint(anchorPoint, anchorFrame, relPoint, x, y)
    self.frame:SetSize(width, size)

    self:Rebuild()
end

--------------------------------------------------------------------------------
-- Client-driven path (12.1 AuraContainer)
--------------------------------------------------------------------------------

function AuraRow:BuildContainer()
    if not Style.SupportsAuraContainer() then return false end

    -- Aura groups are add-only - there is no way to remove one or change its
    -- filter in place - so capacity and filter together decide whether the
    -- container can be kept. A size change just re-styles the buttons it already
    -- handed us, which avoids stranding a frame on every slider tick.
    local signature = tostring(self.count) .. "|" .. tostring(self.filter)

    if self.container and self.containerSignature == signature then
        for _, button in ipairs(self.containerButtons) do
            DecorateButton(button, self.size, self.cfg)
        end
        return true
    end

    if self.container then
        self.container:Hide()
        self.container:SetParent(nil)
        self.container = nil
    end

    -- The template is what supplies AddAuraGroup / SetUnit / SetEnabled; without
    -- it the frame is created but has none of them.
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, self.frame,
        Style.AURA_CONTAINER_TEMPLATE)
    if not ok or not container or type(container.AddAuraGroup) ~= "function" then
        return false
    end

    container:SetAllPoints(self.frame)

    if not pcall(container.SetUnit, container, self.unit) then
        container:Hide()
        return false
    end

    self.containerButtons = {}

    local added = pcall(container.AddAuraGroup, container, "puf", self.filter, {
        maxFrameCount = self.count,
        initializeFrame = function(button)
            DecorateButton(button, self.size, self.cfg)
            self.containerButtons[#self.containerButtons + 1] = button

            -- Hand the client our regions; it fills them in without ever
            -- exposing the aura data to this addon.
            pcall(button.SetIcon, button, button.pufIcon)
            pcall(button.SetApplicationCount, button, button.pufCount)
            pcall(button.SetAuraBorder, button, button.pufBorder)
            pcall(button.SetMouseMotionEnabled, button, true)
        end,
    })

    if not added then
        container:Hide()
        container:SetParent(nil)
        return false
    end

    -- SetEnabled must come LAST, after the unit and every group are declared, and
    -- after the container is visible: it is what arms aura-event registration,
    -- and it gates on IsVisible() as well as IsEnabled(). Enabling it earlier
    -- leaves a container that is wired up correctly and never populates.
    container:Show()
    pcall(container.SetEnabled, container, true)

    self.container = container
    self.containerSignature = signature
    return true
end

--------------------------------------------------------------------------------
-- Fallback path (direct aura scan)
--------------------------------------------------------------------------------

function AuraRow:GetButton(index)
    local button = self.buttons[index]
    if not button then
        button = CreateFrame("Frame", nil, self.frame)
        self.buttons[index] = button
    end

    DecorateButton(button, self.size, self.cfg)

    button:ClearAllPoints()
    button:SetPoint("LEFT", self.frame, "LEFT", (index - 1) * (self.size + self.spacing), 0)

    return button
end

-- Returns a plain array of aura tables, or nil when the client will not give us
-- readable data.
local function ScanAuras(unit, filter, maxCount)
    local list

    local ok = pcall(function()
        if C_UnitAuras and C_UnitAuras.GetUnitAuras then
            local auras = C_UnitAuras.GetUnitAuras(unit, filter, maxCount)
            if auras then
                local out = {}
                for i = 1, maxCount do
                    local aura = auras[i]
                    if not aura then break end
                    out[i] = aura
                end
                list = out
            end
            return
        end

        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local out = {}
            for i = 1, maxCount do
                local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
                if not aura then break end
                out[i] = aura
            end
            list = out
        end
    end)

    if not ok then return nil end
    return list
end

function AuraRow:UpdateFallback()
    local auras = ScanAuras(self.unit, self.filter, self.count)
    local shown = 0

    if auras then
        for index = 1, self.count do
            local aura = auras[index]
            if not aura then break end

            -- A restricted aura arrives as a secret *table*, which cannot be
            -- indexed at all. Ask before touching it rather than relying on the
            -- pcall below to mop up the error.
            if IsSecretTable(aura) then break end

            local button = self:GetButton(index)
            local applied = false

            -- Every field below can be secret; IsSecret is asked before any
            -- comparison, since comparing a secret is itself the error.
            pcall(function()
                if Present(aura.icon) then
                    button.pufIcon:SetTexture(aura.icon)
                    applied = true
                end

                local stacks = aura.applications or aura.charges
                if not IsSecret(stacks) and stacks and stacks > 1 then
                    button.pufCount:SetText(stacks)
                else
                    button.pufCount:SetText("")
                end

                local duration, expires = aura.duration, aura.expirationTime
                if not IsSecret(duration) and not IsSecret(expires)
                    and duration and expires and duration > 0 then
                    button.pufCooldown:SetCooldown(expires - duration, duration)
                else
                    button.pufCooldown:Clear()
                end

                if self.baseFilter == "HARMFUL" then
                    local dispel = aura.dispelName
                    if not IsSecret(dispel) and dispel ~= nil then
                        SetBorderColor(button, Style.DebuffColors[dispel] or Style.DebuffColors.none)
                    else
                        SetBorderColor(button, Style.DebuffColors.none)
                    end
                else
                    SetBorderColor(button, Style.Colors.border)
                end
            end)

            if applied then
                button:Show()
                shown = index
            else
                button:Hide()
                break
            end
        end
    end

    for index = shown + 1, #self.buttons do
        self.buttons[index]:Hide()
    end
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

function AuraRow:Rebuild()
    -- Nothing to build until the row is both switched on and sized; Layout and
    -- SetEnabled each call back in, so whichever happens last does the work.
    if not self.enabled or not self.count then return end

    for _, button in ipairs(self.buttons) do
        button:Hide()
    end

    -- Shown first: the container arms itself on IsVisible(), so building it
    -- inside a still-hidden row produces one that never populates.
    self.frame:Show()

    self.usingContainer = self:BuildContainer()

    if not self.usingContainer then
        self:UpdateFallback()
    end
end

function AuraRow:Update()
    -- Layout has to have run first, otherwise there is no capacity to scan for.
    if not self.enabled or not self.count then return end

    if self.usingContainer then
        -- Addon-callable dirty mark; the container does the actual refresh.
        if self.container then
            pcall(self.container.UpdateAllAuras, self.container)
        end
        return
    end

    self:UpdateFallback()
end

function AuraRow:SetEnabled(enabled)
    enabled = enabled and true or false
    self.enabled = enabled
    self.frame:SetShown(enabled)
    if enabled then
        self:Rebuild()
    end
end

-- The owning frame's settings, used for the stack-count font. Stored rather than
-- looked up so the row never has to know which unit key it belongs to.
function AuraRow:SetConfig(cfg)
    self.cfg = cfg
end

function AuraRow:SetUnit(unit)
    self.unit = unit
    if self.container then
        pcall(self.container.SetUnit, self.container, unit)
    end
end

return AuraRow
