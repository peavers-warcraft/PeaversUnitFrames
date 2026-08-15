--------------------------------------------------------------------------------
-- PeaversUnitFrames Configuration
-- Uses PeaversCommons.ConfigManager with AceDB-3.0 for profile management.
--
-- Almost everything lives per unit rather than addon-wide: each frame owns its
-- own size, colours, font, texture, cast bar and aura rows, so a fat player
-- frame and a small target-of-target can be styled independently. Only settings
-- that genuinely cannot differ between frames stay at the top level.
--
-- Frame positions are stored as offsets from the centre of UIParent rather than
-- as an anchor point plus offset: the movers always reposition by centre, so a
-- single pair of numbers per unit keeps the layout resolution independent and
-- the settings UI trivial.
--------------------------------------------------------------------------------

local addonName, PUF = ...

local PeaversCommons = _G.PeaversCommons
local ConfigManager = PeaversCommons.ConfigManager

PUF.name = PUF.name or addonName

-- The full settings set every frame carries. Each unit gets its own copy, so a
-- new option only ever has to be added here.
local function UnitDefaults(overrides)
    local unit = {
        enabled = true,

        -- Frame
        width = 240,
        height = 46,
        x = 0,
        y = 0,
        bgAlpha = 0.85,

        -- Bars
        barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
        -- "class" colours players by class and NPCs by reaction; "custom" paints
        -- every health bar with healthColor instead.
        healthColorMode = "class",
        healthColor = { r = 0.25, g = 0.62, b = 0.36 },
        -- How much of the bar colour bleeds into the empty portion of the bar.
        healthBgAlpha = 0.22,
        showPower = true,
        powerHeight = 5,

        -- Text
        showName = true,
        -- none | percent | value | both
        healthText = "percent",
        -- nil means "the right font for this locale", resolved at draw time.
        fontFace = nil,
        fontSize = 11,
        fontOutline = "OUTLINE",
        fontShadow = false,

        -- Cast bar
        showCastBar = true,
        castBarHeight = 18,
        castBarIcon = true,

        -- Auras
        showBuffs = true,
        maxBuffs = 8,
        showDebuffs = true,
        maxDebuffs = 8,
        auraSize = 20,
        auraSpacing = 2,

        -- Filtering. All of it is applied by the client through the aura filter
        -- string, because addons cannot read aura data to filter it themselves.
        -- "all" | "mine" | "others"
        buffSource = "all",
        debuffSource = "all",
        -- Narrow to a single category; "any" leaves the row unrestricted.
        -- Buffs:   any | cancelable | defensive
        -- Debuffs: any | dispellable | crowdcontrol
        buffCategory = "any",
        debuffCategory = "any",
    }

    for key, value in pairs(overrides or {}) do
        unit[key] = value
    end

    return unit
end

local PUF_DEFAULTS = {
    -- Addon-wide: these cannot sensibly differ per frame.
    hideBlizzardFrames = true,
    unlocked = false,
    -- Seconds between health/power refreshes. Events drive most updates; this
    -- catches target-of-target, which has no reliable events of its own.
    refreshRate = 0.1,

    units = {
        player = UnitDefaults({ x = -270, y = -200 }),
        target = UnitDefaults({ x = 270, y = -200 }),
        targettarget = UnitDefaults({
            x = 470, y = -200,
            width = 120, height = 28,
            showPower = false,
            healthText = "none",
            showCastBar = false,
            showBuffs = false, maxBuffs = 4,
            showDebuffs = false, maxDebuffs = 4,
            auraSize = 16,
        }),
        focus = UnitDefaults({
            x = -470, y = -200,
            width = 180, height = 36,
            showBuffs = false, maxBuffs = 6,
            maxDebuffs = 6,
            auraSize = 18,
        }),
    },
}

PUF.Config = ConfigManager:NewWithAceDB(
    PUF,
    PUF_DEFAULTS,
    {
        savedVariablesName = "PeaversUnitFramesDB",
        profileType = "character",
        onProfileChanged = function()
            if PUF.Core and PUF.Core.RefreshAll then
                PUF.Core:RefreshAll()
            end
        end,
    }
)

PUF.Config.UNIT_ORDER = { "player", "target", "targettarget", "focus" }

PUF.Config.UNIT_LABELS = {
    player = "Player",
    target = "Target",
    targettarget = "Target of Target",
    focus = "Focus",
}

-- Config table for one unit, always non-nil so callers never have to guard.
function PUF.Config:GetUnit(key)
    local units = self.units
    return units and units[key] or {}
end

-- Defaults for one unit, used by the settings UI to resolve any value the
-- profile has not overridden.
function PUF.Config:GetUnitDefaults(key)
    local defaults = self.defaults and self.defaults.units
    return defaults and defaults[key] or {}
end

-- Settings that are never copied between frames. Position would stack every
-- frame on top of the source, and enabled would silently switch frames on or off
-- behind the user's back - neither is what "make these look the same" means.
local COPY_EXCLUDE = {
    x = true,
    y = true,
    enabled = true,
}

-- Tables have to be copied, not shared: healthColor assigned by reference would
-- leave all four frames pointing at one table, so recolouring one recolours all.
local function CopyValue(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for key, inner in pairs(value) do
        copy[key] = CopyValue(inner)
    end
    return copy
end

-- Push one frame's look onto the other three. Returns how many were updated.
function PUF.Config:CopyUnitToAll(sourceKey)
    local source = self:GetUnit(sourceKey)
    local defaults = self:GetUnitDefaults(sourceKey)
    local updated = 0

    for _, targetKey in ipairs(self.UNIT_ORDER) do
        if targetKey ~= sourceKey then
            local target = self:GetUnit(targetKey)

            -- Iterated over the defaults rather than the source: the source only
            -- holds keys it has actually diverged on, so walking it alone would
            -- skip every setting still sitting at its default and leave the
            -- target's own override in place.
            for key in pairs(defaults) do
                if not COPY_EXCLUDE[key] then
                    local value = source[key]
                    if value == nil then value = defaults[key] end
                    target[key] = CopyValue(value)
                end
            end

            updated = updated + 1
        end
    end

    self:Save()
    return updated
end

return PUF.Config
