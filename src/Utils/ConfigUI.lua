local _, PUF = ...
local Config = PUF.Config

local ConfigUI = {}
PUF.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local W = PeaversCommons.Widgets
local ConfigUIUtils = PeaversCommons.ConfigUIUtils

--------------------------------------------------------------------------------
-- Where the settings went
--
-- Every setting these frames have is now in Blizzard's Edit Mode: select a
-- frame and the dialog holds whether it is on and how big, with a button per
-- group for everything else.
--
-- This page is deliberately not a second copy of them. Two places to change one
-- setting is worse than one place that takes a moment to find, and a mirror of
-- thirty settings would have to be kept honest forever.
--------------------------------------------------------------------------------

local BODY = "Select any of the four frames and its settings open beside the "
    .. "Edit Mode dialog: size, bars, text, cast bar, auras and typed position "
    .. "offsets, plus the settings shared by all four frames."

local HOW = "Open Edit Mode from the game menu, or press Escape and choose "
    .. "Edit Mode. Frames can be dragged, nudged a pixel at a time with the "
    .. "arrow keys, or ten at a time with Shift held."

function ConfigUI:BuildInfoPage(parentFrame)
    local indent = 25
    local width = parentFrame:GetWidth()
    width = (width and width > 100) and (width - (indent * 2) - 10) or 360

    local y = -10

    local function Paragraph(text, font, color)
        local label = W:CreateLabel(parentFrame, text, {
            font = font,
            color = color,
        })
        label:SetPoint("TOPLEFT", indent, y)
        label:SetWidth(width)
        label:SetJustifyH("LEFT")
        y = y - (label:GetStringHeight() or 16) - 14
        return label
    end

    local _, newY = W:CreateSectionHeader(parentFrame, "Settings are in Edit Mode", indent, y)
    y = newY - 10

    Paragraph(BODY)
    Paragraph(HOW, "GameFontNormalSmall", W.Colors.textMuted)

    y = y - 6

    local reset = W:CreateButton(parentFrame, "Reset Every Frame Position", {
        variant = "secondary",
        width = 220,
        onClick = function()
            PUF.Core:ResetPositions()
            PeaversCommons.Utils.Print(PUF, "Frame positions reset.")
        end,
    })
    reset:SetPoint("TOPLEFT", indent, y)
    y = y - 34

    Paragraph("Everything else - including each frame's own position - is in "
        .. "the Edit Mode panel.", "GameFontNormalSmall", W.Colors.textMuted)

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Copy to all frames
--
-- Lives here because the Edit Mode button that triggers it needs the dialog,
-- and because it overwrites three frames and cannot be undone, so it asks.
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
-- Pages
--------------------------------------------------------------------------------

function ConfigUI:GetPages()
    return {
        { key = "info", label = "Information", builder = function(f) ConfigUI:BuildInfoPage(f) end },
    }
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildInfoPage(parentFrame)
    return parentFrame
end

function ConfigUI:InitializeOptions()
    local panel = ConfigUIUtils.CreateSettingsPanel(
        "Settings",
        "The unit frames are configured in Blizzard's Edit Mode"
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
