local ADDON, ns = ...

local panel = CreateFrame("Frame")
panel.name = "Unbuffed"
local category          -- modern Settings category, when the client has one
local refreshers = {}   -- run on every panel show, to resync widgets with the db
local rebuildCustomList -- forward decl

--------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------
local function Header(text, x, y)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Check(label, x, y, get, set, tooltip)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); ns.RefreshAll() end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end

local sliderCount = 0
local function Slider(label, x, y, lo, hi, step, get, set, fmt)
    sliderCount = sliderCount + 1
    local s = CreateFrame("Slider", "UnbuffedSlider" .. sliderCount, panel, "OptionsSliderTemplate")
    s:SetWidth(190)
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    _G[s:GetName() .. "Low"]:SetText(tostring(lo))
    _G[s:GetName() .. "High"]:SetText(tostring(hi))
    local text = _G[s:GetName() .. "Text"]
    local function paint(v) text:SetText(label .. ": " .. (fmt and fmt(v) or tostring(v))) end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        set(v); paint(v); ns.RefreshAll()
    end)
    refreshers[#refreshers + 1] = function() local v = get(); s:SetValue(v); paint(v) end
    return s
end

local SIDES = { { "Right of the nameplate", "RIGHT" }, { "Left of the nameplate", "LEFT" } }

-- Midnight removed UIDropDownMenu; there the widget is a DropdownButton driven by
-- MenuUtil. Keep the legacy branch for the older Classic clients.
local function SideDropdown(x, y)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText("Icon row position")

    if MenuUtil and MenuUtil.CreateRadioMenu then
        local dd = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT", x, y - 18)
        dd:SetWidth(190)
        MenuUtil.CreateRadioMenu(dd,
            function(value) return value == ns.db.side end,
            function(value) ns.db.side = value; ns.RefreshAll() end,
            unpack(SIDES))
        refreshers[#refreshers + 1] = function() dd:GenerateMenu() end
        return dd
    end

    local dd = CreateFrame("Frame", "UnbuffedSideDrop", panel, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y - 18)
    UIDropDownMenu_SetWidth(dd, 170)
    local function setText()
        for _, o in ipairs(SIDES) do
            if o[2] == ns.db.side then UIDropDownMenu_SetText(dd, o[1]); return end
        end
    end
    UIDropDownMenu_Initialize(dd, function(_, level)
        for _, o in ipairs(SIDES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = o[1], (o[2] == ns.db.side)
            info.func = function() ns.db.side = o[2]; setText(); CloseDropDownMenus(); ns.RefreshAll() end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    refreshers[#refreshers + 1] = setText
    return dd
end

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Unbuffed")

local blurb = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
blurb:SetPoint("TOPLEFT", 16, -38)
blurb:SetWidth(520)
blurb:SetJustifyH("LEFT")
blurb:SetText("Shows a small icon beside a friendly player's nameplate for each tracked buff they are |cffffd100missing|r. A fully buffed player shows nothing.")

Check("Enabled", 18, -70, function() return ns.db.enabled end, function(v) ns.db.enabled = v end)

Header("Buffs to flag", 16, -104)

-- Presets, two columns.
for i, preset in ipairs(ns.PRESETS) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    Check(preset.label, 18 + col * 250, -128 - row * 26,
        function()
            local e = ns.FindTracked(preset.key)
            return e and e.enabled
        end,
        function(on)
            if on then
                ns.AddTracked({
                    key = preset.key, label = preset.label, icon = preset.icon,
                    names = { unpack(preset.names) },
                })
            else
                ns.RemoveTracked(preset.key)
            end
            if rebuildCustomList then rebuildCustomList() end
        end,
        "Matched by name, so every rank counts -- and so do the group versions ("
            .. table.concat(preset.names, ", ") .. ").")
end

local presetRows = math.ceil(#ns.PRESETS / 2)
local customY = -128 - presetRows * 26 - 18

Header("Add another buff", 16, customY)

local addBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
addBox:SetSize(200, 22)
addBox:SetPoint("TOPLEFT", 22, customY - 26)
addBox:SetAutoFocus(false)

local addHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
addHint:SetPoint("TOPLEFT", 22, customY - 52)
addHint:SetText("Buff name or spell ID. A name matches every rank; an ID also survives combat.")

local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
addBtn:SetSize(70, 22)
addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
addBtn:SetText("Add")

local function doAdd()
    local text = (addBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    local entry, err = ns.EntryFromInput(text)
    if not entry then ns.Print(err); return end
    ns.AddTracked(entry)
    addBox:SetText("")
    addBox:ClearFocus()
    if rebuildCustomList then rebuildCustomList() end
    ns.RefreshAll()
    ns.Print("now flagging |cffffd100" .. entry.label .. "|r.")
end
addBtn:SetScript("OnClick", doAdd)
addBox:SetScript("OnEnterPressed", doAdd)
addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Custom (non-preset) entries, each with a remove button.
local customRows = {}
local customListY = customY - 76

local emptyFS = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
emptyFS:SetPoint("TOPLEFT", 22, customListY)
emptyFS:SetText("No custom buffs added.")

local PRESET_KEYS = {}
for _, p in ipairs(ns.PRESETS) do PRESET_KEYS[p.key] = true end

rebuildCustomList = function()
    for _, r in ipairs(customRows) do r:Hide() end
    local shown = 0
    for _, e in ipairs(ns.db.tracked) do
        if not PRESET_KEYS[e.key] then
            shown = shown + 1
            local r = customRows[shown]
            if not r then
                r = CreateFrame("Frame", nil, panel)
                r:SetSize(400, 20)
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(16, 16)
                r.icon:SetPoint("LEFT", 0, 0)
                r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                r.label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                r.del = CreateFrame("Button", nil, r)
                r.del:SetSize(16, 16)
                r.del:SetPoint("LEFT", 300, 0)
                r.del:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
                r.del:GetNormalTexture():SetVertexColor(0.9, 0.4, 0.4)
                r.del:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
                customRows[shown] = r
            end
            r:SetPoint("TOPLEFT", 22, customListY - (shown - 1) * 20)
            r.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
            r.label:SetText(e.label)
            r.del:SetScript("OnClick", function()
                ns.RemoveTracked(e.key)
                rebuildCustomList()
                ns.RefreshAll()
            end)
            r:Show()
        end
    end
    emptyFS:SetShown(shown == 0)
end
refreshers[#refreshers + 1] = function() rebuildCustomList() end

local appearanceY = customListY - 4 * 20 - 24
Header("Appearance", 16, appearanceY)

Slider("Icon size", 18, appearanceY - 44, 8, 40, 1,
    function() return ns.db.iconSize end, function(v) ns.db.iconSize = v end)
Slider("Opacity", 268, appearanceY - 44, 0.2, 1, 0.05,
    function() return ns.db.alpha end, function(v) ns.db.alpha = v end,
    function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end)
Slider("Horizontal offset", 18, appearanceY - 94, 0, 60, 1,
    function() return ns.db.xOffset end, function(v) ns.db.xOffset = v end)
Slider("Vertical offset", 268, appearanceY - 94, -40, 40, 1,
    function() return ns.db.yOffset end, function(v) ns.db.yOffset = v end)

SideDropdown(18, appearanceY - 134)

Check("Skip my own nameplate", 268, appearanceY - 136,
    function() return ns.db.hideSelf end, function(v) ns.db.hideSelf = v end,
    "Leaves the personal resource display alone.")

local diagBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
diagBtn:SetSize(190, 22)
diagBtn:SetPoint("TOPLEFT", 268, appearanceY - 164)
diagBtn:SetText("Run diagnostics")
diagBtn:SetScript("OnClick", function() ns.RunDiagnostics() end)
diagBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Prints to chat what this client will and won't let addons read, per tracked buff, against your current target.", nil, nil, nil, nil, true)
    GameTooltip:Show()
end)
diagBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

--------------------------------------------------------------------------
-- Register + open
--------------------------------------------------------------------------
panel.refresh = function()
    if not ns.db then return end
    for _, fn in ipairs(refreshers) do fn() end
end
panel:SetScript("OnShow", panel.refresh)

if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    -- Deliberately NOT overwriting category.ID with the addon name. That idiom is
    -- still common (Ace3 does it) and exists so other addons can open this panel by
    -- name, but it only ever worked because Settings.OpenToCategory used to accept a
    -- string. On 12.x it forwards to C_SettingsUtil.OpenSettingsPanel, which wants a
    -- numeric id and throws on a string -- taking the addon's own /command with it.
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)   -- twice: legacy open-to-category quirk
    end
end

--------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------
SLASH_UNBUFFED1 = "/unbuffed"
SLASH_UNBUFFED2 = "/ub"
SlashCmdList.UNBUFFED = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" then
        ns.OpenOptions()
    elseif cmd == "on" or cmd == "off" then
        ns.db.enabled = (cmd == "on")
        ns.RefreshAll()
        ns.Print(ns.db.enabled and "on." or "off.")
    elseif cmd == "add" then
        local entry, err = ns.EntryFromInput(rest)
        if not entry then ns.Print(err); return end
        ns.AddTracked(entry)
        ns.RefreshAll()
        ns.Print("now flagging |cffffd100" .. entry.label .. "|r.")
    elseif cmd == "remove" or cmd == "rem" then
        local target = rest:lower()
        for _, e in ipairs(ns.db.tracked) do
            if e.key:lower() == target or e.label:lower() == target then
                ns.RemoveTracked(e.key)
                ns.RefreshAll()
                ns.Print("stopped flagging |cffffd100" .. e.label .. "|r.")
                return
            end
        end
        ns.Print("not tracking anything called '" .. rest .. "'.")
    elseif cmd == "list" then
        if #ns.db.tracked == 0 then ns.Print("nothing tracked."); return end
        ns.Print("tracking:")
        for _, e in ipairs(ns.db.tracked) do
            print("   - " .. e.label .. (e.enabled and "" or " |cff888888(off)|r")
                .. "  |cff888888[" .. table.concat(e.names, " / ") .. "]|r")
        end
    elseif cmd == "check" then
        ns.RunDiagnostics()
    else
        ns.Print("/ub  |cff888888(settings)|r  ·  add <name|id>  ·  remove <name>  ·  list  ·  check  ·  on|off")
    end
end
