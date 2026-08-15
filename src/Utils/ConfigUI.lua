local _, PUF = ...
local Config = PUF.Config

local ConfigUI = {}
PUF.ConfigUI = ConfigUI

-- X/Y boxes currently on screen, so a dragged frame can write its new offsets
-- back into the settings page.
ConfigUI.positionInputs = {}

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local W = PeaversCommons.Widgets
local ConfigUIUtils = PeaversCommons.ConfigUIUtils
local ConfigManager = PeaversCommons.ConfigManager

--------------------------------------------------------------------------------
-- Layout metrics for the hand-placed controls
--------------------------------------------------------------------------------

local ROW = 30
local ROW_DESC = 40
local SLIDER = 52
local DROPDOWN = 58
local BUTTON = 38
local SECTION_GAP = 8
local SECTION_END = 12

--------------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------------

local function GetPageOpts(parentFrame)
    local indent = 25
    local width = 360
    local frameWidth = parentFrame:GetWidth()
    if frameWidth and frameWidth > 100 then
        width = frameWidth - (indent * 2) - 10
    end
    return indent, width
end

local function SortedOptions(map)
    local items = {}
    for value, label in pairs(map) do
        items[#items + 1] = { value = value, label = label }
    end
    table.sort(items, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return items
end

-- Addon-wide setting: write, persist, rebuild everything.
local function Set(key, value)
    Config[key] = value
    Config:Save()

    if PUF.Core then
        PUF.Core.lastSetting = key
        PUF.Core.lastSettingTime = GetTime()
    end

    if key == "refreshRate" then
        if PUF.Core then PUF.Core:StartTicker() end
        return
    end

    if PUF.Core then PUF.Core:RefreshAll() end
end

-- Per-unit setting: write into that unit's table and rebuild only that frame.
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

--------------------------------------------------------------------------------
-- Copy to all frames
--
-- Overwrites three frames' settings and cannot be undone, so it asks first.
--------------------------------------------------------------------------------

StaticPopupDialogs["PEAVERSUNITFRAMES_COPY_TO_ALL"] = {
    text = "Copy the %s frame's settings to all other frames?"
        .. "\n\nPosition and enabled state are left alone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, unitKey)
        local updated = Config:CopyUnitToAll(unitKey)
        if PUF.Core then PUF.Core:RefreshAll() end
        PeaversCommons.Utils.Print(PUF, string.format(
            "Copied %s settings to %d other frame%s.",
            Config.UNIT_LABELS[unitKey] or unitKey, updated, updated == 1 and "" or "s"))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- Per-unit page
--
-- Every frame gets the complete set. Nothing here is shared with the other three
-- frames, so the player bar can be tall with a big font while target-of-target
-- stays a thin strip.
--------------------------------------------------------------------------------

function ConfigUI:BuildUnitPage(parentFrame, unitKey)
    local indent, width = GetPageOpts(parentFrame)
    local cfg = Config:GetUnit(unitKey)
    local defaults = Config:GetUnitDefaults(unitKey)
    local y = -10

    local function Section(title)
        local _, newY = W:CreateSectionHeader(parentFrame, title, indent, y - SECTION_END)
        y = newY - SECTION_GAP
    end

    local function Place(widget, height)
        widget:SetPoint("TOPLEFT", indent, y)
        y = y - height
    end

    local function Checkbox(label, key, description)
        local widget = W:CreateCheckbox(parentFrame, label, {
            checked = cfg[key] and true or false,
            width = width,
            description = description,
            onChange = function(checked) SetUnit(unitKey, key, checked) end,
        })
        Place(widget, description and ROW_DESC or ROW)
    end

    local function Slider(label, key, minValue, maxValue, step, formatter)
        local widget = W:CreateSlider(parentFrame, label, {
            min = minValue, max = maxValue, step = step,
            value = cfg[key] or defaults[key] or minValue,
            width = width,
            format = formatter,
            onChange = function(value) SetUnit(unitKey, key, value) end,
        })
        Place(widget, SLIDER)
    end

    local function Dropdown(label, key, options, fallback)
        local widget = W:CreateDropdown(parentFrame, label, {
            options = options,
            selected = cfg[key] or fallback,
            width = width,
            onChange = function(value) SetUnit(unitKey, key, value) end,
        })
        Place(widget, DROPDOWN)
    end

    ----------------------------------------------------------------------------

    local unitLabel = Config.UNIT_LABELS[unitKey] or unitKey

    local copyButton = W:CreateButton(parentFrame, "Copy to All Frames", {
        variant = "secondary",
        width = 170,
        onClick = function()
            StaticPopup_Show("PEAVERSUNITFRAMES_COPY_TO_ALL", unitLabel, nil, unitKey)
        end,
    })
    Place(copyButton, ROW)

    local copyHint = W:CreateLabel(parentFrame,
        "Give the other three frames this frame's look. Position and enabled state are kept.", {
            font = "GameFontNormalSmall",
            color = W.Colors.textMuted,
        })
    copyHint:SetPoint("TOPLEFT", indent, y)
    copyHint:SetWidth(width)
    copyHint:SetJustifyH("LEFT")
    y = y - 22

    Section("Frame")
    Checkbox("Enabled", "enabled")
    Slider("Width", "width", 80, 400, 2)
    Slider("Height", "height", 16, 100, 1)
    Slider("Background Opacity", "bgAlpha", 0, 1, 0.05)

    Section("Position")

    local posHint = W:CreateLabel(parentFrame,
        "Pixels from the centre of the screen. Positive X is right, positive Y is up.", {
            font = "GameFontNormalSmall",
            color = W.Colors.textMuted,
        })
    posHint:SetPoint("TOPLEFT", indent, y)
    posHint:SetWidth(width)
    posHint:SetJustifyH("LEFT")
    y = y - 20

    -- Typed offsets rather than sliders: the point of these is lining frames up
    -- exactly, which means entering the same number twice, not dragging to it.
    local function PositionInput(label, key, xOffset, boxWidth)
        local input = W:CreateInput(parentFrame, label, {
            width = boxWidth,
            text = tostring(math.floor((cfg[key] or 0) + 0.5)),
        })
        input:SetPoint("TOPLEFT", indent + xOffset, y)

        local function Commit()
            local value = tonumber(input:GetText())
            if value then
                value = math.floor(value + 0.5)
                input:SetText(tostring(value))
                SetUnit(unitKey, key, value)
            else
                -- Not a number: restore what is actually stored rather than
                -- leaving the box showing something that was never applied.
                local current = Config:GetUnit(unitKey)[key] or 0
                input:SetText(tostring(math.floor(current + 0.5)))
            end
        end

        -- Enter also clears focus, so both hooks fire; Commit is idempotent.
        input.editBox:HookScript("OnEnterPressed", Commit)
        input.editBox:HookScript("OnEditFocusLost", Commit)

        -- Registered so dragging a frame updates the numbers in place; a page
        -- rebuild simply replaces the entry.
        ConfigUI.positionInputs[unitKey] = ConfigUI.positionInputs[unitKey] or {}
        ConfigUI.positionInputs[unitKey][key] = input

        return input
    end

    local half = math.floor((width - 10) / 2)
    PositionInput("X Offset", "x", 0, half)
    PositionInput("Y Offset", "y", half + 10, half)
    y = y - 48

    Section("Bars")
    Dropdown("Bar Texture", "barTexture", SortedOptions(ConfigManager.GetBarTextures()),
        "Interface\\TargetingFrame\\UI-StatusBar")
    Dropdown("Health Bar Colour", "healthColorMode", {
        { value = "class", label = "Class / reaction" },
        { value = "custom", label = "Single colour" },
    }, "class")

    local custom = cfg.healthColor or defaults.healthColor or { r = 0.25, g = 0.62, b = 0.36 }
    local colorPicker = W:CreateColorPicker(parentFrame, "Single Colour", {
        r = custom.r, g = custom.g, b = custom.b,
        width = width,
        onChange = function(r, g, b) SetUnit(unitKey, "healthColor", { r = r, g = g, b = b }) end,
    })
    Place(colorPicker, ROW)

    Slider("Empty Bar Tint", "healthBgAlpha", 0, 0.6, 0.02)
    Checkbox("Show Power Bar", "showPower")
    Slider("Power Bar Height", "powerHeight", 2, 14, 1)

    Section("Text")
    Checkbox("Show Unit Name", "showName")
    Dropdown("Health Text", "healthText", {
        { value = "none", label = "Hidden" },
        { value = "percent", label = "Percent" },
        { value = "value", label = "Value" },
        { value = "both", label = "Value and percent" },
    }, "percent")
    Dropdown("Font", "fontFace", SortedOptions(ConfigManager.GetFonts()), PUF.Style.GetDefaultFont())
    Slider("Font Size", "fontSize", 6, 24, 1)

    local outlined = W:CreateCheckbox(parentFrame, "Font Outline", {
        checked = cfg.fontOutline == "OUTLINE",
        width = width,
        onChange = function(checked) SetUnit(unitKey, "fontOutline", checked and "OUTLINE" or "") end,
    })
    Place(outlined, ROW)

    Checkbox("Font Shadow", "fontShadow")

    Section("Cast Bar")
    Checkbox("Show Cast Bar", "showCastBar")
    Slider("Cast Bar Height", "castBarHeight", 10, 40, 1)
    Checkbox("Show Spell Icon", "castBarIcon")

    local SOURCE_OPTIONS = {
        { value = "all", label = "Everyone's" },
        { value = "mine", label = "Only mine" },
        { value = "others", label = "Only other people's" },
    }

    Section("Buffs")
    Checkbox("Show Buffs", "showBuffs")
    Slider("Maximum Buffs", "maxBuffs", 1, 16, 1)
    Dropdown("Cast By", "buffSource", SOURCE_OPTIONS, "all")
    Dropdown("Limit To", "buffCategory", {
        { value = "any", label = "Any buff" },
        { value = "cancelable", label = "Cancelable only" },
        { value = "defensive", label = "Major defensives only" },
    }, "any")

    Section("Debuffs")
    Checkbox("Show Debuffs", "showDebuffs")
    Slider("Maximum Debuffs", "maxDebuffs", 1, 16, 1)
    Dropdown("Cast By", "debuffSource", SOURCE_OPTIONS, "all")
    Dropdown("Limit To", "debuffCategory", {
        { value = "any", label = "Any debuff" },
        { value = "dispellable", label = "Dispellable by me only" },
        { value = "crowdcontrol", label = "Crowd control only" },
    }, "any")

    Section("Aura Icons")
    Slider("Icon Size", "auraSize", 10, 40, 1)
    Slider("Icon Spacing", "auraSpacing", 0, 10, 1)

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Global
--
-- The few settings that genuinely cannot differ between frames. Everything that
-- can vary lives on the frame's own tab instead.
--------------------------------------------------------------------------------

function ConfigUI:BuildGlobalPage(parentFrame)
    local indent, width = GetPageOpts(parentFrame)
    local y = -10

    local _, newY = W:CreateSectionHeader(parentFrame, "Position", indent, y)
    y = newY - SECTION_GAP

    local unlock = W:CreateCheckbox(parentFrame, "Unlock Frames", {
        checked = Config.unlocked and true or false,
        width = width,
        description = "Show a drag handle over every enabled frame.",
        onChange = function(checked)
            Config.unlocked = checked
            Config:Save()
            if PUF.Core then PUF.Core:SetUnlocked(checked) end
        end,
    })
    unlock:SetPoint("TOPLEFT", indent, y)
    y = y - ROW_DESC

    local reset = W:CreateButton(parentFrame, "Reset Positions", {
        variant = "secondary",
        width = 140,
        onClick = function()
            if PUF.Core then PUF.Core:ResetPositions() end
        end,
    })
    reset:SetPoint("TOPLEFT", indent, y)
    y = y - BUTTON

    local _, blizzY = W:CreateSectionHeader(parentFrame, "Blizzard Frames", indent, y - SECTION_END)
    y = blizzY - SECTION_GAP

    local hideBlizz = W:CreateCheckbox(parentFrame, "Hide Default Unit Frames", {
        checked = Config.hideBlizzardFrames ~= false,
        width = width,
        description = "Takes effect on the next reload.",
        onChange = function(checked)
            Config.hideBlizzardFrames = checked
            Config:Save()
            if checked and PUF.Blizzard then PUF.Blizzard:Apply() end
        end,
    })
    hideBlizz:SetPoint("TOPLEFT", indent, y)
    y = y - ROW_DESC

    local _, perfY = W:CreateSectionHeader(parentFrame, "Performance", indent, y - SECTION_END)
    y = perfY - SECTION_GAP

    local refresh = W:CreateSlider(parentFrame, "Refresh Interval", {
        min = 0.05, max = 0.5, step = 0.05,
        value = Config.refreshRate or 0.1,
        width = width,
        format = function(v) return string.format("%.2fs", v) end,
        onChange = function(value) Set("refreshRate", value) end,
    })
    refresh:SetPoint("TOPLEFT", indent, y)
    y = y - SLIDER

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Information
--------------------------------------------------------------------------------

function ConfigUI:BuildInfoPage(parentFrame)
    ConfigUIUtils.BuildInfoPage(parentFrame, "Unit Frames", {
        "Four frames and nothing else: you, your target, your target's target, " ..
            "and your focus. Each one has its own tab, and its own size, colours, " ..
            "font, cast bar and aura rows - so no two frames have to look alike.",
        { command = "/puf", desc = "open these settings" },
        { command = "/puf unlock", desc = "toggle the drag handles" },
        { command = "/puf reset", desc = "put every frame back to its default position" },

        { header = "Matching frames up" },
        "Style one frame the way you want it, then use Copy to All Frames at the " ..
            "top of its tab to give the other three the same look. Each frame " ..
            "keeps its own position and its own enabled state, so nothing moves " ..
            "and nothing switches on behind you.",

        { header = "Moving frames" },
        "Unlock the frames on the Global tab to get a drag handle over each one, " ..
            "move them where you want, then lock them again. Positions are stored " ..
            "per character as an offset from the centre of the screen, so they " ..
            "survive a resolution change.",

        { header = "Filtering auras" },
        "Each frame can narrow its buff and debuff rows by who cast the aura and " ..
            "by category - cancelable buffs, major defensives, debuffs you can " ..
            "dispel, crowd control. The filtering is done by the game rather than " ..
            "by this addon, which is the only way it can work: aura data is " ..
            "protected, so an addon cannot look at an aura to decide whether to " ..
            "show it.",

        { header = "Restricted values" },
        "Since Midnight the game hands addons protected values for health, names, " ..
            "auras and casts. The bars and text here are built on the display APIs " ..
            "made for that, so a raid boss reads the same as a party member - the " ..
            "addon shows the numbers without ever being able to inspect them.",
    })
end

-- Push a frame's stored offsets back into its X/Y boxes after a drag. A box the
-- user is actively typing in is left alone.
function ConfigUI:SyncPositionInputs(unitKey)
    local inputs = self.positionInputs[unitKey]
    if not inputs then return end

    local cfg = Config:GetUnit(unitKey)
    for key, input in pairs(inputs) do
        if input.editBox and not input.editBox:HasFocus() then
            pcall(input.SetText, input, tostring(math.floor((cfg[key] or 0) + 0.5)))
        end
    end
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

function ConfigUI:GetPages()
    local pages = {
        { key = "info", label = "Information", builder = function(f) ConfigUI:BuildInfoPage(f) end },
        { key = "global", label = "Global", builder = function(f) ConfigUI:BuildGlobalPage(f) end },
    }

    for _, unitKey in ipairs(Config.UNIT_ORDER) do
        table.insert(pages, {
            key = unitKey,
            label = Config.UNIT_LABELS[unitKey],
            builder = function(f) ConfigUI:BuildUnitPage(f, unitKey) end,
        })
    end

    return pages
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildUnitPage(parentFrame, "player")
    return parentFrame
end

function ConfigUI:InitializeOptions()
    local panel = ConfigUIUtils.CreateSettingsPanel(
        "Settings",
        "Configuration options for the unit frames"
    )
    local content = panel.content
    self:BuildIntoFrame(content)
    panel:UpdateContentHeight(content:GetHeight())
    return panel
end

function ConfigUI:OpenOptions()
    Config:Save()

    if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
        _G.PeaversConfig.MainFrame:Show()
        _G.PeaversConfig.MainFrame:SelectAddon("PeaversUnitFrames")
        return
    end

    if Settings and Settings.OpenToCategory then
        if PUF.directSettingsCategoryID then
            local ok = pcall(Settings.OpenToCategory, PUF.directSettingsCategoryID)
            if ok then return end
        end
        if PUF.directCategoryID then
            local ok = pcall(Settings.OpenToCategory, PUF.directCategoryID)
            if ok then return end
        end
    end

    if SettingsPanel then
        ShowUIPanel(SettingsPanel)
    end
end

Config.OpenOptionsCommand = function()
    ConfigUI:OpenOptions()
end

function ConfigUI:Initialize()
    self.panel = self:InitializeOptions()
end

return ConfigUI
