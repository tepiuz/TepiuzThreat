-- WoW Forever. Only this addon's own frames and FontStrings are changed.
local ADDON_NAME = ...

local driver = CreateFrame("Frame")
local active, labels = {}, {}
local targetLabel
local failures, lastFailure = 0, "none"
local elapsedSinceUpdate = 0
local auraLayoutPending = false
local ready = false
local combatStateRestricted = false
local curves
local settingsCategoryID
local popRestricted = false
local POP_DURATION, POP_GROWTH = 0.45, 0.60
local PULSE_MIN_ALPHA, PULSE_DURATION = 0.30, 0.40

local OPTIONS = {
    { key = "onlyInCombat", default = true, name = "Only show in combat", tooltip = "Hide threat until you enter combat." },
    { key = "showOnNameplates", default = true, name = "Show on nameplates", tooltip = "Show threat on attackable nameplates." },
    { key = "showOnTarget", default = true, name = "Show on target frame", tooltip = "Show threat on the target frame." },
    { key = "displayMode", default = "percent", name = "Threat display", tooltip = "Choose whole numbers with or without %, or text bands on both nameplates and the target frame.", choices = {
        { "percent", "Number with %" }, { "number", "Number only" }, { "text", "Text bands" },
    } },
    { key = "colorGradient", default = true, name = "Color by threat", tooltip = "Gradually change from a neutral color through yellow and orange to red as threat approaches 100%." },
    { key = "aggroPop", default = false, name = "Pop when gaining aggro", tooltip = "Enlarge the nameplate and target labels when an enemy switches to you. Unavailable when the game restricts aggro changes." },
    { key = "preAggroPulse", default = false, name = "Pulse near aggro", tooltip = "Pulse the nameplate and target labels at 90% or more threat, until you gain aggro." },
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
    if ok and not issecretvalue(status) and type(status) == "number"
        and status >= 0 and status <= 3 and status % 1 == 0 then
        return status
    end
end

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

local function LabelFailure(label, operation)
    label.failures = label.failures or {}
    if not label.failures[operation] then
        label.failures[operation] = true
        Failure(label.kind .. ": " .. operation)
    end
end

local function SetPopScale(label, scale)
    local ok = pcall(label.frame.SetScale, label.frame, scale)
    if ok then
        label.popScaled = scale ~= 1
    else
        label.popElapsed = nil
        LabelFailure(label, "aggro scale rejected")
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
    if display.bands then
        for _, text in ipairs(display.bands) do text:Hide() end
        display.aggro:Hide()
    end
end

local function Clear(label)
    if label then
        label.frame:Hide()
        HideDisplay(label.display)
        HideDisplay(label.warning)
        ResetPop(label)
        label.wasTanking = nil
        label.mode = nil
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

local function NewLabelFrame(parent, point, font, kind)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame:Hide()
    local label = { frame = frame, point = point, font = font, kind = kind, state = "hidden" }
    label.display = NewDisplay(label)
    return label
end

local function NewLabel(parent, anchor)
    local label = NewLabelFrame(parent, "LEFT", "GameFontHighlightSmall", "nameplate")
    label.frame:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    label.anchor = anchor
    return label
end

local function NewStepCurve(points)
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    for _, point in ipairs(points) do curve:AddPoint(point[1], point[2]) end
    return curve
end

local function BuildCurves()
    local color = C_CurveUtil.CreateColorCurve()
    color:SetType(Enum.LuaCurveType.Linear)
    for _, point in ipairs({
        { 0, 0.949, 0.925, 0.882 }, { 50, 0.949, 0.925, 0.882 },
        { 75, 0.957, 0.827, 0.369 }, { 90, 0.965, 0.541, 0.220 },
        { 100, 1, 0.294, 0.294 },
    }) do color:AddPoint(point[1], CreateColor(point[2], point[3], point[4], 1)) end
    return {
        color = color,
        -- No threat is the range that rounds to zero in the numeric display.
        bands = {
            NewStepCurve({ { 0, 1 }, { 0.5, 0 } }),
            NewStepCurve({ { 0, 0 }, { 0.5, 1 }, { 50, 0 } }),
            NewStepCurve({ { 0, 0 }, { 50, 1 }, { 80, 0 } }),
            NewStepCurve({ { 0, 0 }, { 80, 1 } }),
        },
        warning = NewStepCurve({ { 0, 0 }, { 90, 1 } }),
        normal = NewStepCurve({ { 0, 1 }, { 90, 0 } }),
    }
end

local function EnsureBands(label, display)
    if display.bands then return end
    local frame = CreateFrame("Frame", nil, display.content)
    frame:SetAllPoints(display.content)
    local bands = {}
    for i, name in ipairs({ "No threat", "Low threat", "Medium threat", "High threat" }) do
        local text = NewText(label, frame)
        text:SetText(name)
        bands[i] = text
    end
    local aggro = NewText(label, display.content)
    aggro:SetText("AGGRO")
    display.bandFrame, display.bands, display.aggro = frame, bands, aggro
end

local function RenderDisplay(label, display, percentage, isTanking, mode)
    if mode == "text" then
        EnsureBands(label, display)
        display.text:Hide()
        display.text:SetText("")
        -- Each static label has its own opacity curve. Lua never chooses a band
        -- by inspecting a restricted number, or reads derived widget properties.
        display.bandFrame:SetAlphaFromBoolean(isTanking, 0, 1)
        display.bandFrame:Show()
        for i, text in ipairs(display.bands) do
            text:SetAlpha(curves.bands[i]:Evaluate(percentage))
            text:Show()
        end
        display.aggro:SetAlphaFromBoolean(isTanking, 1, 0)
        display.aggro:Show()
    else
        if display.bands then
            display.bandFrame:Hide()
            display.aggro:Hide()
        end
        display.text:SetFormattedText(mode == "number" and "%.0f" or "%.0f%%", percentage)
        display.text:Show()
    end
    display.frame:Show()
end

local function RenderStateBand(display, status, isTanking)
    if display.bands then
        display.bandFrame:Hide()
        display.aggro:Hide()
    end
    local tanking = status >= 2
    if not issecretvalue(isTanking) and type(isTanking) == "boolean" then tanking = isTanking end
    local name = tanking and "AGGRO" or status == 1 and "High threat" or "Low threat"
    display.text:SetText(name)
    display.text:Show()
    display.frame:Show()
end

local function SafeDisplay(label, display, percentage, isTanking, mode, status)
    display.bandSource = nil
    if mode == "text" then
        if curves and pcall(RenderDisplay, label, display, percentage, isTanking, mode) then
            display.bandSource = "percentage"
            return mode
        end
        LabelFailure(label, "percentage text bands unavailable")
        if status ~= nil then
            RenderStateBand(display, status, isTanking)
            display.bandSource = "state"
            return mode
        end
        mode = "percent"
    end
    RenderDisplay(label, display, percentage, isTanking, mode)
    return mode
end

local function ColorDisplay(display, r, g, b)
    display.text:SetTextColor(r, g, b)
    if display.bands then
        for _, text in ipairs(display.bands) do text:SetTextColor(r, g, b) end
        display.aggro:SetTextColor(r, g, b)
    end
end

local function SafeColor(label, display, percentage, status)
    display.colorSource = "plain"
    if not Enabled("colorGradient") then
        ColorDisplay(display, 1, 1, 1)
        return
    end
    local ok = pcall(function()
        if not curves then error("curves unavailable") end
        local r, g, b = curves.color:EvaluateUnpacked(percentage)
        ColorDisplay(display, r, g, b)
    end)
    if ok then
        display.colorSource = "percentage"
        return
    end
    if curves then LabelFailure(label, "percentage threat color rejected") end
    -- Threat state has a separate restriction policy from detailed values.
    -- Only use this fallback when the dedicated API returns a public status.
    if status == 0 then
        ColorDisplay(display, 0.949, 0.925, 0.882)
        display.colorSource = "state"
        return
    end
    if status ~= nil and type(GetThreatStatusColor) == "function" then
        local colorOK = pcall(function()
            local r, g, b = GetThreatStatusColor(status)
            ColorDisplay(display, r, g, b)
        end)
        if colorOK then display.colorSource = "state"; return end
    end
    ColorDisplay(display, 1, 1, 1)
end

local function EnsureWarning(label)
    if label.warning then return end
    local warning = NewDisplay(label)
    -- Gate opacity on the outer frame, and animate a separate inner frame.
    -- This keeps the animation independent of all restricted values.
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

local function RenderWarning(label, percentage, isTanking, mode, status)
    label.warningSource = nil
    label.display.frame:SetAlpha(1)
    if not Enabled("preAggroPulse") or (not curves and status == nil) then
        if label.warning then
            HideDisplay(label.warning)
        end
        return
    end
    local ok = pcall(function()
        EnsureWarning(label)
        local warning = label.warning
        SafeDisplay(label, warning, percentage, isTanking, mode, status)
        SafeColor(label, warning, percentage, status)
        local curveOK = curves and pcall(function()
            warning.frame:SetAlphaFromBoolean(isTanking, 0, curves.warning:Evaluate(percentage))
            label.display.frame:SetAlphaFromBoolean(isTanking, 1, curves.normal:Evaluate(percentage))
        end)
        if curveOK then
            label.warningSource = "percentage"
        elseif status ~= nil then
            -- Status 1 is the game's high-threat state before gaining aggro;
            -- this is a coarse warning, not an inferred secret percentage.
            local warn = status == 1 and not isTanking
            warning.frame:SetAlpha(warn and 1 or 0)
            label.display.frame:SetAlpha(warn and 0 or 1)
            label.warningSource = "state"
        else
            error("warning threshold unavailable")
        end
        -- Animation progress can become forbidden under a restricted-opacity
        -- nameplate. Track our own starts/stops instead of querying the widget.
        if not warning.running then
            warning.pulse:Play()
            warning.running = true
        end
    end)
    if not ok then
        label.display.frame:SetAlpha(1)
        if label.warning then
            HideDisplay(label.warning)
        end
        LabelFailure(label, "pre-aggro pulse rejected")
    end
end

local function UpdateAggro(label, isTanking)
    if issecretvalue(isTanking) then
        if Enabled("aggroPop") then popRestricted = true end
        label.wasTanking = nil
        ResetPop(label)
        return
    end
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
    if not ok then Failure("effect layout lookup rejected") end
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
    local label = NewLabelFrame(TargetFrame, "BOTTOM", "GameFontHighlightLarge", "target")
    -- Pixels above the portrait. Increase this to move the percentage up.
    local gapAbovePortrait = 8
    label.frame:SetPoint("BOTTOM", portrait, "TOP", 0, gapAbovePortrait)
    return label
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

    local isTanking, _, percentage = UnitDetailedThreatSituation("player", unit)
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

    local status = PublicThreatStatus(unit)
    -- The dedicated threat-state API can remain public even when all returns
    -- from the detailed API are restricted. It also enables nameplate pops.
    if status ~= nil and (issecretvalue(isTanking) or type(isTanking) ~= "boolean") then
        isTanking = status >= 2
    end
    UpdateAggro(label, isTanking)
    if not issecretvalue(isTanking) and type(isTanking) ~= "boolean" then isTanking = false end
    local mode = DisplayMode()
    mode = SafeDisplay(label, label.display, percentage, isTanking, mode, status)
    SafeColor(label, label.display, percentage, status)
    RenderWarning(label, percentage, isTanking, mode, status)
    label.mode = mode
    label.frame:Show()
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
        Failure("nameplate attachment rejected")
    end
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
        Failure("settings API missing")
        return
    end

    -- Saved variables are applied before ADDON_LOADED. Registering earlier would
    -- bind the controls to a table the client then replaces.
    local ok = pcall(function()
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
                else
                    Failure("display dropdown API missing")
                end
            else
                createCheckbox(category, setting, option.tooltip)
            end
            setting:SetValueChangedCallback(RefreshAll)
        end
        settings.RegisterAddOnCategory(category)
        settingsCategoryID = category:GetID()
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
    if not curves then
        local ok, result = pcall(BuildCurves)
        if ok then curves = result else Failure("threat curves unavailable") end
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
    if not pcall(driver.RegisterEvent, driver, event) then Failure("event unavailable: " .. event) end
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
                if entry.label and entry.label.state ~= "hidden" then
                    SafeRefreshPlate(unit, entry, true)
                end
            end
        end
    end
end)

SLASH_TEPIUZTHREAT1 = "/tthreat"
SLASH_TEPIUZTHREAT2 = "/tepiuzthreat"
local function PrintDiagnostics()
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
    print("Display:", DisplayMode(), "| gradient:", Enabled("colorGradient") and "on" or "off",
        "| aggro pop:", Enabled("aggroPop") and "on" or "off",
        "| pre-aggro pulse:", Enabled("preAggroPulse") and "on" or "off")
    print("Threat curves:", curves and "available" or "unavailable",
        "| restricted aggro changes seen:", popRestricted and "yes" or "no")
    local plateText, plateColored, plateWarnings, plateFallbacks = 0, 0, 0, 0
    for _, entry in pairs(active) do
        local label = entry.label
        if label and label.state ~= "hidden" then
            if label.mode == "text" then plateText = plateText + 1 end
            if label.display.colorSource ~= "plain" then plateColored = plateColored + 1 end
            if label.warningSource then plateWarnings = plateWarnings + 1 end
            if label.display.bandSource == "state" or label.display.colorSource == "state"
                or label.warningSource == "state" then plateFallbacks = plateFallbacks + 1 end
        end
    end
    print("Nameplate display:", "text bands:", plateText, "| colored:", plateColored,
        "| pulse configured:", plateWarnings, "| state fallbacks:", plateFallbacks)
    print("Failures:", failures, "| last:", lastFailure)
end

SlashCmdList.TEPIUZTHREAT = function(message)
    if type(message) == "string" and message:match("^%s*(.-)%s*$"):lower() == "debug" then
        PrintDiagnostics()
        return
    end
    if settingsCategoryID and Settings and type(Settings.OpenToCategory) == "function"
        and pcall(Settings.OpenToCategory, settingsCategoryID) then
        return
    end
    print("Tepiuz Threat: options unavailable. Look under Settings > AddOns > Tepiuz Threat.")
end
