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
        width = 170,
        height = 40,
        x = 0,
        y = -395,
        bgAlpha = 0.85,
        -- A square 2D portrait inside the frame, as tall as the frame. It takes
        -- its room out of the width rather than adding to it, so turning it on
        -- or off never moves anything else.
        showPortrait = true,
        -- left | right. Player faces in from the left, everything else from
        -- the right, so a player/target pair reads as two faces looking at each
        -- other across the screen.
        portraitSide = "right",
        -- When the unit tooltip appears on mouseover: always | ooc | never.
        -- "ooc" is the usual compromise: useful while inspecting something, out
        -- of the way once the fight starts.
        tooltip = "always",

        -- Bars
        -- nil means "whatever the collection uses", resolved at draw time by
        -- Style.GetTexture the same way fontFace is. Spelling out Blizzard's
        -- texture here would pin every new profile to it and quietly opt the
        -- unit frames out of the shared house style.
        barTexture = nil,
        -- "class" colours players by class and NPCs by reaction; "custom" paints
        -- every health bar with healthColor instead. The house look is a black
        -- bar: the frame reads as a dark slab, and the class colour lives in the
        -- tint on the empty part and in the power strip instead.
        healthColorMode = "custom",
        healthColor = { r = 0, g = 0, b = 0 },
        -- How much of the bar colour bleeds into the empty portion of the bar.
        healthBgAlpha = 0.3,
        showPower = true,
        powerHeight = 6,
        -- "power" colours the bar by the resource (blue mana, red rage),
        -- "class" by the unit's class or reaction like the health bar, and
        -- "custom" paints it with powerColor.
        powerColorMode = "power",
        powerColor = { r = 0.20, g = 0.40, b = 0.90 },
        -- "same" follows barTexture; anything else is a texture path of its own.
        powerTexture = "same",
        -- Ease health and power to each new value instead of jumping. The
        -- animation only runs while a bar is moving, so a bar at rest costs
        -- nothing.
        smoothBars = true,

        -- Text
        showName = true,
        -- none | percent | value | both
        healthText = "both",
        -- nil means "the right font for this locale", resolved at draw time.
        fontFace = nil,
        fontSize = 12,
        -- A soft drop shadow rather than an outline: on a flat bar the outline
        -- only thickens the letters, and the shadow keeps them crisp.
        fontOutline = false,
        fontShadow = true,

        -- Cast bar
        showCastBar = true,
        castBarHeight = 16,
        castBarIcon = false,

        -- Auras
        showBuffs = true,
        maxBuffs = 8,
        -- A dedicated slot next to the buff row that only ever holds the unit's
        -- mount, so it survives whatever the buff filters are set to.
        showMount = false,
        showDebuffs = true,
        maxDebuffs = 8,
        auraSize = 22,
        auraSpacing = 1,

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

    -- Which sections of the Edit Mode dialog are open. Shared by all four
    -- frames rather than stored per unit: the dialog is the same shape whichever
    -- frame is selected, and having it reshuffle as you click between them
    -- would be worse than remembering one set of choices.
    editModeSections = {
        bars = false,
        text = false,
        cast = false,
        auras = false,
    },

    units = {
        -- A compact pair either side of the character, low on the screen. The
        -- player frame stays quiet - a thin class-coloured power strip and no
        -- auras or cast bar, which the rest of the UI already shows - while the
        -- target carries the debuffs you put on it.
        player = UnitDefaults({
            x = -429,
            portraitSide = "left", showPortrait = false,
            tooltip = "never",
            powerHeight = 3, powerColorMode = "class",
            showCastBar = false,
            showBuffs = false, maxBuffs = 1,
            showDebuffs = false,
        }),
        target = UnitDefaults({
            x = 429,
            showPortrait = false,
            tooltip = "ooc",
            showPower = false,
            showMount = true,
            debuffSource = "mine",
        }),
        targettarget = UnitDefaults({
            x = 600,
            width = 124, height = 28,
            showPortrait = false,
            tooltip = "ooc",
            healthBgAlpha = 0.26,
            showPower = false,
            healthText = "percent",
            showCastBar = false, castBarHeight = 14,
            showBuffs = false,
            showDebuffs = false,
            auraSize = 20,
        }),
        -- Off until somebody asks for it; set up to match the player frame on
        -- the far side when they do.
        focus = UnitDefaults({
            enabled = false,
            x = -600,
            healthText = "percent",
            showPower = false,
            showCastBar = false,
            showMount = true,
            auraSize = 20,
        }),
    },
}

--------------------------------------------------------------------------------
-- Keeping existing installs looking the way they did
--
-- A saved profile only holds what somebody changed; everything else comes from
-- the defaults above. So changing a default changes the look of every install
-- that never touched that setting - which, for the restyle that introduced
-- these defaults, would have handed every existing player black health bars, a
-- hidden focus frame and a player frame with no cast bar or auras.
--
-- So the first time a profile from before the change is loaded, the defaults it
-- was drawn with are written into it for every setting it never changed. Fresh
-- installs get the new look; existing ones keep theirs, and can still change
-- any of it. A version stamp makes it a one-off.
--------------------------------------------------------------------------------

local DEFAULTS_VERSION = 2

-- The per-unit defaults as they stood up to and including 1.0.13.
local function LegacyUnitDefaults(overrides)
    local unit = {
        enabled = true,
        width = 240, height = 46,
        x = 0, y = 0,
        tooltip = "always",
        healthColorMode = "class",
        healthColor = { r = 0.25, g = 0.62, b = 0.36 },
        healthBgAlpha = 0.22,
        showPower = true, powerHeight = 5,
        showName = true,
        healthText = "percent",
        fontSize = 11, fontOutline = "OUTLINE", fontShadow = false,
        showCastBar = true, castBarHeight = 18, castBarIcon = true,
        showBuffs = true, maxBuffs = 8,
        showMount = false,
        showDebuffs = true, maxDebuffs = 8,
        auraSize = 20, auraSpacing = 2,
        debuffSource = "all",
        -- There was no portrait, so nobody who had the addon before gets one
        -- they did not ask for.
        showPortrait = false,
    }
    for key, value in pairs(overrides or {}) do
        unit[key] = value
    end
    return unit
end

local LEGACY_UNITS = {
    player = LegacyUnitDefaults({ x = -270, y = -200 }),
    target = LegacyUnitDefaults({ x = 270, y = -200, showMount = true }),
    targettarget = LegacyUnitDefaults({
        x = 470, y = -200,
        width = 120, height = 28,
        showPower = false,
        healthText = "none",
        showCastBar = false,
        showBuffs = false, maxBuffs = 4,
        showDebuffs = false, maxDebuffs = 4,
        auraSize = 16,
    }),
    focus = LegacyUnitDefaults({
        x = -470, y = -200,
        width = 180, height = 36,
        showBuffs = false, maxBuffs = 6,
        maxDebuffs = 6,
        showMount = true,
        auraSize = 18,
    }),
}

local function SameValue(a, b)
    if type(a) == "table" and type(b) == "table" then
        return a.r == b.r and a.g == b.g and a.b == b.b
    end
    return a == b
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = v end
    return copy
end

local SV_NAME = "PeaversUnitFramesDB"

--- Write the old defaults into every profile saved before they changed.
--- @return number migrated profiles touched
local function PreserveLegacyLook()
    local sv = _G[SV_NAME]
    -- No saved data at all is a fresh install: nothing to preserve.
    if type(sv) ~= "table" then return 0 end
    if type(sv.global) == "table" and (sv.global.defaultsVersion or 0) >= DEFAULTS_VERSION then
        return 0
    end
    if type(sv.profiles) ~= "table" then return 0 end

    local migrated = 0
    for _, profile in pairs(sv.profiles) do
        if type(profile) == "table" then
            profile.units = type(profile.units) == "table" and profile.units or {}
            for unitKey, legacy in pairs(LEGACY_UNITS) do
                local saved = type(profile.units[unitKey]) == "table" and profile.units[unitKey] or {}
                local current = PUF_DEFAULTS.units[unitKey]
                for key, value in pairs(legacy) do
                    -- Only what the profile left at its default, and only where
                    -- the default actually moved: anything equal would be
                    -- stripped again by AceDB on the way out.
                    if saved[key] == nil and not SameValue(current[key], value) then
                        saved[key] = Copy(value)
                    end
                end
                profile.units[unitKey] = saved
            end
            migrated = migrated + 1
        end
    end
    return migrated
end

--- Mark the saved data as drawn with the current defaults. Runs after AceDB has
--- created the table, so a fresh install is stamped too and never migrated.
local function StampDefaultsVersion()
    local sv = _G[SV_NAME]
    if type(sv) ~= "table" then return end
    sv.global = type(sv.global) == "table" and sv.global or {}
    sv.global.defaultsVersion = DEFAULTS_VERSION
end

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

-- Attached after the config exists; defined above beside the data they use.
PUF.Config.PreserveLegacyLook = function() return PreserveLegacyLook() end
PUF.Config.StampDefaultsVersion = function() return StampDefaultsVersion() end

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
