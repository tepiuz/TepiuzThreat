-- WoW Forever. Only this addon's own FontStrings are changed.
local ADDON_NAME = ...

local driver = CreateFrame("Frame")
local active, labels = {}, {}
local targetLabel
local failures, lastFailure = 0, "none"
local elapsedSinceUpdate = 0
local auraLayoutPending = false
local ready = false
local combatStateRestricted = false

-- All on by default. Missing keys stay on if the settings panel cannot be registered.
local OPTIONS = {
    { key = "onlyInCombat", name = "Only show in combat", tooltip = "Hide the percentage until you enter combat." },
    { key = "showOnNameplates", name = "Show on nameplates", tooltip = "Show the percentage on attackable nameplates." },
    { key = "showOnTarget", name = "Show on target frame", tooltip = "Show the percentage on the target frame." },
}

local function AddonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(getMetadata) ~= "function" then
        return "unknown"
    end
    return getMetadata(ADDON_NAME, "Version") or "unknown"
end

local function Failure(operation)
    failures = failures + 1
    -- Static text only. Never store restricted values or error objects.
    lastFailure = operation
end

local function Clear(label)
    if label then
        label.text:Hide()
        label.text:SetText("")
        label.state = "hidden"
    end
end

local function StyleLabel(text)
    text:SetWordWrap(false)
    -- THICKOUTLINE is Blizzard's heavy stroke. A shadow offset only shifts a thin copy.
    local font, size = text:GetFont()
    if type(font) == "string" and type(size) == "number" and not issecretvalue(font) and not issecretvalue(size) then
        text:SetFont(font, size, "THICKOUTLINE")
    end
    text:Hide()
end

local function NewLabel(parent, anchor, y)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", anchor, "RIGHT", 8, y or 0)
    text:SetJustifyH("LEFT")
    StyleLabel(text)
    return { text = text, state = "hidden", anchor = anchor }
end

local function PubliclyVisible(frame)
    if not frame or frame:IsForbidden() then return false end
    local visible = frame:IsVisible()
    return not issecretvalue(visible) and visible
end

local function EffectAnchor(parent)
    local auras = parent.AurasFrame
    if not PubliclyVisible(auras) then return end

    -- NPC crowd-control icons share a list whose width follows all displayed icons.
    -- The list itself can stay shown when empty; check the displayed children.
    local list = auras.CrowdControlListFrame
    if PubliclyVisible(list) then
        for _, icon in ipairs({ list:GetChildren() }) do
            if PubliclyVisible(icon) then return list end
        end
    end

    -- Enemy players use a separate single-icon loss-of-control display.
    local control = auras.LossOfControlFrame
    if PubliclyVisible(control) and PubliclyVisible(control.AuraItemFrame) then
        return control
    end
end

local function PositionPlateLabel(label, parent, defaultAnchor)
    -- Keep layout failures separate from threat rendering. Do not read aura data
    -- or the size of our text, which can contain a restricted threat number.
    local ok, effectAnchor = pcall(EffectAnchor, parent)
    if not ok then Failure("effect layout lookup rejected") end
    local anchor = ok and effectAnchor or defaultAnchor
    if label.anchor ~= anchor then
        label.text:ClearAllPoints()
        label.text:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        label.anchor = anchor
    end
end

local function TargetPortrait()
    local frame = TargetFrame
    if not frame or frame:IsForbidden() then return end
    -- Classic target layout: the round portrait sits on the right of the frame.
    local portrait = frame.portrait or frame.Portrait or TargetFramePortrait
    if portrait and not portrait:IsForbidden() then
        return portrait
    end
end

local function NewTargetLabel(portrait)
    local text = TargetFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    -- Pixels above the portrait. Increase this to move the percentage up.
    local gapAbovePortrait = 8
    text:SetPoint("BOTTOM", portrait, "TOP", 0, gapAbovePortrait)
    text:SetJustifyH("CENTER")
    StyleLabel(text)
    return { text = text, state = "hidden" }
end

local function Render(label, unit)
    local exists = UnitExists(unit)
    local hostile = UnitCanAttack("player", unit)
    -- These booleans are public in the current Forever build. Hide the label if a later build restricts them.
    if issecretvalue(exists) or issecretvalue(hostile) then
        Clear(label)
        Failure("unit eligibility restricted")
        return
    end
    if not exists or not hostile then
        Clear(label)
        return
    end

    local _, _, percentage = UnitDetailedThreatSituation("player", unit)
    local secret = issecretvalue(percentage)
    -- Missing data is nil. Do not treat that as zero.
    -- Do not compare or inspect a secret percentage. Pass it straight to the widget.
    if not secret and percentage == nil then
        Clear(label)
        return
    end
    if not secret and type(percentage) ~= "number" then
        Clear(label)
        Failure("unexpected threat return type")
        return
    end

    -- SetFormattedText accepts a secret number in this build.
    -- Do not read the resulting text, width, or other derived properties.
    label.text:SetFormattedText("%.0f%%", percentage)
    label.text:Show()
    label.state = secret and "shown (restricted)" or "shown"
end

local function SafeRender(label, unit)
    if not pcall(Render, label, unit) then
        Clear(label)
        Failure("threat query or text display rejected")
    end
end

local function RemovePlate(unit)
    local entry = active[unit]
    if entry and entry.label then
        Clear(entry.label)
    end
    active[unit] = nil
end

local function RefreshPlate(unit, entry, layoutOnly)
    entry.auraLayoutPending = nil
    -- Skip forbidden nameplates.
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local parent = plate and not plate:IsForbidden() and plate.UnitFrame
    -- The level badge sits outside the health bar. Anchor past it.
    local anchor = parent and (parent.PlayerLevelDiffFrame or parent.HealthBarsContainer)
    if not anchor or parent:IsForbidden() then
        Clear(entry.label)
        entry.label = nil
        -- The UnitFrame may not exist yet. The next refresh will retry.
        return
    end

    -- Nameplate UnitFrames are pooled separately from the plate.
    -- Keep our cache off Blizzard objects and resolve the parent on each update.
    local label = labels[parent]
    if not label then
        label = NewLabel(parent, anchor)
        labels[parent] = label
    end
    if entry.label ~= label then
        Clear(entry.label)
        entry.label = label
    end
    PositionPlateLabel(label, parent, anchor)
    if not layoutOnly then SafeRender(label, unit) end
end

local function SafeRefreshPlate(unit, entry, layoutOnly)
    if not pcall(RefreshPlate, unit, entry, layoutOnly) then
        Clear(entry.label)
        Failure("nameplate attachment rejected")
    end
end

local function Enabled(key)
    local db = TepiuzThreatDB
    local value = type(db) == "table" and db[key]
    if value == nil then return true end
    return not not value
end

local function InCombat()
    local ok, locked = pcall(InCombatLockdown)
    -- Fail open. A restricted combat flag should not hide the labels permanently.
    if not ok or issecretvalue(locked) then
        if not combatStateRestricted then
            combatStateRestricted = true
            Failure("combat state restricted")
        end
        return true
    end
    return not not locked
end

local function RefreshAll()
    if not ready then return end
    local show = not Enabled("onlyInCombat") or InCombat()

    if show and Enabled("showOnTarget") then
        if not targetLabel then
            local portrait = TargetPortrait()
            if portrait then
                local ok, label = pcall(NewTargetLabel, portrait)
                if ok then targetLabel = label else Failure("target label creation rejected") end
            end
        end
        if targetLabel then SafeRender(targetLabel, "target") end
    else
        Clear(targetLabel)
    end

    if not show or not Enabled("showOnNameplates") then
        for _, entry in pairs(active) do Clear(entry.label) end
        return
    end
    for unit, entry in pairs(active) do
        SafeRefreshPlate(unit, entry)
    end
end

local function RegisterSettings()
    TepiuzThreatDB = TepiuzThreatDB or {}
    for _, option in ipairs(OPTIONS) do
        if TepiuzThreatDB[option.key] == nil then
            TepiuzThreatDB[option.key] = true
        end
    end

    local settings = Settings
    local createCheckbox = settings and (settings.CreateCheckbox or settings.CreateCheckBox)
    if type(settings) ~= "table"
        or type(settings.RegisterVerticalLayoutCategory) ~= "function"
        or type(settings.RegisterAddOnSetting) ~= "function"
        or type(createCheckbox) ~= "function"
        or type(settings.RegisterAddOnCategory) ~= "function"
    then
        Failure("settings API missing")
        return
    end

    -- Saved variables are applied before ADDON_LOADED. Registering earlier would
    -- bind the controls to a table the client then replaces.
    local ok = pcall(function()
        local category = settings.RegisterVerticalLayoutCategory("Tepiuz Threat")
        for _, option in ipairs(OPTIONS) do
            local setting = settings.RegisterAddOnSetting(
                category, "TepiuzThreat_" .. option.key, option.key, TepiuzThreatDB, type(true), option.name, true)
            createCheckbox(category, setting, option.tooltip)
            setting:SetValueChangedCallback(RefreshAll)
        end
        settings.RegisterAddOnCategory(category)
    end)
    if not ok then Failure("settings registration rejected") end
end

local function DiscoverPlates()
    -- Covers a reload with plates already on screen, and entering a new zone.
    for unit in pairs(active) do RemovePlate(unit) end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok then Failure("nameplate enumeration rejected"); return end
    for _, plate in ipairs(plates) do
        if not plate:IsForbidden() and plate.GetUnit then
            local unit = plate:GetUnit()
            if not issecretvalue(unit) and type(unit) == "string" then
                active[unit] = {}
            end
        end
    end
end

local function Initialize()
    ready = type(UnitDetailedThreatSituation) == "function"
        and type(issecretvalue) == "function"
        and type(UnitExists) == "function" and type(UnitCanAttack) == "function"
        and C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function"
        and type(C_NamePlate.GetNamePlates) == "function"
    if not ready then
        Clear(targetLabel)
        for token in pairs(active) do RemovePlate(token) end
        Failure("required Forever API missing")
        return
    end
    DiscoverPlates()
    RefreshAll()
end

driver:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit == ADDON_NAME then RegisterSettings() end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Initialize()
    elseif event == "PLAYER_LEAVING_WORLD" then
        ready = false
        Clear(targetLabel)
        for token in pairs(active) do RemovePlate(token) end
    elseif not ready then
        return
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if not issecretvalue(unit) and type(unit) == "string" then
            RemovePlate(unit)
            active[unit] = {}
            RefreshAll()
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if not issecretvalue(unit) and type(unit) == "string" then RemovePlate(unit) end
    elseif event == "UNIT_AURA" then
        if not issecretvalue(unit) and type(unit) == "string" then
            local entry = active[unit]
            if entry then
                entry.auraLayoutPending = true
                auraLayoutPending = true
            end
        end
    else
        -- Threat events may name the player, the target, or a mob. Do not compare those payloads.
        RefreshAll()
    end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_FACTION", "UNIT_FLAGS", "UNIT_AURA",
}) do
    if not pcall(driver.RegisterEvent, driver, event) then Failure("event unavailable: " .. event) end
end

-- Covers missed events and nameplates whose frames appear a moment later.
driver:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate >= 0.2 then
        elapsedSinceUpdate = 0
        auraLayoutPending = false
        RefreshAll()
    elseif ready and auraLayoutPending then
        -- UNIT_AURA handlers can run before Blizzard updates the icons. Wait until
        -- OnUpdate, then reposition affected visible labels without querying threat.
        auraLayoutPending = false
        for unit, entry in pairs(active) do
            if entry.auraLayoutPending then
                entry.auraLayoutPending = nil
                if entry.label and entry.label.state ~= "hidden" then
                    SafeRefreshPlate(unit, entry, true)
                end
            end
        end
    end
end)

SLASH_TEPIUZTHREAT1 = "/tthreat"
SLASH_TEPIUZTHREAT2 = "/tepiuzthreat"
SlashCmdList.TEPIUZTHREAT = function()
    local version, build, _, interface = GetBuildInfo()
    local count = 0
    for _ in pairs(active) do count = count + 1 end
    print("Tepiuz Threat", AddonVersion())
    print("Client:", version, build, "interface:", interface)
    print("Ready:", not not ready, "| nameplates:", count,
        "| target:", targetLabel and targetLabel.state or "not attached")
    print("Options:", "combat only:", Enabled("onlyInCombat") and "on" or "off",
        "| nameplates:", Enabled("showOnNameplates") and "on" or "off",
        "| target:", Enabled("showOnTarget") and "on" or "off")
    print("Failures:", failures, "| last:", lastFailure)
end
