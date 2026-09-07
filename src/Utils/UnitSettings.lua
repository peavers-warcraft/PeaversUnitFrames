local addonName, PUF = ...

--------------------------------------------------------------------------------
-- UnitSettings
--
-- One description of what a unit frame can be told to do, rendered by both the
-- settings page and the Edit Mode dialog.
--
-- Before this the two surfaces each carried their own hand-written copy of the
-- same thirty-one settings, in two different widget vocabularies, with the
-- ranges typed out twice. Adding a setting meant adding it twice; renaming a
-- config key broke one surface quietly. That does not survive being repeated
-- across ten addons, so the list lives here and the surfaces render it.
--
-- Each entry says what the setting *is*, never how it is drawn:
--
--   key       the field in the unit's config table
--   label     what to call it
--   kind      checkbox | slider | dropdown | color
--   section   which group it belongs to, shared by both surfaces
--   surface   where it appears - see below
--   unit      px | pt | percent, for formatting the value
--   read      optional: stored value  -> what the widget shows
--   write     optional: what the widget gives -> stored value
--   hidden    optional: hide this row given the unit's current config
--
-- `surface` is the interesting one. "both" is for anything you decide by
-- looking at the frame while you drag it - sizes, spacing, how many aura icons.
-- "config" is for anything you decide off a list and then forget: aura
-- filtering, text formats, fonts. Those are worse in an Edit Mode dialog, which
-- has no room to explain what "Dispellable by me only" means, and better on a
-- settings page that can. Keeping them out is most of the difference between a
-- dialog of twenty-one rows and one of thirty-one.
--------------------------------------------------------------------------------

local UnitSettings = {}
PUF.UnitSettings = UnitSettings

--------------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------------

UnitSettings.SECTIONS = {
    { key = "frame", label = "Frame" },
    { key = "bars", label = "Bars" },
    { key = "text", label = "Text" },
    { key = "cast", label = "Cast Bar" },
    { key = "auras", label = "Auras" },
}

--------------------------------------------------------------------------------
-- Value formatting
--
-- A bare number in a value column is ambiguous: a screenshot of this dialog had
-- "30" (a percentage) directly above "40" (pixels) with nothing to tell them
-- apart. Both surfaces take a formatter that returns a string, so one function
-- serves each.
--------------------------------------------------------------------------------

local FORMATTERS = {
    px = function(value) return math.floor(value + 0.5) .. "px" end,
    pt = function(value) return math.floor(value + 0.5) .. "pt" end,
    percent = function(value) return math.floor((value * 100) + 0.5) .. "%" end,
}

function UnitSettings.Formatter(entry)
    return entry.unit and FORMATTERS[entry.unit] or nil
end

--------------------------------------------------------------------------------
-- Option lists
--
-- Anything sourced from the collection is a function, because ConfigManager's
-- media lists are not populated until LibSharedMedia has been read.
--------------------------------------------------------------------------------

local function Sorted(map)
    local items = {}
    for value, label in pairs(map) do
        items[#items + 1] = { value = value, label = tostring(label) }
    end
    table.sort(items, function(a, b) return a.label < b.label end)
    return items
end

local function Fonts()
    return Sorted(_G.PeaversCommons.ConfigManager.GetFonts())
end

local function BarTextures()
    return Sorted(_G.PeaversCommons.ConfigManager.GetBarTextures())
end

local SOURCE_VALUES = {
    { value = "all", label = "Everyone's" },
    { value = "mine", label = "Only mine" },
    { value = "others", label = "Only other people's" },
}

--------------------------------------------------------------------------------
-- The settings
--------------------------------------------------------------------------------

-- Position is deliberately absent. It is dragged in Edit Mode and typed into a
-- pair of boxes on the settings page, and neither of those is a row in a list.
UnitSettings.ENTRIES = {
    ----------------------------------------------------------------- frame ---
    {
        key = "enabled", label = "Enabled", kind = "checkbox",
        section = "frame", surface = "both",
        desc = "Turn this frame off entirely. It keeps its position and settings.",
    },
    {
        key = "width", label = "Width", kind = "slider",
        section = "frame", surface = "both",
        min = 80, max = 400, step = 2, unit = "px",
    },
    {
        key = "height", label = "Height", kind = "slider",
        section = "frame", surface = "both",
        min = 16, max = 100, step = 1, unit = "px",
    },
    {
        key = "tooltip", label = "Tooltip", kind = "dropdown",
        section = "frame", surface = "config", fallback = "always",
        values = {
            { value = "always", label = "Always show" },
            { value = "ooc", label = "Hide in combat" },
            { value = "never", label = "Never show" },
        },
    },

    ------------------------------------------------------------------ bars ---
    {
        key = "barTexture", label = "Bar Texture", kind = "dropdown",
        section = "bars", surface = "config", values = BarTextures, height = 300,
        fallback = function() return PUF.Style.GetTexture(nil) end,
    },
    {
        key = "healthColorMode", label = "Health Colour", kind = "dropdown",
        section = "bars", surface = "both", fallback = "class",
        -- Choosing "custom" reveals the colour swatch below.
        revealsOthers = true,
        values = {
            { value = "class", label = "Class / reaction" },
            { value = "custom", label = "Single colour" },
        },
    },
    {
        key = "healthColor", label = "Custom Colour", kind = "color",
        section = "bars", surface = "both",
        -- Nothing to pick while the bar is taking its colour from the class.
        hidden = function(cfg) return cfg.healthColorMode ~= "custom" end,
    },
    {
        key = "healthBgAlpha", label = "Empty Bar Tint", kind = "slider",
        section = "bars", surface = "both",
        min = 0, max = 0.6, step = 0.02, unit = "percent",
    },
    {
        key = "bgAlpha", label = "Background Opacity", kind = "slider",
        section = "bars", surface = "both",
        min = 0, max = 1, step = 0.05, unit = "percent",
    },
    {
        key = "showPower", label = "Show Power Bar", kind = "checkbox",
        section = "bars", surface = "both",
    },
    {
        key = "powerHeight", label = "Power Bar Height", kind = "slider",
        section = "bars", surface = "both",
        min = 2, max = 14, step = 1, unit = "px",
        disabled = function(cfg) return not cfg.showPower end,
    },

    ------------------------------------------------------------------ text ---
    {
        key = "showName", label = "Show Unit Name", kind = "checkbox",
        section = "text", surface = "both",
    },
    {
        key = "fontSize", label = "Font Size", kind = "slider",
        section = "text", surface = "both",
        min = 6, max = 24, step = 1, unit = "pt",
    },
    {
        key = "healthText", label = "Health Text", kind = "dropdown",
        section = "text", surface = "config", fallback = "percent",
        values = {
            { value = "none", label = "Hidden" },
            { value = "percent", label = "Percent" },
            { value = "value", label = "Value" },
            { value = "both", label = "Value and percent" },
        },
    },
    {
        key = "fontFace", label = "Font", kind = "dropdown",
        section = "text", surface = "config", values = Fonts, height = 300,
        fallback = function() return PUF.Style.GetDefaultFont() end,
    },
    {
        -- Stored as the outline flag the font API wants, shown as a tick.
        key = "fontOutline", label = "Font Outline", kind = "checkbox",
        section = "text", surface = "config",
        read = function(stored) return stored == "OUTLINE" end,
        write = function(shown) return shown and "OUTLINE" or "" end,
    },
    {
        key = "fontShadow", label = "Font Shadow", kind = "checkbox",
        section = "text", surface = "config",
    },

    ------------------------------------------------------------------ cast ---
    {
        key = "showCastBar", label = "Show Cast Bar", kind = "checkbox",
        section = "cast", surface = "both",
    },
    {
        key = "castBarHeight", label = "Cast Bar Height", kind = "slider",
        section = "cast", surface = "both",
        min = 10, max = 40, step = 1, unit = "px",
        disabled = function(cfg) return not cfg.showCastBar end,
    },
    {
        key = "castBarIcon", label = "Show Spell Icon", kind = "checkbox",
        section = "cast", surface = "both",
        disabled = function(cfg) return not cfg.showCastBar end,
    },

    ----------------------------------------------------------------- auras ---
    {
        key = "showBuffs", label = "Show Buffs", kind = "checkbox",
        section = "auras", surface = "both",
    },
    {
        key = "maxBuffs", label = "Maximum Buffs", kind = "slider",
        section = "auras", surface = "both",
        min = 1, max = 16, step = 1,
        disabled = function(cfg) return not cfg.showBuffs end,
    },
    {
        key = "buffSource", label = "Buffs Cast By", kind = "dropdown",
        section = "auras", surface = "config", fallback = "all", values = SOURCE_VALUES,
    },
    {
        key = "buffCategory", label = "Limit Buffs To", kind = "dropdown",
        section = "auras", surface = "config", fallback = "any",
        values = {
            { value = "any", label = "Any buff" },
            { value = "cancelable", label = "Cancelable only" },
            { value = "defensive", label = "Major defensives only" },
        },
    },
    {
        key = "showMount", label = "Show Mount", kind = "checkbox",
        section = "auras", surface = "both",
        desc = "A dedicated slot above the buff row that only ever holds the mount.",
    },
    {
        key = "showDebuffs", label = "Show Debuffs", kind = "checkbox",
        section = "auras", surface = "both",
    },
    {
        key = "maxDebuffs", label = "Maximum Debuffs", kind = "slider",
        section = "auras", surface = "both",
        min = 1, max = 16, step = 1,
        disabled = function(cfg) return not cfg.showDebuffs end,
    },
    {
        key = "debuffSource", label = "Debuffs Cast By", kind = "dropdown",
        section = "auras", surface = "config", fallback = "all", values = SOURCE_VALUES,
    },
    {
        key = "debuffCategory", label = "Limit Debuffs To", kind = "dropdown",
        section = "auras", surface = "config", fallback = "any",
        values = {
            { value = "any", label = "Any debuff" },
            { value = "dispellable", label = "Dispellable by me only" },
            { value = "crowdcontrol", label = "Crowd control only" },
        },
    },
    {
        key = "auraSize", label = "Aura Icon Size", kind = "slider",
        section = "auras", surface = "both",
        min = 10, max = 40, step = 1, unit = "px",
    },
    {
        key = "auraSpacing", label = "Aura Icon Spacing", kind = "slider",
        section = "auras", surface = "both",
        min = 0, max = 10, step = 1, unit = "px",
    },
}

--------------------------------------------------------------------------------
-- Reading and writing
--
-- Both surfaces go through here, so neither can drift from the other on what a
-- setting means, what it falls back to, or what happens after it changes.
--------------------------------------------------------------------------------

local function Resolve(value)
    if type(value) == "function" then return value() end
    return value
end

-- The list of options for a dropdown, as { value, label } pairs.
function UnitSettings.Values(entry)
    return Resolve(entry.values) or {}
end

-- What the widget should show for this setting on this frame.
function UnitSettings.Read(entry, unitKey)
    local Config = PUF.Config
    local stored = Config:GetUnit(unitKey)[entry.key]

    if stored == nil then
        stored = Config:GetUnitDefaults(unitKey)[entry.key]
    end
    if stored == nil then
        stored = Resolve(entry.fallback)
    end

    if entry.read then
        return entry.read(stored)
    end
    return stored
end

-- What a fresh profile would show, for the "reset to default" affordances both
-- surfaces offer.
function UnitSettings.Default(entry, unitKey)
    local stored = PUF.Config:GetUnitDefaults(unitKey)[entry.key]
    if stored == nil then
        stored = Resolve(entry.fallback)
    end

    if entry.read then
        return entry.read(stored)
    end
    return stored
end

-- Write a setting and rebuild that one frame. This was duplicated verbatim in
-- both surfaces; it belongs with the thing being written.
function UnitSettings.Write(entry, unitKey, value)
    local stored = value
    if entry.write then
        stored = entry.write(value)
    end

    PUF.Config:GetUnit(unitKey)[entry.key] = stored
    PUF.Config:Save()

    if PUF.Core then
        PUF.Core.lastSetting = unitKey .. "." .. entry.key
        PUF.Core.lastSettingTime = GetTime()
        PUF.Core:RefreshUnit(unitKey)
    end
end

function UnitSettings.IsHidden(entry, unitKey)
    if not entry.hidden then return false end
    return entry.hidden(PUF.Config:GetUnit(unitKey)) and true or false
end

function UnitSettings.IsDisabled(entry, unitKey)
    if not entry.disabled then return false end
    return entry.disabled(PUF.Config:GetUnit(unitKey)) and true or false
end

--------------------------------------------------------------------------------
-- Selection
--------------------------------------------------------------------------------

-- Entries a surface should draw, in declaration order.
function UnitSettings.ForSurface(surface)
    local out = {}
    for _, entry in ipairs(UnitSettings.ENTRIES) do
        if entry.surface == "both" or entry.surface == surface then
            out[#out + 1] = entry
        end
    end
    return out
end

-- The same, grouped by section and skipping sections a surface has nothing in.
-- Returns a list of { key, label, entries }.
function UnitSettings.SectionsForSurface(surface)
    local bySection = {}
    for _, entry in ipairs(UnitSettings.ForSurface(surface)) do
        bySection[entry.section] = bySection[entry.section] or {}
        local list = bySection[entry.section]
        list[#list + 1] = entry
    end

    local out = {}
    for _, section in ipairs(UnitSettings.SECTIONS) do
        local entries = bySection[section.key]
        if entries and #entries > 0 then
            out[#out + 1] = { key = section.key, label = section.label, entries = entries }
        end
    end
    return out
end

return UnitSettings
