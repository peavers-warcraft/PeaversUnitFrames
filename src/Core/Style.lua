local addonName, PUF = ...

--------------------------------------------------------------------------------
-- Style
--
-- Colours, fonts, textures, and the Midnight "secret value" guards that every
-- unit read in this addon has to pass through.
--
-- Since 12.0 the client hands addons *secret* numbers for restricted unit data
-- (health, power, names, auras, casts). A secret can be stored, passed along, and
-- handed to a widget setter, but arithmetic, comparison, or using it as a table
-- key is a hard Lua error. So everything here either goes through
-- UnitHealthPercent / UnitPowerPercent (which return plain numbers built for
-- display) or checks IsSecret() before touching the value.
--------------------------------------------------------------------------------

local Style = {}
PUF.Style = Style

local format, floor, abs = string.format, math.floor, math.abs

--------------------------------------------------------------------------------
-- Secret value handling
--------------------------------------------------------------------------------

-- True when the client handed us a restricted value we are not allowed to
-- inspect. issecretvalue only exists from 12.0 onwards.
function Style.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

local IsSecret = Style.IsSecret

-- A restricted aura or update payload arrives as a secret *table*, which cannot
-- be indexed at all - not even to read one field.
function Style.IsSecretTable(value)
    return type(issecrettable) == "function" and issecrettable(value) or false
end

-- Run a game API that may be restricted (or missing on an older build) without
-- letting the error escape into an OnUpdate handler and spam the user.
-- Ten results rather than a packed table: UnitCastingInfo alone returns nine, and
-- this sits on the per-tick path where allocating would show up.
function Style.Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j end
    return nil
end

local Safe = Style.Safe

-- Booleans are the sharp edge of the secret system. A secret string or number can
-- at least be truth-tested (nil is false, anything else is true), but a secret
-- *boolean* cannot be tested or compared at all - that is what takes down other
-- unit frame addons on the UNIT_AURA payload. So every boolean the client hands
-- us is funnelled through here and comes back as a plain true/false, or nil
-- meaning "not allowed to know".
--
-- Order matters: issecretvalue is safe to call on anything, so it is always asked
-- first, before any comparison against nil.
function Style.ReadBool(value)
    if IsSecret(value) then return nil end
    if value == nil then return nil end
    return value and true or false
end

local ReadBool = Style.ReadBool

-- ReadBool over an API call that might itself be missing or throw.
function Style.SafeBool(fn, ...)
    return ReadBool(Safe(fn, ...))
end

local SafeBool = Style.SafeBool

-- Truth-test a value that may be secret but is known not to be a boolean
-- (a name, an icon, a spell id). Testing those is permitted; comparing them is
-- not, so this exists to keep `~= nil` out of the call sites.
function Style.Present(value)
    if IsSecret(value) then return true end
    return value ~= nil
end

local Present = Style.Present

-- UnitExists is not on the documented restricted list, but it is boolean and it
-- gates every update in the addon, so it goes through the same funnel. An
-- unreadable answer is treated as "exists": the frame's visibility is driven by
-- RegisterUnitWatch on the client side anyway, and every read below it is
-- individually guarded.
function Style.Exists(unit)
    local exists = ReadBool(Safe(UnitExists, unit))
    if exists == nil then return true end
    return exists
end

--------------------------------------------------------------------------------
-- Capability probes
--
-- The 12.x display APIs are the only legal way to show restricted data, but the
-- addon still has to load on the older interface versions in the TOC. Probing
-- once at load keeps the hot paths free of pcall.
--------------------------------------------------------------------------------

Style.Caps = {}

do
    local probe = CreateFrame("StatusBar")

    -- 12.0 added an interpolation argument to SetValue, which is what gives the
    -- bars their smooth travel without an addon-side animation loop.
    probe:SetMinMaxValues(0, 100)
    Style.Caps.barInterpolation = pcall(probe.SetValue, probe, 0, 1)

    -- Cast bars for restricted units can only be driven by a DurationObject.
    Style.Caps.timerDuration = (type(probe.SetTimerDuration) == "function")
        and (type(C_DurationUtil) == "table")
        and (type(C_DurationUtil.CreateDuration) == "function")

    probe:Hide()
    probe:SetParent(nil)

    Style.Caps.healthPercent = (type(UnitHealthPercent) == "function")
    Style.Caps.powerPercent = (type(UnitPowerPercent) == "function")
end

--------------------------------------------------------------------------------
-- AuraContainer support
--
-- The container only carries AddAuraGroup when it is created from this template;
-- a bare CreateFrame("AuraContainer") produces something without the methods,
-- which fails quietly and drops the addon onto the scan fallback.
--
-- The probe is lazy, and a failure in combat is deliberately not cached:
-- creating a live container in lockdown raises the client's own error dialog,
-- which pcall does not catch, so a probe that happens to land mid-combat must
-- not permanently disable auras for the session.
--------------------------------------------------------------------------------

Style.AURA_CONTAINER_TEMPLATE = "CustomAuraContainerTemplate"

local auraContainerSupported

function Style.SupportsAuraContainer()
    if auraContainerSupported ~= nil then return auraContainerSupported end
    if InCombatLockdown() then return false end

    local build = select(4, GetBuildInfo())
    if type(build) ~= "number" or build < 120100 then
        auraContainerSupported = false
        return false
    end

    local ok, container = pcall(CreateFrame, "AuraContainer", nil, UIParent,
        Style.AURA_CONTAINER_TEMPLATE)
    if not ok or not container then
        auraContainerSupported = false
        return false
    end

    auraContainerSupported = (type(container.AddAuraGroup) == "function")
    pcall(container.Hide, container)

    return auraContainerSupported
end

-- Reject a filter string the client would not accept, rather than letting
-- AddAuraGroup fail and silently empty the row.
function Style.IsValidFilter(filter)
    if AuraUtil and AuraUtil.IsValidFilterString then
        local ok, valid = pcall(AuraUtil.IsValidFilterString, filter)
        if ok then return valid and true or false end
    end
    return true
end

local INTERPOLATE = Enum and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut

-- Set a bar's value, smoothing it natively where the build allows.
--
-- The value is very often secret, and that is not a problem worth guarding
-- against: SetValue is one of the setters built to accept secrets. Only nil is
-- filtered out, and IsSecret is asked first because comparing a secret to nil
-- would itself be illegal.
function Style.SetBarValue(bar, value)
    if not IsSecret(value) and value == nil then return end

    if INTERPOLATE and Style.Caps.barInterpolation then
        bar:SetValue(value, INTERPOLATE)
    else
        bar:SetValue(value)
    end
end

--------------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------------

Style.Colors = {
    -- Neutral fill for anything whose class or reaction we are not allowed to read.
    unknown = { r = 0.42, g = 0.44, b = 0.50 },
    dead = { r = 0.32, g = 0.32, b = 0.34 },
    offline = { r = 0.38, g = 0.38, b = 0.42 },
    cast = { r = 0.29, g = 0.56, b = 0.89 },
    castUninterruptible = { r = 0.55, g = 0.55, b = 0.60 },
    castChannel = { r = 0.36, g = 0.68, b = 0.62 },
    castFailed = { r = 0.78, g = 0.28, b = 0.28 },
    border = { r = 0, g = 0, b = 0 },
    text = { r = 0.94, g = 0.94, b = 0.96 },
    textMuted = { r = 0.68, g = 0.68, b = 0.74 },
}

-- Debuff border tints, keyed by the dispel type the client reports.
Style.DebuffColors = {
    Magic = { r = 0.20, g = 0.60, b = 1.00 },
    Curse = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison = { r = 0.00, g = 0.60, b = 0.00 },
    Bleed = { r = 0.80, g = 0.10, b = 0.10 },
    none = { r = 0.70, g = 0.15, b = 0.15 },
}

local FLAT = "Interface\\Buttons\\WHITE8x8"

Style.BACKDROP = {
    bgFile = FLAT,
    edgeFile = FLAT,
    tile = true,
    edgeSize = 1,
}

-- Every frame in the addon gets the same treatment: a solid dark fill behind the
-- bars and a single black hairline, which is what gives the flat modern look.
function Style.ApplyBackdrop(frame, bgAlpha)
    frame:SetBackdrop(Style.BACKDROP)
    frame:SetBackdropColor(0, 0, 0, bgAlpha or 0.85)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
end

-- Every appearance getter takes the owning frame's own config table: nothing here
-- is addon-wide any more, so each frame can be styled on its own.

function Style.GetDefaultFont()
    local ConfigManager = _G.PeaversCommons and _G.PeaversCommons.ConfigManager
    if ConfigManager and ConfigManager.GetDefaultFont then
        return ConfigManager.GetDefaultFont()
    end
    return "Fonts\\FRIZQT__.TTF"
end

function Style.GetFont(cfg)
    cfg = cfg or {}
    -- Unset means "whatever suits this locale", resolved here rather than baked
    -- into the saved profile.
    local face = cfg.fontFace or Style.GetDefaultFont()
    local size = cfg.fontSize or 11
    local outline = cfg.fontOutline
    if outline == true then outline = "OUTLINE" end
    if outline == false then outline = "" end
    return face, size, outline or "OUTLINE"
end

function Style.ApplyFont(fontString, cfg, sizeDelta)
    local face, size, outline = Style.GetFont(cfg)
    fontString:SetFont(face, size + (sizeDelta or 0), outline)
    if cfg and cfg.fontShadow then
        fontString:SetShadowOffset(1, -1)
        fontString:SetShadowColor(0, 0, 0, 1)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

function Style.GetTexture(cfg)
    return (cfg and cfg.barTexture) or "Interface\\TargetingFrame\\UI-StatusBar"
end

--------------------------------------------------------------------------------
-- Unit colours
--------------------------------------------------------------------------------

local FALLBACK_POWER = { r = 0.20, g = 0.40, b = 0.90 }

-- Health bar colour. Class colour for players, faction colour for NPCs, and a
-- neutral grey whenever the client will not tell us which (unit identity is
-- secret in combat for anything that is not the player or their pet).
function Style.GetUnitColor(unit, cfg)
    cfg = cfg or {}

    if cfg.healthColorMode == "custom" then
        return cfg.healthColor or Style.Colors.unknown
    end

    if not Style.Exists(unit) then
        return Style.Colors.unknown
    end

    if SafeBool(UnitIsConnected, unit) == false then
        return Style.Colors.offline
    end

    if SafeBool(UnitIsDeadOrGhost, unit) then
        return Style.Colors.dead
    end

    if SafeBool(UnitIsPlayer, unit) then
        local class = Safe(function() return select(2, UnitClass(unit)) end)
        -- The class token has to be readable before it can be used as a key.
        if not IsSecret(class) and class then
            local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class])
                or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
            if color then return color end
        end
        return Style.Colors.unknown
    end

    local reaction = Safe(UnitReaction, unit, "player")
    if not IsSecret(reaction) and reaction and FACTION_BAR_COLORS then
        local color = FACTION_BAR_COLORS[reaction]
        if color then return color end
    end

    return Style.Colors.unknown
end

function Style.GetPowerColor(unit)
    local powerType, powerToken = Safe(UnitPowerType, unit)
    if not PowerBarColor then return FALLBACK_POWER end

    if not IsSecret(powerToken) and powerToken then
        local color = PowerBarColor[powerToken]
        if color then return color end
    end
    if not IsSecret(powerType) and powerType then
        local color = PowerBarColor[powerType]
        if color then return color end
    end

    return PowerBarColor["MANA"] or FALLBACK_POWER
end

--------------------------------------------------------------------------------
-- Unit values
--
-- The key insight, and the one this addon originally got backwards: a restricted
-- health value is never meant to become readable. UnitHealthPercent hands back a
-- secret even when given the ScaleTo100 curve, and that is fine - the client
-- supplies formatters and widget setters that accept secrets directly, so the
-- number reaches the screen without this addon ever inspecting it.
--
-- So nothing below rejects a value for being secret. It is passed straight to
-- StatusBar:SetValue, AbbreviateNumbers, or RoundToNearestString, each of which
-- is permitted to do what we are not.
--------------------------------------------------------------------------------

-- ScaleTo100 makes the percent APIs report 0-100 rather than 0-1. Falling back
-- to `true` is deliberate: the curve argument also accepts it as "use the
-- default curve" on builds without CurveConstants.
local ScaleTo100 = (CurveConstants and CurveConstants.ScaleTo100) or true

-- Formatters that accept secrets. AbbreviateNumbers turns 287431 into "287k"
-- without a single comparison on our side; RoundToNearestString does the same
-- for a percentage.
local AbbreviateNumbers = _G.AbbreviateNumbers or _G.AbbreviateLargeNumbers
local RoundToNearestString = C_StringUtil and C_StringUtil.RoundToNearestString

-- A 0-100 health percentage. Frequently secret - display only, never compared.
function Style.GetHealthPercent(unit)
    if Style.Caps.healthPercent then
        return Safe(UnitHealthPercent, unit, true, ScaleTo100)
    end

    local cur, max = Safe(UnitHealth, unit), Safe(UnitHealthMax, unit)
    if IsSecret(cur) or IsSecret(max) then return nil end
    if cur == nil or max == nil or max == 0 then return nil end
    return (cur / max) * 100
end

-- Power takes the curve in a different argument slot to health.
function Style.GetPowerPercent(unit)
    if Style.Caps.powerPercent then
        return Safe(UnitPowerPercent, unit, nil, false, ScaleTo100)
    end

    local cur, max = Safe(UnitPower, unit), Safe(UnitPowerMax, unit)
    if IsSecret(cur) or IsSecret(max) then return nil end
    if cur == nil or max == nil or max == 0 then return nil end
    return (cur / max) * 100
end

--------------------------------------------------------------------------------
-- Driving bars
--
-- Both percent APIs are on a 0-100 scale thanks to the curve, so the bar range
-- is fixed and only the value changes.
--------------------------------------------------------------------------------

function Style.ApplyHealthToBar(bar, unit)
    bar:SetMinMaxValues(0, 100)
    Style.SetBarValue(bar, Style.GetHealthPercent(unit))
end

function Style.ApplyPowerToBar(bar, unit)
    bar:SetMinMaxValues(0, 100)
    Style.SetBarValue(bar, Style.GetPowerPercent(unit))
end

--------------------------------------------------------------------------------
-- Secret-safe text
--------------------------------------------------------------------------------

-- IsSecret is always asked first: the nil comparison that follows would itself
-- be illegal on a secret.
local function PercentText(pct)
    if IsSecret(pct) then
        if RoundToNearestString then return RoundToNearestString(pct, 1) .. "%" end
        return nil
    end
    if pct == nil then return nil end
    return format("%d%%", floor(pct + 0.5))
end

local function ValueText(value)
    if IsSecret(value) then
        if AbbreviateNumbers then return AbbreviateNumbers(value) end
        -- No abbreviator: string.format still accepts the secret, so the raw
        -- number is shown rather than nothing.
        return format("%s", value)
    end
    if value == nil then return nil end
    if AbbreviateNumbers then return AbbreviateNumbers(value) end
    return Style.Abbreviate(value)
end

Style.PercentText = PercentText
Style.ValueText = ValueText


--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

function Style.Abbreviate(value)
    if IsSecret(value) or value == nil then return nil end
    local magnitude = abs(value)
    if magnitude >= 1e9 then return format("%.1fB", value / 1e9) end
    if magnitude >= 1e6 then return format("%.1fM", value / 1e6) end
    if magnitude >= 1e4 then return format("%.0fk", value / 1e3) end
    if magnitude >= 1e3 then return format("%.1fk", value / 1e3) end
    return tostring(floor(value + 0.5))
end

-- Health readout for a unit, honouring the configured mode and degrading to a
-- percentage whenever the absolute numbers are restricted.
function Style.BuildHealthText(unit, mode)
    if mode == "none" then return "" end

    if SafeBool(UnitIsConnected, unit) == false then return "Offline" end
    if SafeBool(UnitIsDeadOrGhost, unit) then return "Dead" end

    -- Both halves are built by formatters that accept secrets, so an enemy reads
    -- exactly like a party member; concatenating two secret strings is allowed.
    local pctText = PercentText(Style.GetHealthPercent(unit))
    local curText = ValueText(Safe(UnitHealth, unit))

    if mode == "percent" and pctText then return pctText end
    if mode == "value" and curText then return curText end
    if mode == "both" and curText and pctText then return curText .. "  " .. pctText end

    return pctText or curText or ""
end

-- Unit name. In combat the name of anything that is not the player or their pet
-- comes back secret; FontString:SetText accepts secrets, so the caller can still
-- display it, we just must not measure or truncate it here.
function Style.GetUnitName(unit)
    local name = Safe(UnitName, unit)
    -- Truth-testing a secret string is permitted; comparing it is not.
    if not Present(name) then return "" end
    return name
end

--------------------------------------------------------------------------------
-- Diagnostics
--
-- Reports what the client is willing to tell us about a unit. Deliberately never
-- prints a value that might be secret - only whether it is present and whether it
-- is readable - since tostring on a secret is not a permitted operation.
--------------------------------------------------------------------------------

function Style.Diagnose(unit)
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = format(fmt, ...) end

    add("caps: healthPercent=%s powerPercent=%s scaleTo100=%s interp=%s timerDuration=%s auraContainer=%s",
        tostring(Style.Caps.healthPercent), tostring(Style.Caps.powerPercent),
        tostring(ScaleTo100 ~= nil), tostring(Style.Caps.barInterpolation),
        tostring(Style.Caps.timerDuration), tostring(Style.SupportsAuraContainer()))

    add("unit '%s': exists=%s", unit, tostring(Style.Exists(unit)))

    -- Secret is the expected answer here, not a failure: what matters is that the
    -- value is present and that the formatters produced something.
    local pct = Style.GetHealthPercent(unit)
    add("  health percent: present=%s secret=%s", tostring(Present(pct)), tostring(IsSecret(pct)))

    local cur = Safe(UnitHealth, unit)
    add("  UnitHealth: present=%s secret=%s", tostring(Present(cur)), tostring(IsSecret(cur)))

    add("  formatters: abbreviate=%s roundToNearest=%s scaleTo100=%s",
        tostring(AbbreviateNumbers ~= nil), tostring(RoundToNearestString ~= nil),
        tostring(ScaleTo100 ~= true))

    -- Never interpolate the text itself: it may now be a secret string, and while
    -- SetText would accept it, print would not.
    local ok, text = pcall(Style.BuildHealthText, unit, PUF.Config:GetUnit(unit).healthText)
    if not ok then
        add("  health text: errored")
    elseif IsSecret(text) then
        add("  health text: <secret string, displayed but not readable>")
    else
        add("  health text: '%s'", text)
    end

    local frame = PUF.Core and PUF.Core.frames and PUF.Core.frames[unit]
    if frame then
        local minValue, maxValue = frame.health:GetMinMaxValues()
        local value = frame.health:GetValue()
        add("  bar: min=%s max=%s value=%s",
            IsSecret(minValue) and "<secret>" or tostring(minValue),
            IsSecret(maxValue) and "<secret>" or tostring(maxValue),
            IsSecret(value) and "<secret>" or tostring(value))

        -- Where our own cast bar actually is. If this reports it anchored to the
        -- unit button, any stray bar on screen belongs to something else.
        local castBar = frame.castBar
        if castBar and castBar.frame then
            local point, relativeTo, relativePoint, xOfs, yOfs = castBar.frame:GetPoint(1)
            local relName = relativeTo and (relativeTo.GetName and relativeTo:GetName()) or "?"
            add("  castbar: enabled=%s shown=%s anchor=%s -> %s.%s (%s, %s)",
                tostring(castBar.enabled and true or false),
                tostring(castBar.frame:IsShown()),
                tostring(point), tostring(relName), tostring(relativePoint),
                tostring(xOfs), tostring(yOfs))
        end

        -- An unrecognised filter token makes AddAuraGroup fail, which shows up
        -- as an empty row with nothing else to explain it.
        for label, row in pairs({ buffs = frame.buffs, debuffs = frame.debuffs }) do
            if row then
                add("  %s: filter='%s' enabled=%s path=%s max=%s",
                    label, tostring(row.filter), tostring(row.enabled and true or false),
                    row.usingContainer and "container" or "scan",
                    tostring(row.count))
            end
        end
    end

    if PUF.Core then
        add("refresh: count=%s deferredForCombat=%s inCombat=%s",
            tostring(PUF.Core.refreshCount or 0),
            tostring(PUF.Core.deferredForCombat and true or false),
            tostring(InCombatLockdown()))
        if PUF.Core.lastSetting then
            add("last setting: '%s' changed %.1fs ago",
                PUF.Core.lastSetting, GetTime() - (PUF.Core.lastSettingTime or 0))
        else
            add("last setting: none seen this session")
        end
        add("last layout error: %s", PUF.Core.lastError or "none")
    end

    if PUF.Blizzard and PUF.Blizzard.status then
        local parts = {}
        for name, state in pairs(PUF.Blizzard.status) do
            parts[#parts + 1] = name .. "=" .. state
        end
        table.sort(parts)
        add("blizzard frames: %s", #parts > 0 and table.concat(parts, " ") or "not applied")
    end

    return lines
end

return Style
