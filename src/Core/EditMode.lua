local addonName, PUF = ...

--------------------------------------------------------------------------------
-- EditMode
--
-- Registers the four unit frames with Blizzard's Edit Mode. The schema, the
-- dialog, the collapsing sections and the styling all live in PeaversCommons;
-- what is left here is the two things only this addon knows.
--
-- The first is what to register. Never the unit button itself: it is a
-- SecureUnitButtonTemplate driven by RegisterUnitWatch, so it is protected and
-- it hides whenever its unit does not exist - and Edit Mode's selection overlay
-- is a child of whatever it is given, so registering the button would mean the
-- target frame's Edit Mode handle disappeared along with the target. Each frame
-- already builds a plain unprotected mover for its drag handle, and that is what
-- goes in.
--
-- The second is the position. Most Peavers addons store an anchor point and an
-- offset, which is exactly what Edit Mode reports, so they save it verbatim.
-- This one stores an offset from the centre of UIParent instead, so Edit Mode's
-- answer is thrown away and the centre offset re-derived from where the mover
-- physically landed. That keeps one position format in the addon, keeps the
-- typed X/Y boxes on the settings page in sync, and means nothing has to be
-- migrated.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons

local EditMode = {}
PUF.EditMode = EditMode

-- Read by UnitFrame and Core, which have to behave differently while Edit Mode
-- owns the movers.
function EditMode:IsEditing()
    return PeaversCommons.EditMode and PeaversCommons.EditMode:IsEditing() or false
end

-- Edit Mode has finished moving a mover. Its anchor point and offset are
-- ignored: CommitMoverPosition reads where the mover physically is and converts
-- that into the centre offset the rest of the addon speaks, which also writes
-- the value back into the settings page's X/Y boxes.
local function SavePosition(mover)
    if mover.pufUnitFrame then
        mover.pufUnitFrame:CommitMoverPosition()
    end
end

function EditMode:Register()
    if not PeaversCommons.EditMode or not PeaversCommons.EditMode.available then
        return false
    end
    -- Absent when PeaversCommons is too old to have built it.
    if not PUF.UnitSettings then return false end
    if self.registered then return true end

    local Config = PUF.Config

    for _, unitKey in ipairs(Config.UNIT_ORDER) do
        local unitFrame = PUF.Core.frames[unitKey]

        if unitFrame and unitFrame.mover then
            unitFrame.mover.pufUnitFrame = unitFrame

            local defaults = Config:GetUnitDefaults(unitKey)

            PeaversCommons.EditMode:Register({
                frame = unitFrame.mover,
                name = "Peavers " .. (Config.UNIT_LABELS[unitKey] or unitKey),
                schema = PUF.UnitSettings,
                context = unitKey,
                default = { point = "CENTER", x = defaults.x or 0, y = defaults.y or 0 },
                onPositionChanged = SavePosition,

                -- All four movers come out, including any whose frame is
                -- switched off: the Enabled checkbox lives in the dialog, and a
                -- frame you cannot select is a frame you cannot turn back on.
                onEnter = function() unitFrame:SetEditModeShown(true) end,
                onExit = function() unitFrame:SetEditModeShown(false) end,

                -- Positions are not keyed by Edit Mode layout, so a layout
                -- change moves nothing. The movers still have to be put back
                -- over their frames, having been free-floating while dragged.
                onLayout = function() unitFrame:SyncMover() end,

                buttons = {
                    {
                        text = "Copy To All Frames",
                        click = function()
                            StaticPopup_Show("PEAVERSUNITFRAMES_COPY_TO_ALL",
                                Config.UNIT_LABELS[unitKey] or unitKey, nil, unitKey)
                        end,
                    },
                },
            })
        end
    end

    self.registered = true
    return true
end

return EditMode
