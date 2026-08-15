-- PeaversUnitFrames Patrons Module
local addonName, addon = ...

local Patrons = {}
addon.Patrons = Patrons

function Patrons:Initialize()
    if not _G.PeaversCommons or not _G.PeaversCommons.PatronsUI then
        return false
    end

    _G.PeaversCommons.PatronsUI:AddToSupportPanel(addon)

    return true
end

function Patrons:GetAll()
    if not _G.PeaversCommons or not _G.PeaversCommons.Patrons then
        return {}
    end

    return _G.PeaversCommons.Patrons:GetAll()
end

return Patrons
