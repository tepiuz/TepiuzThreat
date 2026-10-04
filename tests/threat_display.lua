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

local function setup(saved, noCurves, noDropdown)
    local e = { frames = {}, animations = {}, messages = {}, settings = {}, inCombat = true, queries = 0,
        threats = {}, nativeStatuses = {}, plates = {},
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
    function methods:GetFont() return "GameFont.ttf", self.font == "GameFontHighlightLarge" and 18 or 12 end
    function methods:Hide() self.shown = false end
    function methods:Show() self.shown = true end
    function methods:IsForbidden() return self.forbidden or false end
    function methods:IsVisible() return self.shown end
    function methods:GetChildren() return unpackValues(self.children) end
    function methods:CreateFontString(_, _, font)
        if e.engine.rejectNextFont then e.engine.rejectNextFont = false; error("font creation rejected") end
        return node(self, font)
    end
    function methods:SetText(value) self.text = engineValue(value) end
    function methods:SetFormattedText(format, value) self.text = string.format(format, engineValue(value)) end
    function methods:SetTextColor(r, g, b) self.color = { engineValue(r), engineValue(g), engineValue(b) } end
    function methods:SetAlpha(value) self.alpha = engineValue(value) end
    function methods:SetAlphaFromBoolean(value, yes, no) self.alpha = engineValue(engineValue(value) and yes or no) end
    function methods:SetScale(value)
        if e.engine.rejectScale then error("scale mutation rejected") end
        self.scale = engineValue(value)
    end
    function methods:SetScript(event, callback) self[event] = callback end
    function methods:RegisterEvent() end
    function methods:GetUnit() return self.unit end
    function methods:CreateAnimationGroup()
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
        function group:Play() self.playing = true; self.plays = self.plays + 1 end
        function group:Stop() self.playing = false end
        function group:IsPlaying() error("animation progress forbidden") end
        return group
    end
    local env = setmetatable({ TepiuzThreatDB = saved, SlashCmdList = {}, Enum = { LuaCurveType = { Step = 1, Linear = 0 } } }, { __index = _G })
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
    e.plate = plate
    e.plates.nameplate1 = plate
    function e:addPlate(unit)
        local extra = node()
        extra.unit, extra.UnitFrame = unit, node()
        extra.UnitFrame.PlayerLevelDiffFrame = node()
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
    env.UnitExists = function() return e.exists == nil and true or e.exists end
    env.UnitCanAttack = function() return e.hostile == nil and true or e.hostile end
    env.UnitDetailedThreatSituation = function(_, unit)
        e.queries = e.queries + 1
        local threat = e.threats[unit] or e.threat
        return threat.tanking, 0, threat.percentage
    end
    env.UnitThreatSituation = function(_, unit) return e.nativeStatuses[unit] end
    env.GetThreatStatusColor = function(status)
        local colors = { [0] = { 1, 1, 1 }, { 1, 1, 0 }, { 1, 0.6, 0 }, { 1, 0, 0 } }
        return unpackValues(colors[status])
    end
    env.InCombatLockdown = function() return e.inCombat end
    env.GetBuildInfo = function() return "1.60.1", "test", "date", 16001 end
    env.GetAddOnMetadata = function() return "test" end
    env.print = function(...)
        local line = {}
        for i = 1, select("#", ...) do line[i] = tostring(select(i, ...)) end
        e.messages[#e.messages + 1] = table.concat(line, " ")
    end
    env.CreateColor = function(r, g, b, a) return { r, g, b, a } end
    local function curve()
        local c = { points = {} }
        function c:SetType(value) self.kind = value end
        function c:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
        function c:Evaluate(value)
            if e.engine.rejectBands then error("curve evaluation rejected") end
            if e.engine.rejectSecretCurves and restricted(value) then error("restricted curve input rejected") end
            local x, y = engineValue(value), self.points[1][2]
            for _, point in ipairs(self.points) do if x >= point[1] then y = point[2] else break end end
            return restricted(value) and secret(y) or y
        end
        function c:EvaluateUnpacked(value)
            if e.engine.rejectColor then error("color evaluation rejected") end
            if e.engine.rejectSecretCurves and restricted(value) then error("restricted curve input rejected") end
            local x, points = engineValue(value), self.points
            local lo, hi = points[1], points[#points]
            for i = 2, #points do
                if x <= points[i][1] then lo, hi = points[i - 1], points[i]; break end
            end
            local t = math.max(0, math.min(1, (x - lo[1]) / (hi[1] - lo[1])))
            local values = {}
            for i = 1, 4 do
                local v = lo[2][i] + (hi[2][i] - lo[2][i]) * t
                values[i] = restricted(value) and secret(v) or v
            end
            return unpackValues(values)
        end
        return c
    end
    if not noCurves then env.C_CurveUtil = { CreateCurve = curve, CreateColorCurve = curve } end
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
    if not noDropdown then env.Settings.CreateDropdown = function(_, _, getter) e.choices = getter() end end
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

local e = setup({ onlyInCombat = false, showOnNameplates = false })
equal(e.env.TepiuzThreatDB.onlyInCombat, false, "existing option preserved")
equal(e.env.TepiuzThreatDB.aggroPop, false, "pop defaults off")
equal(e.env.TepiuzThreatDB.preAggroPulse, false, "pulse defaults off")
equal(#e.choices, 3, "three dropdown modes")
e:text("65%")
e:set("displayMode", "number"); e:text("65")
e:set("displayMode", "text"); e:text("Medium threat")
for _, test in ipairs({ { 0, "No threat" }, { 0.49, "No threat" }, { 0.5, "Low threat" }, { 49.99, "Low threat" }, { 50, "Medium threat" }, { 79.99, "Medium threat" }, { 80, "High threat" }, { 99.6, "High threat" }, { 100, "High threat" } }) do
    e.threat.percentage = secret(test[1]); e.threat.tanking = secret(false); e:refresh(); e:text(test[2])
end
e.threat.tanking = secret(true); e:refresh(); e:text("AGGRO")
e:set("displayMode", "percent"); e:text("100%")
e:set("colorGradient", false)
local white = e:text("100%").color
equal(white[1], 1); equal(white[2], 1); equal(white[3], 1)
e:set("colorGradient", true)
local red = e:text("100%").color
equal(red[1], 1); equal(red[2], 0.294); equal(red[3], 0.294)
e.threat.percentage = nil; e:refresh(); equal(#e:visible(), 0, "missing data hides label")
e.threat.percentage = 0; e.threat.tanking = false; e:refresh(); e:text("0%")
e.hostile = false; e:refresh(); equal(#e:visible(), 0, "friendly target hidden")
e.hostile = true; e:refresh()
e.exists = secret(false); e:refresh(); equal(#e:visible(), 0, "restricted eligibility hidden")
e.exists = true; e:refresh()

e:set("aggroPop", true)
e.threat.tanking = true; e.threat.percentage = 100; e:refresh(); e:tick(0.225)
equal(e:root().scale, 1.6, "aggro transition pops")
e:tick(0.225); equal(e:root().scale, 1, "pop returns to normal")
e:refresh(); e:tick(0.05); equal(e:root().scale, 1, "steady aggro does not repeat pop")
e.threat.tanking = false; e:refresh(); e.threat.tanking = true; e:event("PLAYER_TARGET_CHANGED")
e:tick(0.05); equal(e:root().scale, 1, "target change resets baseline")
e.threat.tanking = false; e:refresh(); e.threat.tanking = secret(true); e:refresh(); e:tick(0.1)
equal(e:root().scale, 1, "restricted aggro cannot pop")

local pulse = setup({ preAggroPulse = true, displayMode = "text" })
pulse.threat.percentage = secret(90); pulse.threat.tanking = secret(false); pulse:refresh(); pulse:text("High threat")
equal(pulse.animations[1].loop, "BOUNCE"); equal(pulse.animations[1].animation.from, 0.30)
equal(pulse.animations[1].animation.to, 1); equal(pulse.animations[1].animation.duration, 0.40)
local base, warning = pulse:root().children[1], pulse:root().children[2]
equal(base.alpha, 0, "normal copy hidden during warning"); equal(warning.alpha, 1, "warning copy enabled")
pulse:refresh(); equal(pulse.animations[1].plays, 1, "refresh does not restart pulse")
pulse:set("displayMode", "number"); pulse:text("90")
pulse.threat.percentage = secret(89.99); pulse:refresh(); pulse:text("90")
equal(base.alpha, 1, "rounded 90 below threshold stays steady"); equal(warning.alpha, 0)
pulse.threat.percentage = secret(100); pulse.threat.tanking = secret(true); pulse:refresh(); pulse:text("100")
equal(base.alpha, 1, "aggro stops warning"); equal(warning.alpha, 0)
pulse:set("displayMode", "text"); pulse:text("AGGRO")
pulse:set("preAggroPulse", false); equal(pulse.animations[1].playing, false, "disabling stops animation")
pulse:set("preAggroPulse", true); pulse.inCombat = false; pulse:event("PLAYER_REGEN_ENABLED")
equal(#pulse:visible(), 0, "out of combat hidden"); equal(pulse.animations[1].playing, false, "hiding stops animation")

local fallback = setup({ displayMode = "text", preAggroPulse = true }, true)
fallback.threat.percentage = secret(95); fallback:refresh(); fallback:text("95%")
local rejected = setup({ displayMode = "text", preAggroPulse = true })
rejected.engine.rejectBands = true; rejected.engine.rejectColor = true
rejected.threat.percentage = secret(95); rejected:refresh()
equal(rejected:text("95%").color[1], 1, "rejected styling retains plain number")
local fontFailure = setup()
fontFailure.engine.rejectNextFont = true; fontFailure:set("displayMode", "text")
fontFailure:text("65%")
fontFailure:refresh(); fontFailure:text("Medium threat")
fontFailure.engine.rejectNextFont = true; fontFailure:set("preAggroPulse", true)
fontFailure:text("Medium threat")
fontFailure:refresh(); fontFailure:text("Medium threat")
local scaleFailure = setup({ aggroPop = true })
scaleFailure.engine.rejectScale = true; scaleFailure.threat.tanking = true; scaleFailure.threat.percentage = 100
scaleFailure:refresh(); scaleFailure:tick(0.15); scaleFailure:text("100%")
scaleFailure:event("PLAYER_TARGET_CHANGED"); scaleFailure:text("100%")
local malformed = setup({ displayMode = "invalid", aggroPop = "yes", showOnTarget = false })
equal(malformed.env.TepiuzThreatDB.displayMode, "percent", "invalid mode reset")
equal(malformed.env.TepiuzThreatDB.aggroPop, false, "invalid boolean reset")
equal(malformed.env.TepiuzThreatDB.showOnTarget, false, "saved hidden target preserved")
equal(malformed:root(), nil, "disabled target not created")
local settingsFallback = setup(nil, false, true)
settingsFallback:text("65%")
equal(settingsFallback.settings.preAggroPulse ~= nil, true, "other settings survive missing dropdown")

local plates = setup({ aggroPop = true, displayMode = "text", preAggroPulse = true })
plates.platePresent = true; plates:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local plateRoot = plates.plate.UnitFrame.children[1]
equal(plates:visible(plateRoot)[1].text, "Medium threat", "nameplate rendering")
local auras, list, icon = { shown = true }, { shown = true }, { shown = true }
function auras:IsForbidden() return false end; function auras:IsVisible() return self.shown end
list.IsForbidden, list.IsVisible = auras.IsForbidden, auras.IsVisible
icon.IsForbidden, icon.IsVisible = auras.IsForbidden, auras.IsVisible
function list:GetChildren() return icon end
auras.CrowdControlListFrame = list; plates.plate.UnitFrame.AurasFrame = auras
plates.queries = 0; plates:event("UNIT_AURA", "nameplate1"); plates:tick(0.01)
equal(plateRoot.point[2], list, "label moves past control icons")
equal(plates.queries, 0, "aura layout does not query threat")
icon.shown = false; plates:event("UNIT_AURA", "nameplate1"); plates:tick(0.01)
equal(plateRoot.point[2], plates.plate.UnitFrame.PlayerLevelDiffFrame, "anchor returns after icons hide")
plates:event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
equal(#plates:visible(plateRoot), 0, "removed plate hidden")
plates.threat.tanking = true; plates.threat.percentage = 100; plates:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
equal(plates.plate.UnitFrame.children[1], plateRoot, "pooled label reused")
plates:tick(0.05); equal(plateRoot.scale, 1, "pooled label does not inherit aggro transition")
plates:event("PLAYER_LEAVING_WORLD"); equal(#plates:visible(plateRoot), 0, "world exit clears plates")
equal(#plates:visible(), 0, "world exit clears target")

-- Model the reported difference: target values are readable, but nameplate
-- percentages are restricted and their curve evaluations are rejected.
local mixed = setup({ displayMode = "text", aggroPop = true, preAggroPulse = true })
mixed.engine.rejectSecretCurves = true
mixed.threats.nameplate1 = { tanking = secret(false), percentage = secret(95) }
mixed.nativeStatuses.nameplate1 = 1
mixed.platePresent = true; mixed:event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local mixedRoot = mixed.plate.UnitFrame.children[1]
mixed:text("Medium threat")
equal(mixed:visible(mixedRoot)[1].text, "High threat", "restricted nameplate retains text mode")
equal(mixed:visible(mixedRoot)[1].color[2], 1, "nameplate uses native warning color")
equal(mixedRoot.children[1].alpha, 0, "nameplate base hidden for native warning")
equal(mixedRoot.children[2].alpha, 1, "nameplate pulse visible despite forbidden animation progress")
local second = mixed:addPlate("nameplate2")
mixed.threats.nameplate2 = { tanking = false, percentage = 30 }
mixed.nativeStatuses.nameplate2 = 0; mixed:refresh()
local secondRoot = second.UnitFrame.children[1]
equal(mixed:visible(secondRoot)[1].text, "Low threat", "second nameplate has independent band")
equal(secondRoot.children[1].alpha, 1, "safe second plate does not pulse")
equal(secondRoot.children[2].alpha, 0, "safe second plate warning hidden")
mixed.threats.nameplate2.percentage = secret(30); mixed:refresh()
equal(mixed:visible(secondRoot)[1].text, "Low threat", "native low state retains nameplate text")
equal(mixed:visible(secondRoot)[1].color[1], 0.949, "native low state uses neutral color")
mixed.threats.nameplate2.percentage = 30; mixed:refresh()
mixed.threats.nameplate1 = { tanking = secret(true), percentage = secret(100) }
mixed.nativeStatuses.nameplate1 = 3; mixed:refresh(); mixed:tick(0.225)
equal(mixedRoot.scale, 1.6, "public native status enables nameplate pop")
equal(mixed:root().scale, 1, "nameplate aggro does not pop target")
equal(secondRoot.scale, 1, "nameplate aggro does not pop another mob")
equal(mixed:visible(mixedRoot)[1].text, "AGGRO", "native aggro overrides fallback band")
equal(mixedRoot.children[1].alpha, 1, "aggro returns nameplate to steady display")
equal(mixedRoot.children[2].alpha, 0, "aggro suppresses nameplate pulse")
mixed:tick(0.225); equal(mixedRoot.scale, 1, "nameplate pop returns to normal")
mixed:set("displayMode", "number"); mixed:text("65")
equal(mixed:visible(mixedRoot)[1].text, "100", "number-only setting applies to first plate")
equal(mixed:visible(secondRoot)[1].text, "30", "number-only setting applies to second plate")
mixed:set("colorGradient", false)
equal(mixed:visible(mixedRoot)[1].color[3], 1, "disabling colors applies to native fallback")
equal(mixed:visible(secondRoot)[1].color[1], 1, "disabling colors applies to percentage color")
mixed:set("displayMode", "percent"); mixed:text("65%")
equal(mixed:visible(mixedRoot)[1].text, "100%", "percentage setting applies to first plate")
equal(mixed:visible(secondRoot)[1].text, "30%", "percentage setting applies to second plate")
mixed:set("displayMode", "text"); mixed:set("colorGradient", true)
mixed.env.SlashCmdList.TEPIUZTHREAT("debug")
equal(table.concat(mixed.messages, "\n"):find("state fallbacks: 1", 1, true) ~= nil, true, "diagnostics count nameplate fallbacks")
mixed.nativeStatuses.nameplate1 = secret(3); mixed:refresh()
equal(mixed:visible(mixedRoot)[1].text, "100%", "restricted native state is never inspected")

e.env.SlashCmdList.TEPIUZTHREAT("debug")
equal(table.concat(e.messages, "\n"):find("restricted aggro changes seen: yes", 1, true) ~= nil, true, "diagnostics report restricted pop")
local commands = setup({})
equal(commands.env.SLASH_TEPIUZTHREAT1, "/tthreat", "short command registered")
equal(commands.env.SLASH_TEPIUZTHREAT2, "/tepiuzthreat", "long command shares handler")
commands.env.SlashCmdList.TEPIUZTHREAT("")
equal(commands.openedCategory, 42, "command opens registered options category")
equal(#commands.messages, 0, "opening options does not print diagnostics")
commands.env.SlashCmdList.TEPIUZTHREAT()
equal(commands.optionsOpened, 2, "command without arguments opens options")
commands.env.SlashCmdList.TEPIUZTHREAT(" DEBUG ")
equal(commands.optionsOpened, 2, "explicit diagnostics do not open options")
equal(table.concat(commands.messages, "\n"):find("Failures:", 1, true) ~= nil, true, "explicit diagnostics retained")
commands.messages = {}
commands.env.Settings.OpenToCategory = nil
commands.env.SlashCmdList.TEPIUZTHREAT("")
equal(#commands.messages, 1, "missing options API gives navigation help")
commands.env.Settings.OpenToCategory = function() error("cannot open settings") end
commands.env.SlashCmdList.TEPIUZTHREAT("")
equal(#commands.messages, 2, "rejected settings opening gives navigation help")
print("Passed " .. checks .. " checks for threat display, restricted-value paths, options, alerts, and lifecycle.")
