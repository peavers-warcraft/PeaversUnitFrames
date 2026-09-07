local _, PUF = ...
local Config = PUF.Config

local ConfigUI = {}
PUF.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local ConfigUIUtils = PeaversCommons.ConfigUIUtils

--------------------------------------------------------------------------------
-- Where the settings went
--
-- Every setting these frames have is in Blizzard's Edit Mode. This page is
-- deliberately not a second copy of them: two places to change one setting is
-- worse than one place that takes a moment to find.
--
-- The wording is PeaversCommons', not this addon's, so that every addon in the
-- collection says it the same way.
--------------------------------------------------------------------------------

function ConfigUI:BuildInfoPage(parentFrame)
    ConfigUIUtils.BuildInfoPageWithEditMode(parentFrame, "Unit Frames", {
        "Clean player, target, target of target and focus frames, with cast "
            .. "bars and aura rows on each.",
        { command = "/puf", desc = "open this page" },
        { command = "/puf reset", desc = "put every frame back where it started" },

        { header = "Nudging a frame" },
        "A selected frame can be dragged, nudged a pixel at a time with the "
            .. "arrow keys, or ten at a time with Shift held. The Position "
            .. "group also takes typed offsets, for lining two frames up "
            .. "exactly.",
    }, {
        title = "the unit frames",
        select = "any of the four frames",
        reset = function()
            Config:Reset()
            if PUF.Core then PUF.Core:RefreshAll() end
            if PeaversCommons.EditModePanel then
                PeaversCommons.EditModePanel:Refresh()
            end
        end,
    })
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
