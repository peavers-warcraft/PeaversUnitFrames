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

-- The section drawn plain at the top of the dialog instead of behind an
-- expander. Everything else in the schema becomes a collapsible group.
local TOP_SECTION = "frame"

-- Collapsible sections, taken from the schema so a new group only has to be
-- declared once. Built lazily: the schema is loaded after this file.
local sectionKeys
local function SectionKeys()
    if not sectionKeys then
        sectionKeys = {}
        for _, section in ipairs(PUF.UnitSettings.SectionsForSurface("editmode")) do
            if section.key ~= TOP_SECTION then
                sectionKeys[#sectionKeys + 1] = section.key
            end
        end
    end
    return sectionKeys
end

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
        for _, key in ipairs(SectionKeys()) do
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
-- Turning a schema entry into an Edit Mode setting
--
-- Nothing here decides what a setting is or what it may be set to - that all
-- lives in UnitSettings, which the settings page reads from too. This is only
-- the translation into what LibEditMode wants.
--------------------------------------------------------------------------------

local ST = LibEditMode and LibEditMode.SettingType
local UnitSettings = PUF.UnitSettings

-- A row is hidden when its section is collapsed, or when the setting itself
-- says it has nothing to offer right now - the custom colour with the bar on
-- class colours, for instance.
local function HiddenFn(entry, unitKey, section)
    if not section and not entry.hidden then return nil end

    return function()
        if section and not SectionShown(section) then return true end
        return UnitSettings.IsHidden(entry, unitKey)
    end
end

local function DisabledFn(entry, unitKey)
    if not entry.disabled then return nil end
    return function() return UnitSettings.IsDisabled(entry, unitKey) end
end

-- LibEditMode's dropdowns want `text` where the settings page's want `label`.
local function DropdownValues(entry)
    return function()
        local out = {}
        for _, option in ipairs(UnitSettings.Values(entry)) do
            out[#out + 1] = { value = option.value, text = option.label }
        end
        return out
    end
end

local function AsColor(value)
    value = value or {}
    return CreateColor(value.r or 1, value.g or 1, value.b or 1)
end

local Builders = {}

function Builders.checkbox(entry, unitKey)
    return {
        kind = ST.Checkbox,
        default = UnitSettings.Default(entry, unitKey) and true or false,
        get = function() return UnitSettings.Read(entry, unitKey) and true or false end,
        set = function(_, value) UnitSettings.Write(entry, unitKey, value and true or false) end,
    }
end

function Builders.slider(entry, unitKey)
    return {
        kind = ST.Slider,
        default = UnitSettings.Default(entry, unitKey) or entry.min,
        get = function() return UnitSettings.Read(entry, unitKey) or entry.min end,
        set = function(_, value) UnitSettings.Write(entry, unitKey, value) end,
        minValue = entry.min,
        maxValue = entry.max,
        valueStep = entry.step,
        formatter = UnitSettings.Formatter(entry),
    }
end

function Builders.dropdown(entry, unitKey)
    return {
        kind = ST.Dropdown,
        default = UnitSettings.Default(entry, unitKey),
        get = function() return UnitSettings.Read(entry, unitKey) end,
        set = function(_, value) UnitSettings.Write(entry, unitKey, value) end,
        values = DropdownValues(entry),
        height = entry.height,
    }
end

function Builders.color(entry, unitKey)
    return {
        kind = ST.ColorPicker,
        default = AsColor(UnitSettings.Default(entry, unitKey)),
        get = function() return AsColor(UnitSettings.Read(entry, unitKey)) end,
        set = function(_, color)
            UnitSettings.Write(entry, unitKey, { r = color.r, g = color.g, b = color.b })
        end,
    }
end

local function ToSetting(entry, unitKey, section)
    local builder = Builders[entry.kind]
    if not builder then return nil end

    local setting = builder(entry, unitKey)
    setting.name = entry.label
    setting.desc = entry.desc
    setting.hidden = HiddenFn(entry, unitKey, section)
    setting.disabled = DisabledFn(entry, unitKey)
    return setting
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

--------------------------------------------------------------------------------
-- The settings for one frame
--
-- The first section is drawn plain at the top of the dialog rather than behind
-- an expander: enabling a frame and sizing it are what people open this for,
-- and putting them one click away to save three rows would be a poor trade.
--------------------------------------------------------------------------------

local function BuildSettings(unitKey)
    local settings = {}

    for _, section in ipairs(UnitSettings.SectionsForSurface("editmode")) do
        local grouped = section.key ~= TOP_SECTION

        if grouped then
            settings[#settings + 1] = Expander(section.label, section.key)
        end

        for _, entry in ipairs(section.entries) do
            local setting = ToSetting(entry, unitKey, grouped and section.key or nil)
            if setting then
                settings[#settings + 1] = setting
            end
        end
    end

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

    -- After registration, because the dialog it squares up does not exist until
    -- the first AddFrame creates it.
    if PUF.EditModeStyle then
        PUF.EditModeStyle:Apply()
    end

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
