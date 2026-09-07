local addonName, PUF = ...

--------------------------------------------------------------------------------
-- EditMode
--
-- Puts the four unit frames into Blizzard's Edit Mode, so they are placed and
-- configured where every other frame on the screen is placed and configured
-- rather than in a settings window layered over the top of them.
--
-- What gets registered is the *mover*, never the unit button itself. The button
-- is a SecureUnitButtonTemplate driven by RegisterUnitWatch: it is protected, it
-- hides itself whenever its unit does not exist, and LibEditMode parents its
-- selection overlay to whatever it is handed - so registering the button would
-- mean the target frame vanishes the moment you have no focus, taking its Edit
-- Mode handle with it. The mover is a plain unprotected frame that we control
-- the visibility of, which is exactly what Edit Mode wants.
--
-- Positions are still stored the way the rest of the addon stores them: an
-- offset from the centre of UIParent, per unit, in the character profile. Edit
-- Mode hands us its own anchor point and offset, and we deliberately throw that
-- away and re-derive the centre offset from where the mover actually landed.
-- That keeps one position format in the addon, keeps the typed X/Y boxes on the
-- settings page working and in sync, and means there is nothing to migrate.
--
-- Settings are likewise read and written straight through to the existing
-- per-character profile, ignoring the layout name Edit Mode passes in. Keying
-- them by Edit Mode layout instead is a real option and probably the eventual
-- answer, but it is a separate decision with its own migration; this pass
-- deliberately leaves the storage alone so that what is being tested is whether
-- the dialog is a good home for these settings, and nothing else.
--------------------------------------------------------------------------------

local LibEditMode = LibStub and LibStub("LibEditMode", true)

local EditMode = {}
PUF.EditMode = EditMode

EditMode.available = LibEditMode and true or false

local Config = PUF.Config

--------------------------------------------------------------------------------
-- Section state
--
-- The dialog has no scroll bar - it is a VerticalLayoutFrame that simply grows
-- until it runs off the screen - so a frame's thirty-odd settings have to be
-- collapsed into sections or they are unreachable on a short monitor. Expander
-- state is shared across the four frames on purpose: opening "Auras" on the
-- player and then clicking the target should not close it again.
--------------------------------------------------------------------------------

local function Sections()
    Config.editModeSections = Config.editModeSections or {}
    return Config.editModeSections
end

local SECTION_KEYS = { "bars", "text", "cast", "auras" }

local function SectionShown(name)
    return Sections()[name] and true or false
end

-- Ask Edit Mode to rebuild whichever of our dialogs is currently open. The
-- library checks that the frame it is handed is the selected one, so offering
-- it all four costs nothing and saves tracking the selection ourselves.
local function RebuildOpenDialog()
    for _, unitKey in ipairs(Config.UNIT_ORDER) do
        local unitFrame = PUF.Core and PUF.Core.frames[unitKey]
        if unitFrame and unitFrame.mover then
            LibEditMode:RefreshFrameSettings(unitFrame.mover)
        end
    end
end

-- One section open at a time.
--
-- The dialog has no scroll bar, it just grows: all four sections open is
-- thirty-four rows, which runs off the bottom of a 1080p screen. Closing the
-- others as one opens holds it to the tallest single section instead of the
-- sum of them.
--
-- The rebuild afterwards is not optional. An expander widget reads its own
-- open state once, when the dialog is built, and never again - Refresh only
-- re-evaluates whether it is hidden. So a section closed behind its back keeps
-- drawing an open arrow over no rows, and takes two clicks to reopen. Only a
-- rebuild puts every expander back in step with the config.
--
-- Two things keep that from running away. It is deferred a frame because this
-- is called from inside the expander's own click handler, which goes on to use
-- the widget after we return, and the rebuild releases it back to the pool.
-- And it only happens when a section was actually closed: building the dialog
-- calls this setter once per expander, and without that condition the open one
-- would request a rebuild every time, which would request another.
local function SetSection(name, value)
    local sections = Sections()
    local closedAnother = false

    if value then
        for _, key in ipairs(SECTION_KEYS) do
            if key ~= name and sections[key] then
                sections[key] = false
                closedAnother = true
            end
        end
    end

    sections[name] = value and true or false
    Config:Save()

    if closedAnother then
        C_Timer.After(0, RebuildOpenDialog)
    end
end

--------------------------------------------------------------------------------
-- Setting helpers
--------------------------------------------------------------------------------

local ST = LibEditMode and LibEditMode.SettingType

-- Per-unit write: the same path the settings page uses, so both surfaces behave
-- identically and neither can drift from the other.
local function SetUnit(unitKey, key, value)
    local unitConfig = Config:GetUnit(unitKey)
    unitConfig[key] = value
    Config:Save()

    if PUF.Core then
        PUF.Core.lastSetting = unitKey .. "." .. key
        PUF.Core.lastSettingTime = GetTime()
        PUF.Core:RefreshUnit(unitKey)
    end
end

local function GetUnit(unitKey, key)
    local value = Config:GetUnit(unitKey)[key]
    if value == nil then
        value = Config:GetUnitDefaults(unitKey)[key]
    end
    return value
end

-- Every setting below is built through these, so a setting is one line and the
-- layoutName argument Edit Mode passes is discarded in exactly one place.
local function Checkbox(unitKey, label, key, section, desc)
    return {
        kind = ST.Checkbox,
        name = label,
        desc = desc,
        default = Config:GetUnitDefaults(unitKey)[key] and true or false,
        get = function() return GetUnit(unitKey, key) and true or false end,
        set = function(_, value) SetUnit(unitKey, key, value and true or false) end,
        hidden = section and function() return not SectionShown(section) end or nil,
    }
end

local function Slider(unitKey, label, key, section, minValue, maxValue, step, formatter)
    return {
        kind = ST.Slider,
        name = label,
        default = Config:GetUnitDefaults(unitKey)[key] or minValue,
        get = function() return GetUnit(unitKey, key) or minValue end,
        set = function(_, value) SetUnit(unitKey, key, value) end,
        minValue = minValue,
        maxValue = maxValue,
        valueStep = step,
        formatter = formatter,
        hidden = section and function() return not SectionShown(section) end or nil,
    }
end

local function Dropdown(unitKey, label, key, section, values, fallback, height)
    return {
        kind = ST.Dropdown,
        name = label,
        default = Config:GetUnitDefaults(unitKey)[key] or fallback,
        get = function() return GetUnit(unitKey, key) or fallback end,
        set = function(_, value) SetUnit(unitKey, key, value) end,
        values = values,
        height = height,
        hidden = section and function() return not SectionShown(section) end or nil,
    }
end

local function Expander(label, section)
    return {
        kind = ST.Expander,
        name = label,
        default = false,
        get = function() return SectionShown(section) end,
        set = function(_, value) SetSection(section, value) end,
    }
end

-- Turns a {value = label} map from ConfigManager into the indexed list the
-- dropdown wants, sorted by label so the font list is not in hash order.
local function SortedOptions(map)
    local items = {}
    for value, label in pairs(map) do
        items[#items + 1] = { value = value, text = tostring(label) }
    end
    table.sort(items, function(a, b) return a.text < b.text end)
    return items
end

local function Percent(value)
    return math.floor((value * 100) + 0.5)
end

--------------------------------------------------------------------------------
-- The settings for one frame
--------------------------------------------------------------------------------

local SOURCE_VALUES = {
    { value = "all", text = "Everyone's" },
    { value = "mine", text = "Only mine" },
    { value = "others", text = "Only other people's" },
}

local function BuildSettings(unitKey)
    local ConfigManager = _G.PeaversCommons.ConfigManager
    local defaults = Config:GetUnitDefaults(unitKey)

    local settings = {
        Checkbox(unitKey, "Enabled", "enabled", nil,
            "Turn this frame off entirely. It keeps its position and settings."),
        Slider(unitKey, "Width", "width", nil, 80, 400, 2),
        Slider(unitKey, "Height", "height", nil, 16, 100, 1),
        Dropdown(unitKey, "Tooltip", "tooltip", nil, {
            { value = "always", text = "Always show" },
            { value = "ooc", text = "Hide in combat" },
            { value = "never", text = "Never show" },
        }, "always"),

        Expander("Bars", "bars"),
        Dropdown(unitKey, "Bar Texture", "barTexture", "bars",
            function() return SortedOptions(ConfigManager.GetBarTextures()) end,
            PUF.Style.GetTexture(nil), 300),
        Dropdown(unitKey, "Health Colour", "healthColorMode", "bars", {
            { value = "class", text = "Class / reaction" },
            { value = "custom", text = "Single colour" },
        }, "class"),
        {
            kind = ST.ColorPicker,
            name = "Single Colour",
            default = CreateColor(
                (defaults.healthColor or {}).r or 0.25,
                (defaults.healthColor or {}).g or 0.62,
                (defaults.healthColor or {}).b or 0.36),
            get = function()
                local c = GetUnit(unitKey, "healthColor") or {}
                return CreateColor(c.r or 0.25, c.g or 0.62, c.b or 0.36)
            end,
            set = function(_, color)
                SetUnit(unitKey, "healthColor", { r = color.r, g = color.g, b = color.b })
            end,
            -- Nothing to pick when the bar is taking its colour from the class.
            hidden = function()
                return not SectionShown("bars") or GetUnit(unitKey, "healthColorMode") ~= "custom"
            end,
        },
        Slider(unitKey, "Empty Bar Tint", "healthBgAlpha", "bars", 0, 0.6, 0.02, Percent),
        Slider(unitKey, "Background Opacity", "bgAlpha", "bars", 0, 1, 0.05, Percent),
        Checkbox(unitKey, "Show Power Bar", "showPower", "bars"),
        Slider(unitKey, "Power Bar Height", "powerHeight", "bars", 2, 14, 1),

        Expander("Text", "text"),
        Checkbox(unitKey, "Show Unit Name", "showName", "text"),
        Dropdown(unitKey, "Health Text", "healthText", "text", {
            { value = "none", text = "Hidden" },
            { value = "percent", text = "Percent" },
            { value = "value", text = "Value" },
            { value = "both", text = "Value and percent" },
        }, "percent"),
        Dropdown(unitKey, "Font", "fontFace", "text",
            function() return SortedOptions(ConfigManager.GetFonts()) end,
            PUF.Style.GetDefaultFont(), 300),
        Slider(unitKey, "Font Size", "fontSize", "text", 6, 24, 1),
        {
            kind = ST.Checkbox,
            name = "Font Outline",
            default = (defaults.fontOutline or "") == "OUTLINE",
            get = function() return GetUnit(unitKey, "fontOutline") == "OUTLINE" end,
            set = function(_, value) SetUnit(unitKey, "fontOutline", value and "OUTLINE" or "") end,
            hidden = function() return not SectionShown("text") end,
        },
        Checkbox(unitKey, "Font Shadow", "fontShadow", "text"),

        Expander("Cast Bar", "cast"),
        Checkbox(unitKey, "Show Cast Bar", "showCastBar", "cast"),
        Slider(unitKey, "Cast Bar Height", "castBarHeight", "cast", 10, 40, 1),
        Checkbox(unitKey, "Show Spell Icon", "castBarIcon", "cast"),

        Expander("Auras", "auras"),
        Checkbox(unitKey, "Show Buffs", "showBuffs", "auras"),
        Slider(unitKey, "Maximum Buffs", "maxBuffs", "auras", 1, 16, 1),
        Dropdown(unitKey, "Buffs Cast By", "buffSource", "auras", SOURCE_VALUES, "all"),
        Dropdown(unitKey, "Limit Buffs To", "buffCategory", "auras", {
            { value = "any", text = "Any buff" },
            { value = "cancelable", text = "Cancelable only" },
            { value = "defensive", text = "Major defensives only" },
        }, "any"),
        Checkbox(unitKey, "Show Mount", "showMount", "auras",
            "A dedicated slot above the buff row that only ever holds the mount."),
        Checkbox(unitKey, "Show Debuffs", "showDebuffs", "auras"),
        Slider(unitKey, "Maximum Debuffs", "maxDebuffs", "auras", 1, 16, 1),
        Dropdown(unitKey, "Debuffs Cast By", "debuffSource", "auras", SOURCE_VALUES, "all"),
        Dropdown(unitKey, "Limit Debuffs To", "debuffCategory", "auras", {
            { value = "any", text = "Any debuff" },
            { value = "dispellable", text = "Dispellable by me only" },
            { value = "crowdcontrol", text = "Crowd control only" },
        }, "any"),
        Slider(unitKey, "Aura Icon Size", "auraSize", "auras", 10, 40, 1),
        Slider(unitKey, "Aura Icon Spacing", "auraSpacing", "auras", 0, 10, 1),
    }

    return settings
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

-- Where a frame sits when it has never been moved, in the anchor form Edit Mode
-- compares against for its "Reset Position" button.
local function DefaultPosition(unitKey)
    local defaults = Config:GetUnitDefaults(unitKey)
    return {
        point = "CENTER",
        x = defaults.x or 0,
        y = defaults.y or 0,
    }
end

-- Edit Mode has finished moving the mover. Its anchor point and offset are
-- ignored: CommitMoverPosition reads where the mover physically is and converts
-- that into the centre offset the rest of the addon speaks, which also writes
-- the value back into the settings page's X/Y boxes.
local function OnPositionChanged(frame)
    local unitFrame = frame.pufUnitFrame
    if not unitFrame then return end

    unitFrame:CommitMoverPosition()
end

function EditMode:Register()
    if not self.available then return false end
    if self.registered then return true end

    for _, unitKey in ipairs(Config.UNIT_ORDER) do
        local unitFrame = PUF.Core.frames[unitKey]
        if unitFrame and unitFrame.mover then
            local mover = unitFrame.mover
            mover.pufUnitFrame = unitFrame

            LibEditMode:AddFrame(
                mover,
                OnPositionChanged,
                DefaultPosition(unitKey),
                "Peavers " .. (Config.UNIT_LABELS[unitKey] or unitKey)
            )

            LibEditMode:AddFrameSettings(mover, BuildSettings(unitKey))

            LibEditMode:AddFrameSettingsButtons(mover, {
                {
                    text = "Copy To All Frames",
                    click = function()
                        StaticPopup_Show("PEAVERSUNITFRAMES_COPY_TO_ALL",
                            Config.UNIT_LABELS[unitKey] or unitKey, nil, unitKey)
                    end,
                },
            })
        end
    end

    LibEditMode:RegisterCallback("enter", function() EditMode:OnEnter() end)
    LibEditMode:RegisterCallback("exit", function() EditMode:OnExit() end)
    LibEditMode:RegisterCallback("layout", function() EditMode:OnLayout() end)

    self.registered = true
    return true
end

--------------------------------------------------------------------------------
-- Entering and leaving
--------------------------------------------------------------------------------

-- All four movers come out, including any whose frame is switched off: the
-- Enabled checkbox lives in the dialog, and a frame you cannot select is a
-- frame you cannot turn back on.
function EditMode:OnEnter()
    self.editing = true

    for _, unitKey in ipairs(Config.UNIT_ORDER) do
        local unitFrame = PUF.Core.frames[unitKey]
        if unitFrame then
            unitFrame:SetEditModeShown(true)
        end
    end
end

function EditMode:OnExit()
    self.editing = false

    for _, unitKey in ipairs(Config.UNIT_ORDER) do
        local unitFrame = PUF.Core.frames[unitKey]
        if unitFrame then
            unitFrame:SetEditModeShown(false)
        end
    end

    -- Whatever was changed in the dialog has been written a setting at a time;
    -- this puts the frames back under the normal lock state afterwards.
    if PUF.Core then
        PUF.Core:SetUnlocked(Config.unlocked and true or false)
    end
end

-- Positions are not keyed by layout yet, so switching layout changes nothing
-- about where the frames go. The movers still have to be put back over their
-- frames, since they were free-floating while being dragged.
function EditMode:OnLayout()
    if not self.editing then return end

    for _, unitKey in ipairs(Config.UNIT_ORDER) do
        local unitFrame = PUF.Core.frames[unitKey]
        if unitFrame then
            unitFrame:SyncMover()
        end
    end
end

function EditMode:IsEditing()
    return self.editing and true or false
end

return EditMode
