local addonName, PUF = ...

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r " .. addonName .. " requires PeaversCommons to work properly.")
    return
end

local Utils = PeaversCommons.Utils

PUF.name = addonName
PUF.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

PeaversCommons.SlashCommands:Register(addonName, "puf", {
    default = function()
        PUF.ConfigUI:OpenOptions()
    end,
    unlock = function()
        local unlocked = PUF.Core:ToggleUnlocked()
        Utils.Print(PUF, unlocked and "Frames unlocked - drag them into place." or "Frames locked.")
    end,
    lock = function()
        PUF.Config.unlocked = false
        PUF.Config:Save()
        PUF.Core:SetUnlocked(false)
        Utils.Print(PUF, "Frames locked.")
    end,
    reset = function()
        PUF.Core:ResetPositions()
        Utils.Print(PUF, "Frame positions reset.")
    end,
    debug = function(rest)
        local unit = (rest and rest ~= "" and rest) or "target"
        Utils.Print(PUF, "Diagnostics for '" .. unit .. "':")
        for _, line in ipairs(PUF.Style.Diagnose(unit)) do
            print("  " .. line)
        end
    end,
    help = function()
        Utils.Print(PUF, "Commands:")
        print("  /puf - Open settings")
        print("  /puf unlock - Show the drag handles")
        print("  /puf lock - Hide the drag handles")
        print("  /puf reset - Reset every frame position")
        print("  /puf debug [unit] - Report what the client will tell us about a unit")
    end,
})

PeaversCommons.Events:Init(addonName, function()
    PUF.Config:Initialize()

    PUF.Core:Initialize()

    if PUF.ConfigUI and PUF.ConfigUI.Initialize then
        PUF.ConfigUI:Initialize()
    end

    if PUF.Patrons and PUF.Patrons.Initialize then
        PUF.Patrons:Initialize()
    end

    PeaversCommons.Events:RegisterEvent("PLAYER_LOGOUT", function()
        PUF.Config:Save()
    end)

    C_Timer.After(0.5, function()
        PeaversCommons.SettingsUI:CreateRedirectPage(PUF, "PeaversUnitFrames", "Peavers Unit Frames")
    end)

    if PeaversCommons.ConfigRegistry then
        PeaversCommons.ConfigRegistry:Register({
            name = "PeaversUnitFrames",
            displayName = "Unit Frames",
            description = "Player, target, target of target and focus frames",
            addonRef = PUF,
            config = PUF.Config,
            pages = PUF.ConfigUI:GetPages(),
            order = 6,
        })
    end
end, {
    suppressAnnouncement = true
})

_G.PeaversUnitFrames = PUF
