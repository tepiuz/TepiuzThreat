-- Run from the repository root: lua tests/threat_display.lua
-- These mocks verify addon behavior, not the client's secret-value enforcement.
-- Tests also run on newer Lua versions; keep the guarded compatibility fallbacks.
---@diagnostic disable-next-line: deprecated
local unpackValues = unpack or table.unpack
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function secret(value)
    local function reject() error("addon inspected a restricted value") end
    return setmetatable({ restricted = true, value = value }, {
        __lt = reject, __le = reject, __concat = reject, __tostring = reject,
        __add = reject, __sub = reject, __mul = reject, __div = reject,
    })
end
local function restricted(value) return type(value) == "table" and value.restricted == true end
-- False needs special handling because it is a valid restricted boolean.
local function engineValue(value)
    if restricted(value) then return value.value end
    return value
end

local function setup(saved, noCurves, noDropdown, solo)
    local e = { frames = {}, animations = {}, messages = {}, settings = {}, queries = 0,
        inInstance = false, instanceType = "none", inGroup = not solo, events = {},
        unitExists = {}, threats = {}, nativeStatuses = { target = 0, nameplate1 = 0 }, plates = {}, stateQueries = 0,
        threat = { tanking = false, percentage = 65 }, engine = {} }
    local methods = {}
    local function node(parent, font)
        local n = setmetatable({ parent = parent, children = {}, shown = true, alpha = 1, scale = 1, font = font }, { __index = methods })
        if parent then parent.children[#parent.children + 1] = n end
        return n
    end
    function methods:SetSize(w, h) self.width, self.height = w, h end
    function methods:SetAllPoints(anchor) self.allPoints = anchor end
    function methods:SetPoint(...) self.point = { ... } end
    function methods:ClearAllPoints() self.point = nil end
    function methods:SetJustifyH(value) self.justify = value end
    function methods:SetWordWrap(value) self.wrap = value end
    function methods:SetFont(font, size, outline) self.fontName, self.fontSize, self.outline = font, size, outline end
    function methods:GetFont()
        return self.fontName or "GameFont.ttf", self.fontSize or (self.font == "GameFontHighlightLarge" and 18 or 12)
    end
    function methods:Hide() self.shown = false end
    function methods:Show() self.shown = true end
    function methods:IsForbidden() return self.forbidden or false end
    function methods:IsVisible() return self.shown end
    function methods:GetChildren() return unpackValues(self.children) end
    function methods:CreateFontString(_, _, font)
        if e.engine.rejectNextFont then e.engine.rejectNextFont = false; error("font creation rejected") end
        return node(self, font)
    end
    function methods:SetText(value)
        if e.engine.rejectText and value ~= "" then error(e.engine.errorObject or "text application rejected") end
        self.text = engineValue(value)
    end
    function methods:SetFormattedText(format, value) self.text = string.format(format, engineValue(value)) end
    function methods:SetTextColor(r, g, b)
        if e.engine.rejectColor then error(e.engine.errorObject or "color application rejected") end
        assert(not restricted(r) and not restricted(g) and not restricted(b), "colors must be public")
        self.color = { engineValue(r), engineValue(g), engineValue(b) }
    end
    function methods:SetAlpha(value)
        assert(not restricted(value), "opacity must be public")
        self.alpha = engineValue(value)
    end
    function methods:SetScale(value)
        if e.engine.rejectScale then error("scale mutation rejected") end
        self.scale = engineValue(value)
    end
    function methods:SetScript(event, callback) self[event] = callback end
    function methods:RegisterEvent(event) e.events[event] = true end
    function methods:GetUnit() return self.unit end
    function methods:CreateAnimationGroup()
        if e.engine.rejectPulseCreation then error("pulse creation rejected") end
        local group = { owner = self, playing = false, plays = 0 }
        e.animations[#e.animations + 1] = group
        function group:SetLooping(value) self.loop = value end
        function group:CreateAnimation(kind)
            local animation = { kind = kind }
            self.animation = animation
            function animation:SetFromAlpha(value) self.from = value end
            function animation:SetToAlpha(value) self.to = value end
            function animation:SetDuration(value) self.duration = value end
            function animation:SetSmoothing(value) self.smoothing = value end
            return animation
        end
        function group:Play()
            if e.engine.rejectPulseStart then error("pulse start rejected") end
            self.playing = true; self.plays = self.plays + 1
        end
        function group:Stop() self.playing = false end
        function group:IsPlaying() error("animation progress forbidden") end
        return group
    end
    local env = setmetatable({ TepiuzThreatDB = saved, SlashCmdList = {} }, { __index = _G })
    env.issecretvalue = restricted
    env.CreateFrame = function(_, _, parent)
        local frame = node(parent)
        e.frames[#e.frames + 1] = frame
        return frame
    end
    env.TargetFrame = node()
    env.TargetFrame.portrait = node()
    local plate = node()
    plate.unit = "nameplate1"
    plate.UnitFrame = node()
    plate.UnitFrame.PlayerLevelDiffFrame = node()
    plate.UnitFrame.HealthBarsContainer = node()
    e.plate = plate
    e.plates.nameplate1 = plate
    function e:addPlate(unit)
        local extra = node()
        extra.unit, extra.UnitFrame = unit, node()
        extra.UnitFrame.PlayerLevelDiffFrame = node()
        extra.UnitFrame.HealthBarsContainer = node()
        self.plates[unit] = extra
        self:event("NAME_PLATE_UNIT_ADDED", unit)
        return extra
    end
    env.C_NamePlate = {
        GetNamePlates = function()
            local plates = {}
            if e.platePresent then for _, p in pairs(e.plates) do plates[#plates + 1] = p end end
            return plates
        end,
        GetNamePlateForUnit = function(unit) return e.plates[unit] end,
    }
    env.UnitExists = function(unit)
        if e.unitExists[unit] ~= nil then return e.unitExists[unit] end
        return e.exists == nil and true or e.exists
    end
    env.UnitCanAttack = function() return e.hostile == nil and true or e.hostile end
    env.UnitDetailedThreatSituation = function(_, unit)
        e.queries = e.queries + 1
        local threat = e.threats[unit] or e.threat
        return threat.tanking, 0, threat.percentage
    end
    env.UnitThreatSituation = function(player, unit)
        equal(player, "player", "query threat state for the player")
        e.stateQueries = e.stateQueries + 1
        if e.engine.rejectStateQuery then error(e.engine.errorObject or "state query rejected") end
        return e.nativeStatuses[unit]
    end
    env.IsInGroup = function()
        if e.engine.rejectGroupQuery then error("group query rejected") end
        return e.inGroup
    end
    env.IsInInstance = function()
        if e.engine.rejectInstanceQuery then error("instance query rejected") end
        return e.inInstance, e.instanceType
    end
    env.print = function(...)
        local line = {}
        for i = 1, select("#", ...) do line[i] = tostring(select(i, ...)) end
        e.messages[#e.messages + 1] = table.concat(line, " ")
    end
    -- The client rejects addon curve evaluation with restricted inputs. The
    -- new presentation must not depend on curves at all, even for public data.
    if not noCurves then
        local function rejectCurve() error("threat presentation must not use curves") end
        env.C_CurveUtil = { CreateCurve = rejectCurve, CreateColorCurve = rejectCurve }
    end
    env.Settings = {
        RegisterVerticalLayoutCategory = function()
            e.category = { GetID = function() return 42 end }
            return e.category
        end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function(id) e.openedCategory = id; e.optionsOpened = (e.optionsOpened or 0) + 1 end,
        CreateCheckbox = function() end,
        RegisterAddOnSetting = function(_, _, key, db, kind, _, default)
            equal(kind, type(default), "setting type")
            local setting = {}
            function setting:SetValueChangedCallback(callback) self.callback = callback end
            function setting:SetValue(value) db[key] = value; self.callback() end
            e.settings[key] = setting
            return setting
        end,
        CreateControlTextContainer = function()
            local container = { choices = {} }
            function container:Add(value, text) self.choices[#self.choices + 1] = { value, text } end
            function container:GetData() return self.choices end
            return container
        end,
    }
    if not noDropdown then env.Settings.CreateDropdown = function(_, setting, getter) setting.choices = getter() end end
    local chunk
    if setfenv then
        chunk = assert(loadfile("TepiuzThreat.lua"))
        setfenv(chunk, env)
    else
        -- Lua 5.2+ accepts the environment directly; Lua 5.1 uses the branch above.
        ---@diagnostic disable-next-line: redundant-parameter
        chunk = assert(loadfile("TepiuzThreat.lua", "t", env))
    end
    chunk("TepiuzThreat")
    e.env, e.driver = env, e.frames[1]
    function e:event(event, unit) self.driver.OnEvent(self.driver, event, unit) end
    function e:tick(elapsed) self.driver.OnUpdate(self.driver, elapsed) end
    function e:set(key, value) self.settings[key]:SetValue(value) end
    function e:refresh() self:event("UNIT_THREAT_LIST_UPDATE", secret("ignored payload")) end
    function e:root() return self.env.TargetFrame.children[1] end
    function e:visible(root)
        local texts = {}
        local function visit(n, opacity, shown)
            shown = shown and n.shown
            opacity = opacity * n.alpha
            if shown and opacity > 0 and n.font and n.text and n.text ~= "" then texts[#texts + 1] = n end
            for _, child in ipairs(n.children) do visit(child, opacity, shown) end
        end
        visit(root or self:root(), 1, true)
        return texts
    end
    function e:text(expected)
        local texts = self:visible()
        equal(#texts, 1, "exactly one displayed label")
        equal(texts[1].text, expected, "displayed threat")
        return texts[1]
    end
    e:event("ADDON_LOADED", "TepiuzThreat")
    e:event("PLAYER_LOGIN")
    return e
end

local e = setup({ onlyInCombat = true, showOnNameplates = false })
equal(e.settings.onlyInCombat, nil, "legacy combat preference no longer registers a setting")
equal(e.env.TepiuzThreatDB.showOnNameplates, false, "existing option preserved")
equal(e.env.TepiuzThreatDB.aggroPop, false, "pop defaults off")
equal(e.env.TepiuzThreatDB.preAggroPulse, false, "pulse defaults off")
equal(e.env.TepiuzThreatDB.largerText, false, "larger text defaults off")
equal(e.env.TepiuzThreatDB.visibilityMode, "group", "visibility defaults to group")
equal(e.settings.onlyInGroupContent, nil, "old checkbox no longer registered")
equal(#e.settings.displayMode.choices, 3, "three display modes")
equal(#e.settings.visibilityMode.choices, 3, "three visibility modes")
for i, mode in ipairs({ "group", "instance", "always" }) do
    equal(e.settings.visibilityMode.choices[i][1], mode, "visibility choice order")
end
e:text("65%")
e:set("displayMode", "number"); e:text("65")
e:set("displayMode", "text"); e:text("Low threat")
local states = {
    { 0, "Low threat", { 0.949, 0.925, 0.882 } },
    { 1, "High threat", { 0.957, 0.827, 0.369 } },
    { 2, "AGGRO", { 1, 0.294, 0.294 } },
    { 3, "AGGRO", { 1, 0.294, 0.294 } },
}
-- Percentages and detailed tanking flags cannot override the public state.
for _, state in ipairs(states) do
    e.nativeStatuses.target = state[1]
    for _, value in ipairs({ 0, 0.5, 49.99, 50, 65, 79.99, 80, 90, 100 }) do
        e.threat.percentage = secret(value); e.threat.tanking = secret(state[1] < 2)
        e:refresh()
        local text = e:text(state[2])
        for i = 1, 3 do equal(text.color[i], state[3][i], "state color independent of percentage") end
    end
end
e:set("displayMode", "percent"); e:text("100%")
e:set("colorGradient", false)
local white = e:text("100%").color
for i = 1, 3 do equal(white[i], 1, "explicit white preference") end
e:set("colorGradient", true)
e.threat.percentage = nil; e:refresh(); equal(#e:visible(), 0, "missing data hides label")
e.threat.percentage = 0; e.nativeStatuses.target = 0; e:refresh(); e:text("0%")
e.hostile = false; e:refresh(); equal(#e:visible(), 0, "friendly target hidden")
e.hostile = true; e:refresh()
e.exists = secret(false); e:refresh(); equal(#e:visible(), 0, "restricted eligibility hidden")
e.exists = true; e:refresh()

e:set("aggroPop", true)
e.nativeStatuses.target = 2; e:refresh(); e:tick(0.225)
equal(e:root().scale, 1.6, "public aggro transition pops despite restricted detailed flag")
e:tick(0.225); equal(e:root().scale, 1, "pop returns to normal")
e.nativeStatuses.target = 3; e:refresh(); e:tick(0.05)
equal(e:root().scale, 1, "changing aggro states does not repeat pop")
e.nativeStatuses.target = 0; e:refresh(); e.nativeStatuses.target = 3; e:event("PLAYER_TARGET_CHANGED")
e:tick(0.05); equal(e:root().scale, 1, "target change resets baseline")
e.nativeStatuses.target = 0; e:refresh(); e.nativeStatuses.target = secret(3); e:refresh(); e:tick(0.1)
equal(e:root().scale, 1, "restricted state cannot pop")
equal(#e:visible(), 0, "restricted state cannot supply enabled color")
e.nativeStatuses.target = 3; e:refresh(); e:tick(0.05)
equal(e:root().scale, 1, "state recovery establishes a fresh baseline")

local pulse = setup({ preAggroPulse = true, displayMode = "text" })
pulse.threat.percentage = secret(65); pulse.threat.tanking = secret(true)
pulse.nativeStatuses.target = 1; pulse:refresh(); pulse:text("High threat")
equal(pulse.animations[1].loop, "BOUNCE"); equal(pulse.animations[1].animation.from, 0.30)
equal(pulse.animations[1].animation.to, 1); equal(pulse.animations[1].animation.duration, 0.40)
local base, warning = pulse:root().children[1], pulse:root().children[2]
equal(base.alpha, 0, "normal copy hidden during high-state warning")
equal(warning.shown, true, "warning copy enabled")
pulse:refresh(); equal(pulse.animations[1].plays, 1, "refresh does not restart pulse")
pulse:set("displayMode", "number"); pulse:text("65")
pulse.threat.percentage = secret(99.6); pulse.nativeStatuses.target = 0; pulse:refresh(); pulse:text("100")
equal(base.alpha, 1, "low state stays steady regardless of percentage")
equal(warning.shown, false); equal(pulse.animations[1].playing, false, "low state stops pulse")
pulse.nativeStatuses.target = 1; pulse:refresh()
equal(pulse.animations[1].plays, 2, "returning to high state restarts pulse")
pulse.nativeStatuses.target = 2; pulse:refresh(); pulse:text("100")
equal(base.alpha, 1, "aggro stops warning"); equal(warning.shown, false)
pulse:set("displayMode", "text"); pulse:text("AGGRO")
pulse.nativeStatuses.target = 1; pulse:refresh(); pulse:set("preAggroPulse", false)
equal(pulse.animations[1].playing, false, "disabling stops animation")
pulse:set("preAggroPulse", true); pulse.threat.percentage = nil; pulse:event("PLAYER_REGEN_ENABLED")
equal(#pulse:visible(), 0, "missing threat hides display"); equal(pulse.animations[1].playing, false, "hiding stops animation")

local noCurves = setup({ displayMode = "text", preAggroPulse = true }, true)
noCurves.nativeStatuses.target = 1; noCurves.threat.percentage = secret(95); noCurves:refresh()
noCurves:text("High threat")
equal(noCurves.animations[1].playing, true, "state styling and alerts require no curve API")
local rejected = setup({ displayMode = "text" })
rejected.engine.rejectText = true; rejected:refresh()
equal(#rejected:visible(), 0, "rejected text never substitutes a number")
equal(rejected.env.TepiuzThreatDB.displayMode, "text", "failed styling preserves selected mode")
rejected.engine.rejectText = false; rejected.engine.rejectColor = true; rejected:refresh()
equal(#rejected:visible(), 0, "rejected color never substitutes white")
rejected.engine.rejectColor = false; rejected:refresh(); rejected:text("Low threat")
for _, failure in ipairs({ "rejectNextFont", "rejectPulseCreation", "rejectPulseStart" }) do
    local failedPulse = setup({ displayMode = "text", preAggroPulse = true })
    failedPulse.engine[failure] = true; failedPulse.nativeStatuses.target = 1; failedPulse:refresh()
    failedPulse:text("High threat")
    equal(failedPulse:root().children[1].alpha, 1, "failed pulse leaves main text steady")
    failedPulse.engine[failure] = false; failedPulse:refresh(); failedPulse:text("High threat")
    equal(failedPulse:root().children[1].alpha, 0, "pulse recovers on next refresh")
end
local scaleFailure = setup({ aggroPop = true })
scaleFailure.engine.rejectScale = true; scaleFailure.nativeStatuses.target = 3; scaleFailure.threat.percentage = 100
scaleFailure:refresh(); scaleFailure:tick(0.15); scaleFailure:text("100%")
scaleFailure:event("PLAYER_TARGET_CHANGED"); scaleFailure:text("100%")
local malformed = setup({ displayMode = "invalid", aggroPop = "yes", largerText = "yes", showOnTarget = false })
equal(malformed.env.TepiuzThreatDB.displayMode, "percent", "invalid mode reset")
equal(malformed.env.TepiuzThreatDB.aggroPop, false, "invalid boolean reset")
equal(malformed.env.TepiuzThreatDB.largerText, false, "invalid text size preference reset")
equal(malformed.env.TepiuzThreatDB.showOnTarget, false, "saved hidden target preserved")
equal(malformed:root(), nil, "disabled target not created")
local settingsFallback = setup(nil, false, true)
settingsFallback:text("65%")
equal(settingsFallback.settings.preAggroPulse ~= nil, true, "other settings survive missing dropdown")

-- The optional content filter applies to both displays; threat data is still required.
local content = setup({ preAggroPulse = true, aggroPop = true })
local contentPlate = content:addPlate("nameplate1").UnitFrame.children[1]
equal(content.events.ZONE_CHANGED_NEW_AREA, true, "zone changes refresh visibility")
content.nativeStatuses.target, content.nativeStatuses.nameplate1 = 1, 1; content:refresh()
content:set("visibilityMode", "instance")
equal(#content:visible(), 0, "enabling content filter hides outdoor target")
equal(#content:visible(contentPlate), 0, "enabling content filter hides outdoor nameplate")
for _, animation in ipairs(content.animations) do equal(animation.playing, false, "filter stops pulses") end
content.inInstance = true
for _, instanceType in ipairs({ "party", "raid" }) do
    content.instanceType = instanceType; content:event("ZONE_CHANGED_NEW_AREA")
    content:text("65%")
    equal(#content:visible(contentPlate), 1, "party and raid content shows nameplate")
    content.threat.percentage = nil; content:event("PLAYER_REGEN_ENABLED")
    equal(#content:visible(), 0, "missing threat hides target in group content")
    equal(#content:visible(contentPlate), 0, "missing threat hides nameplate in group content")
    content.threat.percentage = 65; content:refresh(); content:text("65%")
    equal(#content:visible(contentPlate), 1, "returning threat data restores nameplate")
end
for _, instanceType in ipairs({ "none", "pvp", "arena", "scenario", "unknown", secret("party") }) do
    content.instanceType = instanceType; content:event("ZONE_CHANGED_NEW_AREA")
    equal(#content:visible(), 0, "other or restricted instance types hide target")
    equal(#content:visible(contentPlate), 0, "other or restricted instance types hide nameplate")
end
content.instanceType = "party"
for _, inInstance in ipairs({ false, secret(true) }) do
    content.inInstance = inInstance; content:refresh()
    equal(#content:visible(), 0, "requires a public positive instance flag")
end
content.inInstance = true; content:refresh(); content:text("65%")
content.nativeStatuses.target = 3; content:refresh(); content:tick(0.225)
equal(content:root().scale, 1.6, "aggro pop runs inside group content")
content.inInstance, content.instanceType = false, "none"; content:event("ZONE_CHANGED_NEW_AREA")
equal(content:root().scale, 1, "leaving group content resets pop")
equal(#content:visible(), 0, "leaving group content hides target")
equal(#content:visible(contentPlate), 0, "leaving group content hides nameplate")
content.inInstance, content.instanceType = true, "party"; content:tick(0.2)
content:text("65%")
equal(content:root().scale, 1, "periodic refresh recovers without a false aggro pop")
content.engine.rejectInstanceQuery = true; content:refresh()
equal(#content:visible(), 0, "failed instance query hides filtered threat")
content.env.IsInInstance = nil; content:refresh()
equal(#content:visible(), 0, "missing instance API hides filtered threat")
content:set("visibilityMode", "always"); content:text("65%")
equal(#content:visible(contentPlate), 1, "disabling filter restores both displays without instance API")
local savedContent = setup({ onlyInGroupContent = true })
equal(savedContent.env.TepiuzThreatDB.visibilityMode, "instance", "saved content filter migrated")
equal(savedContent.env.TepiuzThreatDB.onlyInGroupContent, nil, "legacy checkbox removed after migration")
equal(savedContent:root(), nil, "saved filter prevents outdoor target creation at login")
savedContent.inInstance, savedContent.instanceType = true, "raid"
savedContent:event("PLAYER_ENTERING_WORLD"); savedContent:text("65%")

-- Group visibility follows membership even outside instances, for both displays.
local grouped = setup({ visibilityMode = "always", preAggroPulse = true }, false, false, true)
local groupedPlate = grouped:addPlate("nameplate1").UnitFrame.children[1]
equal(grouped.events.GROUP_ROSTER_UPDATE, true, "membership changes refresh visibility")
grouped:set("visibilityMode", "group")
equal(#grouped:visible(), 0, "solo target hidden")
equal(#grouped:visible(groupedPlate), 0, "solo nameplate hidden")
for _, instanceType in ipairs({ "none", "party", "raid", "pvp" }) do
    grouped.inInstance, grouped.instanceType = instanceType ~= "none", instanceType
    grouped.inGroup = true; grouped:event("GROUP_ROSTER_UPDATE")
    grouped:text("65%")
    equal(#grouped:visible(groupedPlate), 1, "group membership shows both displays in any zone")
    grouped.threat.percentage = nil; grouped:refresh()
    equal(#grouped:visible(), 0, "group membership still requires target threat")
    equal(#grouped:visible(groupedPlate), 0, "group membership still requires nameplate threat")
    grouped.threat.percentage = 65
    grouped.nativeStatuses.target, grouped.nativeStatuses.nameplate1 = 1, 1
    grouped:refresh()
    grouped.inGroup = false; grouped:event("GROUP_ROSTER_UPDATE")
    equal(#grouped:visible(), 0, "leaving group hides target even inside an instance")
    equal(#grouped:visible(groupedPlate), 0, "leaving group hides nameplate")
    for _, animation in ipairs(grouped.animations) do equal(animation.playing, false, "leaving group stops pulses") end
end
grouped:set("visibilityMode", "instance")
grouped.inInstance, grouped.instanceType = true, "party"; grouped:refresh(); grouped:text("65%")
equal(#grouped:visible(groupedPlate), 1, "instance mode also works when solo")
grouped:set("visibilityMode", "group")
for _, invalid in ipairs({ secret(true), "yes", 1 }) do
    grouped.inGroup = invalid; grouped:refresh()
    equal(#grouped:visible(), 0, "invalid or restricted membership hides filtered display")
end
grouped.inGroup = true; grouped.engine.rejectGroupQuery = true; grouped:refresh()
equal(#grouped:visible(), 0, "failed membership query hides filtered display")
grouped.env.IsInGroup = nil; grouped:refresh()
equal(#grouped:visible(), 0, "missing membership API hides filtered display")
grouped:set("visibilityMode", "always"); grouped:text("65%")
equal(#grouped:visible(groupedPlate), 1, "always mode works without membership API")
local savedGroup = setup({ visibilityMode = "group" }, false, false, true)
equal(savedGroup:root(), nil, "saved group mode hides solo target on login")
savedGroup.inGroup = true; savedGroup:event("GROUP_ROSTER_UPDATE"); savedGroup:text("65%")
local explicitMode = setup({ visibilityMode = "group", onlyInGroupContent = true })
equal(explicitMode.env.TepiuzThreatDB.visibilityMode, "group", "new preference takes precedence over old checkbox")
local invalidVisibility = setup({ visibilityMode = "invalid" })
equal(invalidVisibility.env.TepiuzThreatDB.visibilityMode, "group", "invalid visibility resets to default")
local oldUnfiltered = setup({ onlyInGroupContent = false })
equal(oldUnfiltered.env.TepiuzThreatDB.visibilityMode, "always", "old disabled filter migrates to always")

-- Resizing covers both templates, pulse copies, pop resets, and pooled labels.
local sized = setup({ preAggroPulse = true, aggroPop = true })
local sizedPlate = sized:addPlate("nameplate1").UnitFrame.children[1]
equal(sized:text("65%").fontSize, 18, "target keeps its default size")
equal(sized:visible(sizedPlate)[1].fontSize, 12, "nameplate keeps its default size")
sized:set("largerText", true)
for _, mode in ipairs({ "percent", "number", "text" }) do
    sized:set("displayMode", mode)
    sized:refresh()
    equal(sized:visible()[1].fontSize, 36, "target size doubles without compounding")
    equal(sized:visible(sizedPlate)[1].fontSize, 24, "nameplate size doubles in every mode")
end
sized.nativeStatuses.target, sized.nativeStatuses.nameplate1 = 1, 1; sized:refresh()
equal(sized:text("High threat").fontSize, 36, "new target pulse uses larger size")
equal(sized:visible(sizedPlate)[1].fontSize, 24, "new nameplate pulse uses larger size")
sized:set("largerText", false)
equal(sized:text("High threat").fontSize, 18, "active target pulse resizes immediately")
equal(sized:visible(sizedPlate)[1].fontSize, 12, "active nameplate pulse resizes immediately")
sized:set("largerText", true)
sized.nativeStatuses.target, sized.nativeStatuses.nameplate1 = 3, 3; sized:refresh(); sized:tick(0.225)
equal(sized:root().scale, 1.6, "pop still enlarges the larger text")
sized:tick(0.225)
equal(sized:root().scale, 1, "pop returns to its resting scale")
equal(sized:text("AGGRO").fontSize, 36, "pop reset retains larger target text")
sized:event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
sized:set("largerText", false)
sized:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
equal(sized:visible(sizedPlate)[1].fontSize, 12, "pooled nameplate applies the latest size")
equal(sized:text("AGGRO").fontSize, 18, "target restores its original size")
local savedSize = setup({ largerText = true })
equal(savedSize:text("65%").fontSize, 36, "saved larger size applied at login")
local savedPlate = savedSize:addPlate("nameplate1").UnitFrame.children[1]
equal(savedSize:visible(savedPlate)[1].fontSize, 24, "new nameplate applies saved larger size")

-- Placement changes reanchor the steady text and pulse copy together.
local placement = setup({ preAggroPulse = true, largerText = true })
local placementParent = placement:addPlate("nameplate1").UnitFrame
local placementRoot = placementParent.children[1]
equal(placement.env.TepiuzThreatDB.nameplatePosition, "right", "placement defaults right")
equal(#placement.settings.nameplatePosition.choices, 4, "four placement choices")
local targetPoint = placement:root().point
local positions = {
    { "left", "RIGHT", "LEFT", -8, 0, "RIGHT" },
    { "top", "BOTTOM", "TOP", 0, 8, "CENTER" },
    { "right", "LEFT", "RIGHT", 8, 0, "LEFT" },
    { "bottom", "TOP", "BOTTOM", 0, -8, "CENTER" },
}
for pass = 1, 2 do
    placement.nativeStatuses.nameplate1 = pass == 1 and 0 or 1
    placement:refresh()
    for i, position in ipairs(positions) do
        equal(placement.settings.nameplatePosition.choices[i][1], position[1], "placement choice order")
        placement:set("nameplatePosition", position[1])
        equal(placementRoot.point[1], position[2], "text grows away from plate")
        equal(placementRoot.point[2], position[1] == "right" and placementParent.PlayerLevelDiffFrame or placementParent.HealthBarsContainer, "placement anchor")
        equal(placementRoot.point[3], position[3], "correct edge of plate")
        equal(placementRoot.point[4], position[4], "horizontal gap")
        equal(placementRoot.point[5], position[5], "vertical gap")
        local text = placement:visible(placementRoot)[1]
        equal(text.point[1], position[2], "visible copy follows selected edge")
        equal(text.justify, position[6], "top and bottom text centered")
        equal(text.fontSize, 24, "placement retains larger text")
        equal(placement:root().point, targetPoint, "target position unchanged")
        for _, display in ipairs(placementRoot.children) do
            equal(display.children[1].children[1].point[1], position[2], "all existing copies share anchor")
        end
    end
end
placement:event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
placement:set("nameplatePosition", "top")
placement:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
equal(placementParent.children[1], placementRoot, "placement reuses pooled label")
equal(placementRoot.point[1], "BOTTOM", "reused label applies current placement")
for _, position in ipairs(positions) do
    local savedPlacement = setup({ nameplatePosition = position[1] })
    local root = savedPlacement:addPlate("nameplate1").UnitFrame.children[1]
    equal(root.point[1], position[2], "saved placement applies to new plates")
end
local invalidPlacement = setup({ nameplatePosition = "invalid" })
equal(invalidPlacement.env.TepiuzThreatDB.nameplatePosition, "right", "invalid placement resets to right")

-- Vertical plate placement follows visible name/cast regions and falls back
-- when those regions disappear, including on a reused nameplate.
local nameRegion = { shown = true }
function nameRegion:IsForbidden() return false end
function nameRegion:IsVisible() return self.shown end
local castRegion = { shown = true, IsForbidden = nameRegion.IsForbidden, IsVisible = nameRegion.IsVisible }
placementParent.name = nameRegion
placementParent.CastBarsContainer = { castBar = castRegion }
placement:set("nameplatePosition", "top")
equal(placementRoot.point[2], nameRegion, "top clears the visible unit name")
nameRegion.shown = false; placement:refresh()
equal(placementRoot.point[2], placementParent.HealthBarsContainer, "hidden name uses health bar")
placement:set("nameplatePosition", "bottom")
equal(placementRoot.point[2], castRegion, "bottom clears visible cast bar")
castRegion.shown = false; placement:refresh()
equal(placementRoot.point[2], placementParent.HealthBarsContainer, "hidden cast bar uses health bar")

-- Target placement is independent and moves both steady and pulsing copies.
equal(placement.env.TepiuzThreatDB.targetPosition, "right", "target defaults right")
equal(placement.settings.targetPosition.choices[3][2], "Right (Default)", "target default marked")
equal(placement.settings.nameplatePosition.choices[3][2], "Right (Default)", "nameplate default marked")
equal(placement.settings.displayMode.choices[1][2], "Percentage (Default)", "display default marked")
equal(placement.settings.visibilityMode.choices[1][2], "While in a party or raid (Default)", "visibility default marked")
local platePoint = placementRoot.point
for pass = 1, 2 do
    placement.nativeStatuses.target = pass == 1 and 0 or 1
    placement:refresh()
    for _, position in ipairs(positions) do
        placement:set("targetPosition", position[1])
        local root = placement:root()
        equal(root.point[1], position[2], "target text edge")
        equal(root.point[2], placement.env.TargetFrame, "target anchors to full frame")
        equal(root.point[3], position[3], "target frame edge")
        equal(root.point[4], position[4], "target horizontal gap")
        equal(root.point[5], position[5] + (position[1] == "top" and -19 or position[1] == "bottom" and 7 or 0), "target gap excludes invisible padding")
        equal(placement:text("65%").justify, position[6], "target text alignment")
        equal(placement:text("65%").fontSize, 36, "target keeps larger font")
        for _, display in ipairs(root.children) do
            equal(display.children[1].children[1].point[1], position[2], "target pulse and base move together")
        end
        equal(placementRoot.point, platePoint, "target placement leaves nameplate unchanged")
    end
end
for _, position in ipairs(positions) do
    local savedTarget = setup({ targetPosition = position[1] })
    equal(savedTarget:root().point[1], position[2], "saved target placement applied")
end
local invalidTarget = setup({ targetPosition = "invalid" })
equal(invalidTarget.env.TepiuzThreatDB.targetPosition, "right", "invalid target placement defaults right")
local newSolo = setup(nil, false, false, true)
equal(newSolo:root(), nil, "new default hides solo outdoor threat")
newSolo.inGroup = true; newSolo:event("GROUP_ROSTER_UPDATE"); newSolo:text("65%")
local savedAlways = setup({ visibilityMode = "always", nameplatePosition = "left" }, false, false, true)
savedAlways:text("65%")
equal(savedAlways.env.TepiuzThreatDB.nameplatePosition, "left", "existing placement preserved")

local plates = setup({ aggroPop = true, displayMode = "text", preAggroPulse = true, nameplatePosition = "right" })
plates.platePresent = true; plates:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local plateRoot = plates.plate.UnitFrame.children[1]
equal(plates:visible(plateRoot)[1].text, "Low threat", "nameplate rendering")
local auras, list, icon = { shown = true }, { shown = true }, { shown = true }
function auras:IsForbidden() return false end; function auras:IsVisible() return self.shown end
list.IsForbidden, list.IsVisible = auras.IsForbidden, auras.IsVisible
icon.IsForbidden, icon.IsVisible = auras.IsForbidden, auras.IsVisible
function list:GetChildren() return icon end
auras.CrowdControlListFrame = list; plates.plate.UnitFrame.AurasFrame = auras
plates.queries = 0; plates:event("UNIT_AURA", "nameplate1"); plates:tick(0.01)
equal(plateRoot.point[2], list, "label moves past control icons")
equal(plates.queries, 0, "aura layout does not query threat")
plates:set("nameplatePosition", "top")
plates:event("UNIT_AURA", "nameplate1"); plates:tick(0.01)
equal(plateRoot.point[2], plates.plate.UnitFrame.HealthBarsContainer, "centered placement stays on health bar with icons")
plates:set("nameplatePosition", "right")
icon.shown = false; plates:event("UNIT_AURA", "nameplate1"); plates:tick(0.01)
equal(plateRoot.point[2], plates.plate.UnitFrame.PlayerLevelDiffFrame, "anchor returns after icons hide")
plates:event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
equal(#plates:visible(plateRoot), 0, "removed plate hidden")
plates.nativeStatuses.nameplate1 = 3; plates.threat.percentage = 100; plates:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
equal(plates.plate.UnitFrame.children[1], plateRoot, "pooled label reused")
plates:tick(0.05); equal(plateRoot.scale, 1, "pooled label does not inherit aggro transition")
plates:event("PLAYER_LEAVING_WORLD"); equal(#plates:visible(plateRoot), 0, "world exit clears plates")
equal(#plates:visible(), 0, "world exit clears target")

-- Reproduce the reported mismatch: public target 65%, restricted nameplate
-- 65%, both state 0. Then switch targets among several independent enemies.
local mixed = setup({ displayMode = "text", aggroPop = true, preAggroPulse = true })
local mobs = {
    { percentage = 65, status = 0, text = "Low threat" },
    { percentage = 95, status = 1, text = "High threat" },
    { percentage = 100, status = 2, text = "AGGRO" },
    { percentage = 100, status = 3, text = "AGGRO" },
}
for i, mob in ipairs(mobs) do
    local unit = "nameplate" .. i
    mixed.threats[unit] = { tanking = secret(i < 3), percentage = secret(mob.percentage) }
    mixed.nativeStatuses[unit] = mob.status
    mob.root = mixed:addPlate(unit).UnitFrame.children[1]
end
for _, selected in ipairs(mobs) do
    mixed.threat = { percentage = selected.percentage, tanking = false }
    mixed.nativeStatuses.target = selected.status
    mixed:event("PLAYER_TARGET_CHANGED")
    local targetText = mixed:text(selected.text)
    for _, mob in ipairs(mobs) do
        local text = mixed:visible(mob.root)[1]
        equal(text.text, mob.text, "each enemy retains its own state across target changes")
        if mob == selected then
            for i = 1, 3 do equal(text.color[i], targetText.color[i], "same mob has matching colors") end
        end
        equal(mob.root.children[1].alpha, mob.status == 1 and 0 or 1, "each enemy pulses by its own state")
        equal(mob.root.scale, 1, "target changes do not pop nameplates")
    end
end
mixed.unitExists.target = false; mixed:event("PLAYER_TARGET_CHANGED")
equal(#mixed:visible(), 0, "no target hides only the target label")
for _, mob in ipairs(mobs) do
    equal(mixed:visible(mob.root)[1].text, mob.text, "untargeted mobs keep their own text")
end
mixed.unitExists.target = true; mixed:event("PLAYER_TARGET_CHANGED")
mixed.nativeStatuses.nameplate1 = nil; mixed:refresh()
equal(#mixed:visible(mobs[1].root), 0, "missing nameplate state hides only that enemy")
mixed:text("AGGRO")
equal(mixed:visible(mobs[2].root)[1].text, "High threat", "missing state does not suppress other plates")
mixed.nativeStatuses.nameplate1 = 0; mixed:refresh()
for _, mode in ipairs({ "number", "percent" }) do
    mixed:set("displayMode", mode)
    for _, mob in ipairs(mobs) do
        local text = mixed:visible(mob.root)[1]
        equal(text.text, tostring(mob.percentage) .. (mode == "percent" and "%" or ""), "restricted numbers unchanged")
        for i = 1, 3 do equal(text.color[i], states[mob.status + 1][3][i], "numeric modes share state colors") end
    end
end
mixed:set("displayMode", "text"); mixed:set("colorGradient", false)
for _, mob in ipairs(mobs) do
    local text = mixed:visible(mob.root)[1]
    equal(text.text, mob.text, "white preference preserves text mode")
    for i = 1, 3 do equal(text.color[i], 1, "white preference applies to every mob") end
end
mixed:set("colorGradient", true)
mixed.nativeStatuses.nameplate1 = 3; mixed:refresh(); mixed:tick(0.225)
equal(mobs[1].root.scale, 1.6, "public state transition pops only its own mob")
equal(mobs[2].root.scale, 1, "unrelated enemy does not pop")
equal(mixed:root().scale, 1, "unrelated target does not pop")
equal(#mixed.messages, 0, "normal rendering produces no chat output")

-- Missing or unusable states cannot produce invented text/colors. Numeric
-- display with explicit white remains possible without a public state.
local unavailable = setup({ displayMode = "text", preAggroPulse = true })
unavailable.platePresent = true; unavailable:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local unaffectedRoot = unavailable.plate.UnitFrame.children[1]
for _, value in ipairs({ secret(1), -1, 4, 0.5, "1", false }) do
    unavailable.nativeStatuses.target = value; unavailable:refresh()
    equal(#unavailable:visible(), 0, "invalid or restricted status hides text")
    equal(unavailable:visible(unaffectedRoot)[1].text, "Low threat", "unavailable target does not affect nameplate")
end
unavailable.nativeStatuses.target = nil; unavailable:refresh()
equal(#unavailable:visible(), 0, "absent state hides text")
unavailable:set("colorGradient", false)
equal(#unavailable:visible(), 0, "text mode never switches to numbers")
unavailable:set("displayMode", "number"); unavailable:text("65")
unavailable:set("colorGradient", true)
equal(#unavailable:visible(), 0, "numeric mode cannot invent an enabled color")
unavailable.nativeStatuses.target = 1; unavailable:refresh(); unavailable:text("65")
unavailable.engine.rejectStateQuery = true; unavailable:refresh()
equal(#unavailable:visible(), 0, "rejected state query hides dependent presentation")
unavailable.engine.rejectStateQuery = false; unavailable:refresh(); unavailable:text("65")
unavailable.env.UnitThreatSituation = nil; unavailable:refresh()
equal(#unavailable:visible(), 0, "missing state API hides dependent presentation")
unavailable:set("colorGradient", false); unavailable:text("65")

-- No percentage is ordinary absence, even in combat with a native state.
local absent = setup({ displayMode = "text", preAggroPulse = true })
absent.platePresent = true; absent:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local absentRoot = absent.plate.UnitFrame.children[1]
absent.threat.percentage = nil; absent:refresh()
equal(#absent:visible(), 0, "missing target data hides label in combat")
equal(#absent:visible(absentRoot), 0, "missing nameplate data hides label in combat")
equal(#absent.messages, 0, "missing data emits no failure log")
absent.threat.percentage = 65
absent.nativeStatuses.target, absent.nativeStatuses.nameplate1 = nil, nil; absent:refresh()
equal(#absent.messages, 0, "missing state is expected absence")
absent.nativeStatuses.target, absent.nativeStatuses.nameplate1 = 0, 0
absent.threat.percentage = 0; absent:refresh(); absent:text("Low threat")
absent:set("displayMode", "percent"); absent:text("0%")
equal(absent:visible(absentRoot)[1].text, "0%", "actual zero remains visible")

-- Rendering failures remain quiet and recover without changing settings.
local quiet = setup({ displayMode = "text" })
quiet.threat.percentage = secret(73.54321)
quiet.engine.errorObject = secret("private exception")
for _, failure in ipairs({ "rejectText", "rejectColor", "rejectStateQuery" }) do
    quiet.engine[failure] = true; quiet:refresh()
    equal(#quiet:visible(), 0, "failed rendering hides the affected label")
    equal(#quiet.messages, 0, "failures do not print chat messages or exception contents")
    quiet.engine[failure] = false; quiet:refresh(); quiet:text("Low threat")
end

local commands = setup({})
equal(commands.env.SLASH_TEPIUZTHREAT1, "/tthreat", "short command registered")
equal(commands.env.SLASH_TEPIUZTHREAT2, "/tepiuzthreat", "long command shares handler")
commands.env.SlashCmdList.TEPIUZTHREAT("")
equal(commands.openedCategory, 42, "command opens registered options category")
equal(#commands.messages, 0, "opening options does not print chat messages")
commands.env.SlashCmdList.TEPIUZTHREAT()
equal(commands.optionsOpened, 2, "command without arguments opens options")
for _, oldCommand in ipairs({ "debug", "debug on", "debug off" }) do
    commands.env.SlashCmdList.TEPIUZTHREAT(oldCommand)
end
equal(commands.optionsOpened, 5, "removed debug subcommands simply open options")
equal(#commands.messages, 0, "removed debug subcommands produce no diagnostics")
commands.messages = {}
commands.env.Settings.OpenToCategory = nil
commands.env.SlashCmdList.TEPIUZTHREAT("")
equal(#commands.messages, 1, "missing options API gives navigation help")
commands.env.Settings.OpenToCategory = function() error("cannot open settings") end
commands.env.SlashCmdList.TEPIUZTHREAT("")
equal(#commands.messages, 2, "rejected settings opening gives navigation help")
print("Passed " .. checks .. " checks for threat display, restricted-value paths, options, alerts, and lifecycle.")
