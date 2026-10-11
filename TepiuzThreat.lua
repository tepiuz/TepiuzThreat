-- WoW Forever. Only this addon's own frames and FontStrings are changed.
local ADDON_NAME = ...

local driver = CreateFrame("Frame")
local active, labels = {}, {}
local targetLabel
local elapsedSinceUpdate = 0
local auraLayoutPending = false
local ready = false
local settingsCategoryID
local POP_DURATION, POP_GROWTH = 0.45, 0.60
local PULSE_MIN_ALPHA, PULSE_DURATION = 0.30, 0.40
-- Public game states, shared by every view and display mode. Percentages are
-- display-only: restricted numbers must never be interpreted in addon Lua.
local THREAT_STATES = {
    [0] = { text = "Low threat", color = { 0.949, 0.925, 0.882 } },
    [1] = { text = "High threat", color = { 0.957, 0.827, 0.369 } },
    [2] = { text = "AGGRO", color = { 1, 0.294, 0.294 } },
    [3] = { text = "AGGRO", color = { 1, 0.294, 0.294 } },
}

local OPTIONS = {
    { key = "onlyInCombat", default = true, name = "Only show in combat", tooltip = "Hide threat until you enter combat." },
    { key = "showOnNameplates", default = true, name = "Show on nameplates", tooltip = "Show threat on attackable nameplates." },
    { key = "showOnTarget", default = true, name = "Show on target frame", tooltip = "Show threat on the target frame." },
    { key = "displayMode", default = "percent", name = "Threat display", tooltip = "Show a number with %, a number only, or Low threat, High threat, and AGGRO.", choices = {
        { "percent", "Number with %" }, { "number", "Number only" }, { "text", "Text bands" },
    } },
    -- Keep the saved key so existing color preferences survive the rule change.
    { key = "colorGradient", default = true, name = "Color by threat", tooltip = "Use neutral for Low threat, yellow for High threat, and red for AGGRO. Turn off for white text." },
    { key = "aggroPop", default = false, name = "Pop when gaining aggro", tooltip = "Briefly enlarge the threat text when you gain aggro." },
    { key = "preAggroPulse", default = false, name = "Pulse near aggro", tooltip = "Pulse at High threat to warn you before gaining aggro. Stop at Low threat or when you gain aggro." },
}
local DEFAULTS = {}
for _, option in ipairs(OPTIONS) do DEFAULTS[option.key] = option.default end

local function Option(key)
    local db = TepiuzThreatDB
    if type(db) ~= "table" then return DEFAULTS[key] end
    local value = db[key]
    if value == nil then return DEFAULTS[key] end
    return value
end

local function Enabled(key)
    return not not Option(key)
end

local function DisplayMode()
    local mode = Option("displayMode")
    return (mode == "number" or mode == "text") and mode or "percent"
end

local function PublicThreatStatus(unit)
    if type(UnitThreatSituation) ~= "function" then return end
    local ok, status = pcall(UnitThreatSituation, "player", unit)
    if ok and not issecretvalue(status) and type(status) == "number" and THREAT_STATES[status] then
        return status
    end
end

local function SetPopScale(label, scale)
    local ok = pcall(label.frame.SetScale, label.frame, scale)
    if ok then
        label.popScaled = scale ~= 1
    else
        label.popElapsed = nil
    end
end

local function ResetPop(label)
    label.popElapsed = nil
    if label.popScaled then SetPopScale(label, 1) end
end

local function HideDisplay(display)
    if not display then return end
    display.frame:Hide()
    display.text:Hide()
    display.text:SetText("")
    if display.pulse then
        display.pulse:Stop()
        display.running = false
    end
end

local function Clear(label)
    if label then
        label.frame:Hide()
        HideDisplay(label.display)
        HideDisplay(label.warning)
        ResetPop(label)
        label.wasTanking = nil
        label.shown = false
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

local function NewText(label, parent)
    local text = parent:CreateFontString(nil, "OVERLAY", label.font)
    text:SetPoint(label.point, parent, label.point, 0, 0)
    text:SetJustifyH(label.point == "LEFT" and "LEFT" or "CENTER")
    StyleLabel(text)
    return text
end

local function NewDisplay(label)
    local frame = CreateFrame("Frame", nil, label.frame)
    frame:SetAllPoints(label.frame)
    frame:Hide()
    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints(frame)
    return { frame = frame, content = content, text = NewText(label, content) }
end

local function NewLabelFrame(parent, point, font)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame:Hide()
    local label = { frame = frame, point = point, font = font, shown = false }
    label.display = NewDisplay(label)
    return label
end

local function NewLabel(parent, anchor)
    local label = NewLabelFrame(parent, "LEFT", "GameFontHighlightSmall")
    label.frame:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    label.anchor = anchor
    return label
end

local function SafeDisplay(display, percentage, status, mode)
    if mode == "text" and status == nil then
        HideDisplay(display)
        return false
    end
    local ok = pcall(function()
        if mode == "text" then
            display.text:SetText(THREAT_STATES[status].text)
        else
            display.text:SetFormattedText(mode == "number" and "%.0f" or "%.0f%%", percentage)
        end
        display.text:Show()
        display.frame:Show()
    end)
    if not ok then
        HideDisplay(display)
        return false
    end
    return true
end

local function SafeColor(display, status)
    local colored = Enabled("colorGradient")
    if colored and status == nil then return false end
    local ok = pcall(function()
        if colored then
            local color = THREAT_STATES[status].color
            display.text:SetTextColor(color[1], color[2], color[3])
        else
            display.text:SetTextColor(1, 1, 1)
        end
    end)
    return ok
end

local function EnsureWarning(label)
    if label.warning then return end
    local warning = NewDisplay(label)
    -- Animate a separate copy so stopping the pulse restores steady opacity.
    local pulse = warning.content:CreateAnimationGroup()
    warning.pulse = pulse
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(PULSE_MIN_ALPHA)
    alpha:SetToAlpha(1)
    alpha:SetDuration(PULSE_DURATION)
    alpha:SetSmoothing("IN_OUT")
    label.warning = warning
end

local function RenderWarning(label, percentage, status, mode)
    label.display.frame:SetAlpha(1)
    if not Enabled("preAggroPulse") or status ~= 1 then
        HideDisplay(label.warning)
        return
    end
    local ok = pcall(function()
        EnsureWarning(label)
        local warning = label.warning
        if not SafeDisplay(warning, percentage, status, mode)
            or not SafeColor(warning, status) then
            HideDisplay(warning)
            return
        end
        -- Animation progress can be forbidden on a nameplate. Track our own
        -- starts/stops instead of querying the widget.
        if not warning.running then
            warning.pulse:Play()
            warning.running = true
        end
        label.display.frame:SetAlpha(0)
    end)
    if not ok then
        label.display.frame:SetAlpha(1)
        HideDisplay(label.warning)
    end
end

local function UpdateAggro(label, isTanking)
    if type(isTanking) ~= "boolean" then
        label.wasTanking = nil
        ResetPop(label)
        return
    end
    if Enabled("aggroPop") and isTanking and label.wasTanking == false then
        label.popElapsed = 0
    elseif not Enabled("aggroPop") then
        ResetPop(label)
    end
    -- First observation establishes a baseline; switching targets must not pop.
    label.wasTanking = isTanking
end

local function AnimatePop(label, elapsed)
    if not label or not label.popElapsed then return end
    label.popElapsed = label.popElapsed + elapsed
    if label.popElapsed >= POP_DURATION then
        ResetPop(label)
    else
        SetPopScale(label, 1 + POP_GROWTH * math.sin(math.pi * label.popElapsed / POP_DURATION))
    end
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
    local anchor = ok and effectAnchor or defaultAnchor
    if label.anchor ~= anchor then
        label.frame:ClearAllPoints()
        label.frame:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
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
    local label = NewLabelFrame(TargetFrame, "BOTTOM", "GameFontHighlightLarge")
    -- Pixels above the portrait. Increase this to move the percentage up.
    local gapAbovePortrait = 8
    label.frame:SetPoint("BOTTOM", portrait, "TOP", 0, gapAbovePortrait)
    return label
end

local function RenderPresentation(label, percentage, status)
    local mode = DisplayMode()
    local displayOK = SafeDisplay(label.display, percentage, status, mode)
    local colorOK = SafeColor(label.display, status)
    if not displayOK or not colorOK then
        -- Preserve the selected presentation. Unavailable text/color hides only
        -- this label; never substitute numbers, other bands, or a white color.
        Clear(label)
        return false
    end
    RenderWarning(label, percentage, status, mode)
    label.frame:Show()
    return true
end

local function Render(label, unit)
    local exists = UnitExists(unit)
    local hostile = UnitCanAttack("player", unit)
    -- These booleans are public in the current Forever build. Hide the label if a later build restricts them.
    if issecretvalue(exists) or issecretvalue(hostile) then
        Clear(label)
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
        return
    end

    local status = PublicThreatStatus(unit)
    -- One public state drives all presentation, including aggro transitions.
    -- Do not mix in the detailed API's independently restricted tanking flag.
    local isTanking
    if status ~= nil then isTanking = status >= 2 end
    UpdateAggro(label, isTanking)
    if RenderPresentation(label, percentage, status) then
        label.shown = true
    end
end

local function SafeRender(label, unit)
    if not pcall(Render, label, unit) then
        Clear(label)
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
    if not parent or not anchor or parent:IsForbidden() then
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
    end
end

local function InCombat()
    local ok, locked = pcall(InCombatLockdown)
    -- Fail open. A restricted combat flag should not hide the labels permanently.
    if not ok or issecretvalue(locked) then
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
                if ok then targetLabel = label end
            end
        end
        if targetLabel then SafeRender(targetLabel, "target") end
    else
        Clear(targetLabel)
    end

    if not show or not Enabled("showOnNameplates") then
        for _, entry in pairs(active) do Clear(entry.label) end
    else
        for unit, entry in pairs(active) do
            SafeRefreshPlate(unit, entry)
        end
    end
end

local function RegisterSettings()
    if type(TepiuzThreatDB) ~= "table" then TepiuzThreatDB = {} end
    for _, option in ipairs(OPTIONS) do
        local value = TepiuzThreatDB[option.key]
        local valid = type(value) == type(option.default)
        if option.choices then
            valid = false
            for _, choice in ipairs(option.choices) do
                if value == choice[1] then valid = true end
            end
        end
        if not valid then TepiuzThreatDB[option.key] = option.default end
    end

    local settings = Settings
    local createCheckbox = settings and (settings.CreateCheckbox or settings.CreateCheckBox)
    if type(settings) ~= "table"
        or type(settings.RegisterVerticalLayoutCategory) ~= "function"
        or type(settings.RegisterAddOnSetting) ~= "function"
        or type(createCheckbox) ~= "function"
        or type(settings.RegisterAddOnCategory) ~= "function"
    then
        return
    end

    -- Saved variables are applied before ADDON_LOADED. Registering earlier would
    -- bind the controls to a table the client then replaces.
    pcall(function()
        local category = settings.RegisterVerticalLayoutCategory("Tepiuz Threat")
        for _, option in ipairs(OPTIONS) do
            local setting = settings.RegisterAddOnSetting(
                category, "TepiuzThreat_" .. option.key, option.key, TepiuzThreatDB, type(option.default), option.name, option.default)
            if option.choices then
                if type(settings.CreateDropdown) == "function" and type(settings.CreateControlTextContainer) == "function" then
                    local choices = option.choices
                    local function GetChoices()
                        local container = settings.CreateControlTextContainer()
                        for _, choice in ipairs(choices) do container:Add(choice[1], choice[2]) end
                        return container:GetData()
                    end
                    settings.CreateDropdown(category, setting, GetChoices, option.tooltip)
                end
            else
                createCheckbox(category, setting, option.tooltip)
            end
            setting:SetValueChangedCallback(RefreshAll)
        end
        settings.RegisterAddOnCategory(category)
        settingsCategoryID = category:GetID()
    end)
end

local function DiscoverPlates()
    -- Covers a reload with plates already on screen, and entering a new zone.
    for unit in pairs(active) do RemovePlate(unit) end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok then return end
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
    elseif event == "PLAYER_TARGET_CHANGED" then
        Clear(targetLabel)
        RefreshAll()
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
    pcall(driver.RegisterEvent, driver, event)
end

-- Covers missed events and nameplates whose frames appear a moment later.
driver:SetScript("OnUpdate", function(_, elapsed)
    AnimatePop(targetLabel, elapsed)
    for _, entry in pairs(active) do AnimatePop(entry.label, elapsed) end
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
                if entry.label and entry.label.shown then
                    SafeRefreshPlate(unit, entry, true)
                end
            end
        end
    end
end)

SLASH_TEPIUZTHREAT1 = "/tthreat"
SLASH_TEPIUZTHREAT2 = "/tepiuzthreat"
---@param _message? string
SlashCmdList.TEPIUZTHREAT = function(_message)
    if settingsCategoryID and Settings and type(Settings.OpenToCategory) == "function"
        and pcall(Settings.OpenToCategory, settingsCategoryID) then
        return
    end
    print("Tepiuz Threat: options unavailable. Look under Settings > AddOns > Tepiuz Threat.")
end
