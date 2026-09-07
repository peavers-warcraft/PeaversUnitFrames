local addonName, PUF = ...

--------------------------------------------------------------------------------
-- UnitSettings
--
-- What a unit frame can be told to do, described once, rendered by the settings
-- page and by the Edit Mode dialog.
--
-- The machinery for that lives in PeaversCommons.SettingsSchema - this file is
-- the list. Almost none of these keys are standard Peavers settings, so unlike
-- most addons they are spelled out in full rather than resolved from
-- ConfigSchema.Common; the two that are standard, fontFace and barTexture, name
-- only their key and take their options from the collection.
--
-- Settings live per unit rather than on the config directly, which is what the
-- scope functions below are for: the same schema is rendered four times, once
-- per frame, with the unit key as its context.
--
-- `surface` decides where a setting appears. "both" is anything you judge by
-- looking at the frame while you drag it. "config" is anything picked off a
-- list once and forgotten - aura filters, text formats, fonts - which the
-- settings page can explain and a dialog with no scroll bar cannot.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons

local SECTIONS = {
    { key = "frame", label = "Frame" },
    { key = "bars", label = "Bars" },
    { key = "text", label = "Text" },
    { key = "cast", label = "Cast Bar" },
    { key = "auras", label = "Auras" },
}

local SOURCE_VALUES = {
    { value = "all", label = "Everyone's" },
    { value = "mine", label = "Only mine" },
    { value = "others", label = "Only other people's" },
}

-- Position is deliberately absent. It is dragged in Edit Mode and typed into a
-- pair of boxes on the settings page, and neither of those is a row in a list.
local ENTRIES = {
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
    -- Standard settings: the label, kind and option list all come from
    -- ConfigSchema.Common.
    { key = "barTexture", section = "bars", surface = "config", height = 300 },
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
    { key = "fontFace", section = "text", surface = "config", height = 300 },
    -- Stored as the outline flag the font API wants, shown as a tick. The schema
    -- knows this one by name and keeps whichever shape it finds.
    { key = "fontOutline", section = "text", surface = "config" },
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
-- The schema
--
-- Rendered once per frame, with the unit key as its context - which is what the
-- scope functions turn back into that frame's slice of the profile.
--------------------------------------------------------------------------------

local UnitSettings = PeaversCommons.SettingsSchema:New({
    config = PUF.Config,
    sections = SECTIONS,
    entries = ENTRIES,
    scope = function(config, unitKey) return config:GetUnit(unitKey) end,
    scopeDefaults = function(config, unitKey) return config:GetUnitDefaults(unitKey) end,
    apply = function(entry, unitKey)
        if not PUF.Core then return end
        PUF.Core.lastSetting = unitKey .. "." .. entry.key
        PUF.Core.lastSettingTime = GetTime()
        PUF.Core:RefreshUnit(unitKey)
    end,
})

PUF.UnitSettings = UnitSettings

-- Kept reachable for the tests, which check the declaration against the config
-- defaults in both directions.
UnitSettings.SECTIONS = SECTIONS
UnitSettings.DECLARED = ENTRIES

return UnitSettings
