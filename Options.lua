local ADDON, ns = ...

local panel = CreateFrame("Frame")
panel.name = "Unbuffed"
local category          -- modern Settings category, when the client has one
local refreshers = {}   -- run on every panel show, to resync widgets with the db
local rebuildCustomList -- forward decl
local content           -- the scroll child; every widget below lives in it
local blocks = {}       -- the panel's sections, top to bottom
local syncDependents    -- forward decl: re-reads the db into everything that hangs off it

-- After the user changes something: redraw the real plates, then everything in the
-- panel that depends on the new value (the preview, which sections show, what greys out).
local function onChange()
    ns.RefreshAll()
    syncDependents()
end

--------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------
-- Every helper takes an optional parent, so a section can own its widgets and be
-- shown, hidden or moved as one piece.
local function Header(text, x, y, parent)
    local p = parent or content
    local fs = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local line = p:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.18)
    line:SetSize(520 - x, 1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    return fs
end

local function Check(label, x, y, get, set, tooltip, parent)
    local p = parent or content
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(24, 24)
    local fs = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); onChange() end)
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
local function Slider(label, x, y, lo, hi, step, get, set, fmt, parent)
    sliderCount = sliderCount + 1
    local s = CreateFrame("Slider", "UnbuffedSlider" .. sliderCount, parent or content, "OptionsSliderTemplate")
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
        paint(v)
        if ns.PanelRefreshing() then return end   -- resync, not a user edit
        set(v); onChange()
    end)
    refreshers[#refreshers + 1] = function() local v = get(); s:SetValue(v); paint(v) end
    return s
end

local function Button(label, x, y, w, onClick, tooltip, parent)
    local b = CreateFrame("Button", nil, parent or content, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if tooltip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

-- Dropdowns. Midnight removed UIDropDownMenu; there the widget is a DropdownButton
-- driven by MenuUtil. Keep the legacy branch for the older Classic clients. The
-- choices come from ns.ANCHORS and ns.ICON_STYLES, so each is defined in one place.
local function Choices(list, supported)
    local out = {}
    for _, o in ipairs(list) do
        if not supported or supported(o.key) then out[#out + 1] = { o.label, o.key } end
    end
    return out
end
local ANCHOR_CHOICES = Choices(ns.ANCHORS)
local STYLE_CHOICES  = Choices(ns.ICON_STYLES, ns.IconStyleSupported)

-- `key` is the db field the dropdown edits. `name` is only for the legacy branch,
-- whose frames need a unique global name.
local function Dropdown(name, label, x, y, width, choices, key, parent)
    local p = parent or content
    local fs = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(label)

    if MenuUtil and MenuUtil.CreateRadioMenu then
        local dd = CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT", x, y - 18)
        dd:SetWidth(width)
        MenuUtil.CreateRadioMenu(dd,
            function(value) return value == ns.db[key] end,
            function(value)
                if ns.PanelRefreshing() then return end   -- resync, not a user edit
                ns.db[key] = value; onChange()
            end,
            unpack(choices))
        refreshers[#refreshers + 1] = function() dd:GenerateMenu() end
        return dd
    end

    local dd = CreateFrame("Frame", name, p, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", x - 16, y - 18)
    UIDropDownMenu_SetWidth(dd, width - 20)
    local function setText()
        for _, o in ipairs(choices) do
            if o[2] == ns.db[key] then UIDropDownMenu_SetText(dd, o[1]); return end
        end
    end
    UIDropDownMenu_Initialize(dd, function(_, level)
        for _, o in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = o[1], (o[2] == ns.db[key])
            info.func = function() ns.db[key] = o[2]; setText(); CloseDropDownMenus(); onChange() end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    refreshers[#refreshers + 1] = setText
    return dd
end

--------------------------------------------------------------------------
-- Sections
--------------------------------------------------------------------------
-- The panel is a stack of sections, each a frame that owns its widgets. Stacking is
-- done here rather than by hand-placed coordinates because two sections change
-- height as you use the panel: the custom-buff list grows, and the Custom position
-- section only exists while Custom is the anchor. Everything below just slides.
local function Section(height, shownFn)
    local b = CreateFrame("Frame", nil, content)
    b:SetSize(560, height)
    b.h, b.shownFn = height, shownFn
    blocks[#blocks + 1] = b
    return b
end

local function layoutBlocks()
    local y = 0
    for _, b in ipairs(blocks) do
        local show = (not b.shownFn) or b.shownFn()
        b:SetShown(show)
        if show then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            y = y + b.h + 10
        end
    end
    content:SetHeight(y + 10)
end

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------
-- Everything the "Reset" button puts back: how the icons look and where they sit.
-- Deliberately not the tracked list or the master switch -- those are what you chose
-- to watch, not how it is drawn.
local APPEARANCE_KEYS = {
    "anchor", "xOffset", "yOffset", "iconSize", "iconStyle", "iconZoom", "spacing", "alpha",
    "hideSelf", "flagExpiring", "expiringMinutes",
}

-- The panel is built on first show, not at load. A Settings canvas category
-- needs a frame up front, but not a populated one -- and building widgets at
-- load means creating them against SavedVariables that have not arrived yet.
-- Anything that reads or writes the db while being constructed then works off
-- the stand-in defaults, and can write a default back over a loaded value.
local built = false
local function buildPanel()
    if built then return end
    built = true

    -- The scroll frame is what lets the panel be longer than the window it lives in.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 900)
    scroll:SetScrollChild(content)

    ----------------------------------------------------------------------
    -- Title
    ----------------------------------------------------------------------
    local head = Section(100)
    local title = head:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Unbuffed")

    local blurb = head:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT", 16, -36)
    blurb:SetWidth(520)
    blurb:SetJustifyH("LEFT")
    blurb:SetText("Shows a small icon beside a friendly player's nameplate for each tracked buff they are |cffffd100missing|r. A fully buffed player shows nothing.")

    Check("Enabled", 18, -70, function() return ns.db.enabled end, function(v) ns.db.enabled = v end,
        nil, head)

    ----------------------------------------------------------------------
    -- Tracking
    ----------------------------------------------------------------------
    local track = Section(222)
    Header("Buffs to flag", 16, 0, track)

    -- Presets, three columns: nine of them in five rows wasted enough height
    -- to push the controls below off the bottom of the panel.
    local PRESET_COLS = 3
    for i, preset in ipairs(ns.PRESETS) do
        local col = (i - 1) % PRESET_COLS
        local row = math.floor((i - 1) / PRESET_COLS)
        Check(preset.label, 18 + col * 174, -28 - row * 26,
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
                .. table.concat(preset.names, ", ") .. ").", track)
    end

    local presetRows = math.ceil(#ns.PRESETS / PRESET_COLS)
    local customY = -28 - presetRows * 26 - 12

    Header("Add another buff", 16, customY, track)

    local addBox = CreateFrame("EditBox", nil, track, "InputBoxTemplate")
    addBox:SetSize(200, 22)
    addBox:SetPoint("TOPLEFT", 22, customY - 30)
    addBox:SetAutoFocus(false)

    local addHint = track:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    addHint:SetPoint("TOPLEFT", 22, customY - 56)
    addHint:SetText("Buff name or spell ID. A name matches every rank; an ID also survives combat.")

    local addBtn = CreateFrame("Button", nil, track, "UIPanelButtonTemplate")
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
    local customListY = customY - 80
    local LIST_TOP = -customListY   -- distance from the section's top to the first row

    local emptyFS = track:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
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
                    r = CreateFrame("Frame", nil, track)
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
        -- The section is as tall as its list, so everything below follows it.
        track.h = LIST_TOP + math.max(shown, 1) * 20 + 8
        track:SetHeight(track.h)
        layoutBlocks()
    end
    refreshers[#refreshers + 1] = function() rebuildCustomList() end

    ----------------------------------------------------------------------
    -- Position
    ----------------------------------------------------------------------
    local pos = Section(226)
    Header("Position", 16, 0, pos)

    -- A mock nameplate with the icon row on it, drawn by the very code the real
    -- plates use (ns.PlaceRow), so choosing an anchor shows exactly what it does.
    -- The plate's proportions are approximate; the icon size and spacing are real.
    local pv = CreateFrame("Frame", nil, pos)
    pv:SetSize(520, 100)
    pv:SetPoint("TOPLEFT", 18, -28)
    pv:SetClipsChildren(true)

    local pvEdge = pv:CreateTexture(nil, "BACKGROUND")
    pvEdge:SetAllPoints()
    pvEdge:SetColorTexture(0.25, 0.25, 0.28, 1)
    local pvFill = pv:CreateTexture(nil, "BACKGROUND", nil, 1)
    pvFill:SetPoint("TOPLEFT", 1, -1)
    pvFill:SetPoint("BOTTOMRIGHT", -1, 1)
    pvFill:SetColorTexture(0.06, 0.06, 0.08, 1)

    local pvCaption = pv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pvCaption:SetPoint("TOPLEFT", 6, -5)
    pvCaption:SetText("Preview")

    local mock = CreateFrame("Frame", nil, pv)
    mock:SetSize(150, 34)
    mock:SetPoint("CENTER", pv, "CENTER", -50, 10)

    local bar = CreateFrame("Frame", nil, mock)
    bar:SetSize(150, 12)
    bar:SetPoint("BOTTOM", mock, "BOTTOM", 0, 2)
    local barBack = bar:CreateTexture(nil, "BACKGROUND")
    barBack:SetAllPoints()
    barBack:SetColorTexture(0.10, 0.08, 0.08, 1)
    local barFill = bar:CreateTexture(nil, "ARTWORK")
    barFill:SetPoint("TOPLEFT")
    barFill:SetPoint("BOTTOMLEFT")
    barFill:SetWidth(100)
    barFill:SetColorTexture(0.25, 0.70, 0.25, 1)

    local level = CreateFrame("Frame", nil, mock)
    level:SetSize(22, 18)
    level:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    level:SetFrameLevel(bar:GetFrameLevel() + 2)
    local levelBack = level:CreateTexture(nil, "BACKGROUND")
    levelBack:SetAllPoints()
    levelBack:SetColorTexture(0.05, 0.04, 0.03, 1)
    local levelText = level:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetPoint("CENTER")
    levelText:SetText("8")

    local mockName = mock:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mockName:SetPoint("BOTTOM", bar, "TOP", 0, 3)
    mockName:SetText("Adventurer")

    -- Two demo icons, so spacing and which way the row grows are both visible.
    local pvRow = CreateFrame("Frame", nil, pv)
    pvRow:SetFrameLevel(pv:GetFrameLevel() + 6)
    pvRow.icons = {}
    for i, preset in ipairs({ ns.PRESETS[1], ns.PRESETS[3] }) do
        local t = ns.NewIcon(pvRow)
        t:SetTexture(preset.icon)
        pvRow.icons[i] = t
    end

    local function updatePreview()
        local db = ns.db
        local size, gap = db.iconSize, db.spacing
        local n = #pvRow.icons
        for i, t in ipairs(pvRow.icons) do
            t:ClearAllPoints()
            t:SetPoint("LEFT", pvRow, "LEFT", (i - 1) * (size + gap), 0)
            t:SetSize(size, size)
            t:SetAlpha(db.alpha)
            ns.StyleIcon(t, db.iconStyle, db.alpha, db.iconZoom)
        end
        pvRow:SetSize(n * size + (n - 1) * gap, size)
        ns.PlaceRow(pvRow, mock, bar, level, db)
    end

    Dropdown("UnbuffedAnchorDrop", "Anchor", 18, -138, 240, ANCHOR_CHOICES, "anchor", pos)
    local anchorHelp = pos:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    anchorHelp:SetPoint("TOPLEFT", 18, -190)
    anchorHelp:SetWidth(500)
    anchorHelp:SetJustifyH("LEFT")

    ----------------------------------------------------------------------
    -- Custom position (only while Custom is the anchor)
    ----------------------------------------------------------------------
    local custom = Section(88, function() return ns.db.anchor == "CUSTOM" end)
    Header("Custom position", 16, 0, custom)
    Slider("Horizontal offset", 18, -44, -200, 200, 1,
        function() return ns.db.xOffset end, function(v) ns.db.xOffset = v end,
        nil, custom)
    Slider("Vertical offset", 268, -44, -100, 100, 1,
        function() return ns.db.yOffset end, function(v) ns.db.yOffset = v end,
        nil, custom)

    ----------------------------------------------------------------------
    -- Look
    ----------------------------------------------------------------------
    local look = Section(200)
    Header("Look", 16, 0, look)
    Slider("Icon size", 18, -44, 8, 40, 1,
        function() return ns.db.iconSize end, function(v) ns.db.iconSize = v end,
        nil, look)
    Slider("Opacity", 268, -44, 0.2, 1, 0.05,
        function() return ns.db.alpha end, function(v) ns.db.alpha = v end,
        function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end, look)
    Slider("Spacing", 18, -94, 0, 12, 1,
        function() return ns.db.spacing end, function(v) ns.db.spacing = v end,
        nil, look)
    Dropdown("UnbuffedStyleDrop", "Icon style", 268, -90, 190, STYLE_CHOICES, "iconStyle", look)
    Slider("Icon zoom", 18, -144, 0, 30, 1,
        function() return ns.db.iconZoom end, function(v) ns.db.iconZoom = v end,
        function(v) return v .. "%" end, look)

    ----------------------------------------------------------------------
    -- Buffs about to expire
    ----------------------------------------------------------------------
    -- Same icon, tinted amber with the minutes left on it, so a buff about to run
    -- out reads differently from one that was never cast.
    local expiring = Section(116)
    Header("Buffs about to expire", 16, 0, expiring)
    Check("Also flag buffs about to expire", 18, -28,
        function() return ns.db.flagExpiring end, function(v) ns.db.flagExpiring = v end,
        "Shows the icon tinted amber, with the minutes left on it, once a buff drops "
            .. "below the threshold. A buff whose remaining time this client won't "
            .. "report is never flagged.", expiring)
    local warnSlider = Slider("Warn under (minutes)", 18, -76, 1, 30, 1,
        function() return ns.db.expiringMinutes end,
        function(v) ns.db.expiringMinutes = v end, nil, expiring)

    ----------------------------------------------------------------------
    -- General
    ----------------------------------------------------------------------
    local general = Section(96)
    Header("General", 16, 0, general)
    Check("Skip my own nameplate", 18, -28,
        function() return ns.db.hideSelf end, function(v) ns.db.hideSelf = v end,
        "Leaves the personal resource display alone.", general)
    -- Two clicks rather than a popup: a StaticPopup shown from addon code can hang the
    -- client in Gamepad mode, and this needs no dialog of its own. The first click arms
    -- the button and says so; it disarms itself if the second never comes.
    local RESET_LABEL = "Reset position and look"
    local resetBtn, armed
    resetBtn = Button(RESET_LABEL, 18, -62, 190, function()
        armed = (armed or 0) + 1
        local mine = armed
        if resetBtn.confirming then
            resetBtn.confirming = false
            resetBtn:SetText(RESET_LABEL)
            ns.ResetAppearance()
            return
        end
        resetBtn.confirming = true
        resetBtn:SetText("|cffff5555Click again to confirm|r")
        C_Timer.After(4, function()
            if armed == mine and resetBtn.confirming then
                resetBtn.confirming = false
                resetBtn:SetText(RESET_LABEL)
            end
        end)
    end, "Puts the position, size, opacity and expiry settings back to their defaults. Which buffs you track is left alone.",
        general)

    ----------------------------------------------------------------------
    -- Everything that follows from the current values
    ----------------------------------------------------------------------
    -- Called after every change and every resync. Nothing here writes to the db.
    syncDependents = function()
        for _, a in ipairs(ns.ANCHORS) do
            if a.key == ns.db.anchor then anchorHelp:SetText(a.help) end
        end
        -- A greyed-out control still shows its value; it just stops taking input.
        local on = ns.db.flagExpiring
        warnSlider:SetAlpha(on and 1 or 0.4)
        warnSlider:EnableMouse(on and true or false)
        layoutBlocks()
        updatePreview()
    end
end


--------------------------------------------------------------------------
-- Register + open
--------------------------------------------------------------------------
-- Set while widgets are being resynced from the db, so that resyncing can never
-- write back into it. A slider's SetValue fires OnValueChanged, and a dropdown's
-- GenerateMenu can re-invoke its setter -- both would then "save" whatever the
-- widget happened to be showing. That is a write triggered by a read, which is
-- how a stale default gets laid over a loaded value.
local refreshing = false
function ns.PanelRefreshing() return refreshing end

local function refreshPanel()
    -- Never before ADDON_LOADED. ns.db is a stand-in full of defaults until then,
    -- and building or refreshing against it is exactly how defaults leak into the
    -- real table. The Settings frame can call OnRefresh during registration.
    if not ns.dbReady then return end
    -- The guard has to cover construction too, not just the resync afterwards.
    -- Building a slider calls SetMinMaxValues, which can clamp the slider's value
    -- and so fire OnValueChanged exactly as a drag would. Outside the guard, that
    -- would run the setter and write the clamped value over a loaded one.
    refreshing = true
    buildPanel()
    for _, fn in ipairs(refreshers) do fn() end
    syncDependents()
    refreshing = false
end
panel:SetScript("OnShow", refreshPanel)
-- The modern Settings frame drives canvas panels through these rather than the
-- legacy `refresh`, and Baganator/Auctionator define all three even when empty.
panel.OnRefresh = refreshPanel
panel.OnCommit  = function() end
panel.OnDefault = function() end

-- What the Reset button does once confirmed.
function ns.ResetAppearance()
    for _, key in ipairs(APPEARANCE_KEYS) do ns.db[key] = ns.defaults[key] end
    refreshPanel()
    ns.RefreshAll()
end

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
    else
        ns.Print("/ub  |cff888888(settings)|r  ·  add <name|id>  ·  remove <name>  ·  list  ·  on|off")
    end
end
