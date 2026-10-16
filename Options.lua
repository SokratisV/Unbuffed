local ADDON, ns = ...

local panel = CreateFrame("Frame")
panel.name = "Unbuffed"
local category          -- modern Settings category, when the client has one
local refreshers = {}   -- run on every panel show, to resync widgets with the db
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
local EXPIRE_CHOICES = Choices(ns.EXPIRE_STYLES)

-- `key` is the db field the dropdown edits. `name` is only for the legacy branch,
-- whose frames need a unique global name. `default` is what it shows while the field
-- has no saved value (the class dropdown starts on your own class, for instance).
local function Dropdown(name, label, x, y, width, choices, key, parent, default)
    local p = parent or content
    local function current()
        local v = ns.db[key]
        if v == nil then return default end
        return v
    end
    local fs = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(label)

    if MenuUtil and MenuUtil.CreateRadioMenu then
        local dd = CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")
        dd:SetPoint("TOPLEFT", x, y - 18)
        dd:SetWidth(width)
        MenuUtil.CreateRadioMenu(dd,
            function(value) return value == current() end,
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
            if o[2] == current() then UIDropDownMenu_SetText(dd, o[1]); return end
        end
    end
    UIDropDownMenu_Initialize(dd, function(_, level)
        for _, o in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = o[1], (o[2] == current())
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
    "hideSelf", "flagExpiring", "expiringMinutes", "expireStyle", "expireAlpha",
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
    local head = Section(70)
    local title = head:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("Unbuffed")

    local blurb = head:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT", 16, -36)
    blurb:SetWidth(520)
    blurb:SetJustifyH("LEFT")
    blurb:SetText("Shows a small icon beside a friendly player's nameplate for each tracked buff they are |cffffd100missing|r. A fully buffed player shows nothing.")

    ----------------------------------------------------------------------
    -- Tracking
    ----------------------------------------------------------------------
    -- Pick a class, tick the buffs it offers. Choices accumulate across classes, and the
    -- Active list underneath shows everything currently tracked, whichever class it came
    -- from -- or none, for a buff added by name. All of it is laid out by renderTracking,
    -- because the grid's height depends on the class and the active list's on how many
    -- buffs are tracked; the section just grows and everything below slides.
    local track = Section(300)
    Header("Buffs to flag", 16, 0, track)

    local classList = ns.ClassList()
    local defaultClass = ns.PlayerClass() or classList[1].key   -- start on your own class
    local function currentClass() return ns.db.browseClass or defaultClass end
    local function className(key)
        for _, c in ipairs(classList) do if c.key == key then return c.name end end
        return key
    end
    Dropdown("UnbuffedClassDrop", "Class", 18, -28, 230, Choices(classList), "browseClass", track, defaultClass)

    local GRID_COLS, GRID_X, GRID_W, ROW_H = 3, 18, 174, 26
    local GRID_TOP = 82       -- where the class's buffs start, below the section's top
    local CHIP_H = 24

    -- The class's buffs: a pool of ticks, reused as the class changes.
    local gridPool = {}
    local function gridWidget(i)
        local w = gridPool[i]
        if w then return w end
        w = CreateFrame("CheckButton", nil, track, "UICheckButtonTemplate")
        w:SetSize(24, 24)
        w.icon = w:CreateTexture(nil, "ARTWORK")
        w.icon:SetSize(16, 16)
        w.icon:SetPoint("LEFT", w, "RIGHT", 2, 0)
        w.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        w.text = w:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        w.text:SetPoint("LEFT", w.icon, "RIGHT", 4, 0)
        w.text:SetWidth(GRID_W - 74)
        w.text:SetJustifyH("LEFT")
        w.text:SetWordWrap(false)
        w:SetScript("OnClick", function(self)
            local preset = self.preset
            if self:GetChecked() then ns.AddTracked(ns.PresetEntry(preset)) else ns.RemoveTracked(preset.key) end
            onChange()
        end)
        w:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Matched by name, so every rank counts -- and so do the group versions ("
                .. table.concat(self.preset.names, ", ") .. ").", nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        w:SetScript("OnLeave", function() GameTooltip:Hide() end)
        gridPool[i] = w
        return w
    end

    local gridEmpty = track:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    gridEmpty:SetWidth(500)
    gridEmpty:SetJustifyH("LEFT")

    -- Returns the height the grid takes.
    local function renderGrid()
        local classKey = currentClass()
        local list = ns.ClassBuffs(classKey)
        for i, preset in ipairs(list) do
            local w = gridWidget(i)
            w.preset = preset
            w.icon:SetTexture(ns.PresetIcon(preset))
            w.text:SetText(preset.label)
            local e = ns.FindTracked(preset.key)
            w:SetChecked(e and e.enabled and true or false)
            local col, row = (i - 1) % GRID_COLS, math.floor((i - 1) / GRID_COLS)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", track, "TOPLEFT", GRID_X + col * GRID_W, -(GRID_TOP + row * ROW_H))
            w:Show()
        end
        for i = #list + 1, #gridPool do gridPool[i]:Hide() end
        if #list == 0 then
            gridEmpty:SetText(className(classKey) .. " has no buffs worth flagging on other players. "
                .. "Anything else can still be added by name below.")
            gridEmpty:ClearAllPoints()
            gridEmpty:SetPoint("TOPLEFT", track, "TOPLEFT", 22, -GRID_TOP)
            gridEmpty:Show()
            return 22
        end
        gridEmpty:Hide()
        return math.ceil(#list / GRID_COLS) * ROW_H
    end

    -- Everything being tracked, from any class, each with a button to drop it.
    local activeHeader = Header("Active buffs", 16, 0, track)
    local activeEmpty = track:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    activeEmpty:SetText("Nothing is being tracked yet. Pick a class above and tick the buffs you want flagged.")

    local chipPool = {}
    local function chipFrame(i)
        local c = chipPool[i]
        if c then return c end
        c = CreateFrame("Frame", nil, track)
        c:SetSize(GRID_W - 6, 22)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(16, 16)
        c.icon:SetPoint("LEFT", 0, 0)
        c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        c.text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        c.text:SetPoint("LEFT", c.icon, "RIGHT", 5, 0)
        c.text:SetWidth(GRID_W - 6 - 16 - 5 - 24)
        c.text:SetJustifyH("LEFT")
        c.text:SetWordWrap(false)
        c.del = CreateFrame("Button", nil, c)
        c.del:SetSize(16, 16)
        c.del:SetPoint("RIGHT", 0, 0)
        c.del:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        c.del:GetNormalTexture():SetVertexColor(0.9, 0.4, 0.4)
        c.del:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        c.del:SetScript("OnClick", function()
            if c.entry then ns.RemoveTracked(c.entry.key); onChange() end
        end)
        chipPool[i] = c
        return c
    end

    -- Adding by name or spell id, for anything the classes above do not list.
    local addHeader = Header("Add another buff", 16, 0, track)

    local addBox = CreateFrame("EditBox", nil, track, "InputBoxTemplate")
    addBox:SetSize(200, 22)
    addBox:SetAutoFocus(false)

    local addHint = track:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
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
        onChange()
        ns.Print("now flagging |cffffd100" .. entry.label .. "|r.")
    end
    addBtn:SetScript("OnClick", doAdd)
    addBox:SetScript("OnEnterPressed", doAdd)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Lay the whole section out from the current class and the current tracked list.
    local function renderTracking()
        local y = GRID_TOP + renderGrid() + 14

        local n = #ns.db.tracked
        activeHeader:SetText("Active buffs (" .. n .. ")")
        activeHeader:ClearAllPoints()
        activeHeader:SetPoint("TOPLEFT", track, "TOPLEFT", 16, -y)
        y = y + 26
        for i, e in ipairs(ns.db.tracked) do
            local c = chipFrame(i)
            c.entry = e
            c.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
            c.text:SetText(e.label or e.key)
            c:SetAlpha(e.enabled == false and 0.5 or 1)
            local col, row = (i - 1) % GRID_COLS, math.floor((i - 1) / GRID_COLS)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", track, "TOPLEFT", GRID_X + col * GRID_W, -(y + row * CHIP_H))
            c:Show()
        end
        for i = n + 1, #chipPool do chipPool[i]:Hide() end
        activeEmpty:ClearAllPoints()
        activeEmpty:SetPoint("TOPLEFT", track, "TOPLEFT", 22, -y)
        activeEmpty:SetShown(n == 0)
        y = y + math.max(1, math.ceil(n / GRID_COLS)) * CHIP_H + 12

        addHeader:ClearAllPoints()
        addHeader:SetPoint("TOPLEFT", track, "TOPLEFT", 16, -y)
        addBox:ClearAllPoints()
        addBox:SetPoint("TOPLEFT", track, "TOPLEFT", 22, -(y + 30))
        addHint:ClearAllPoints()
        addHint:SetPoint("TOPLEFT", track, "TOPLEFT", 22, -(y + 56))

        track.h = y + 56 + 18
        track:SetHeight(track.h)
    end

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

    -- Demo icons, so spacing and which way the row grows are both visible. The third is
    -- the "about to expire" example, with its timer, so the expiring look can be judged
    -- here too; it appears only while expiry flagging is on.
    local pvRow = CreateFrame("Frame", nil, pv)
    pvRow:SetFrameLevel(pv:GetFrameLevel() + 6)
    pvRow.icons = {}
    for i, key in ipairs({ "fortitude", "motw", "intellect" }) do
        local t = ns.NewIcon(pvRow)
        t:SetTexture(ns.PresetIcon(ns.FindPreset(key)))
        pvRow.icons[i] = t
    end
    -- A font template, not just a layer: a FontString with no font raises "Font not set" the
    -- moment it is given text, which here would abort the build of the whole panel.
    local pvTimer = pvRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pvTimer:SetDrawLayer("OVERLAY", 2)
    pvTimer:SetPoint("BOTTOMRIGHT", pvRow.icons[3], "BOTTOMRIGHT", 2, -2)
    pvTimer:SetText("4m")

    local function updatePreview()
        local db = ns.db
        local size, gap = db.iconSize, db.spacing
        local n = db.flagExpiring and 3 or 2
        for i, t in ipairs(pvRow.icons) do
            if i > n then
                ns.HideIcon(t)
            else
                local alpha, r, g, b = db.alpha, 1, 1, 1
                if i == 3 then   -- the expiring example
                    local er, eg, eb, ea = ns.ExpiringLook(db)
                    r, g, b, alpha = er, eg, eb, db.alpha * ea
                end
                t:ClearAllPoints()
                t:SetPoint("LEFT", pvRow, "LEFT", (i - 1) * (size + gap), 0)
                t:SetSize(size, size)
                t:SetAlpha(alpha)
                t:SetVertexColor(r, g, b)
                ns.StyleIcon(t, db.iconStyle, alpha, db.iconZoom)
                t:Show()
            end
        end
        if n == 3 then
            pvTimer:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", math.max(7, math.floor(size * 0.46)), "OUTLINE")
            pvTimer:SetAlpha(1)   -- the timer never fades with its icon
            pvTimer:Show()
        else
            pvTimer:Hide()
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
    -- The same icon with the minutes left on it, told apart from one that was never
    -- cast either by an amber tint or by fading. Only the icon fades, never the timer.
    local expiring = Section(164)
    Header("Buffs about to expire", 16, 0, expiring)
    Check("Also flag buffs about to expire", 18, -28,
        function() return ns.db.flagExpiring end, function(v) ns.db.flagExpiring = v end,
        "Keeps the icon showing, with the minutes left on it, once a buff drops "
            .. "below the threshold -- tinted amber or faded, as chosen below. A buff "
            .. "whose remaining time this client won't report is never flagged.", expiring)
    local warnSlider = Slider("Warn under (minutes)", 18, -76, 1, 30, 1,
        function() return ns.db.expiringMinutes end,
        function(v) ns.db.expiringMinutes = v end, nil, expiring)
    local expireDD = Dropdown("UnbuffedExpireDrop", "Show them as", 268, -72, 190, EXPIRE_CHOICES, "expireStyle", expiring)
    local fadeSlider = Slider("Faded opacity", 18, -134, 10, 100, 5,
        function() return ns.db.expireAlpha end, function(v) ns.db.expireAlpha = v end,
        function(v) return v .. "%" end, expiring)

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
        renderTracking()
        for _, a in ipairs(ns.ANCHORS) do
            if a.key == ns.db.anchor then anchorHelp:SetText(a.help) end
        end
        -- A greyed-out control still shows its value; it just stops taking input.
        local function dim(widget, enabled)
            widget:SetAlpha(enabled and 1 or 0.4)
            widget:EnableMouse(enabled and true or false)
        end
        local on = ns.db.flagExpiring
        dim(warnSlider, on)
        dim(expireDD, on)
        dim(fadeSlider, on and ns.db.expireStyle == "FADE")   -- only meaningful when fading
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
        ns.Print("/ub  |cff888888(settings)|r  ·  add <name|id>  ·  remove <name>  ·  list")
    end
end
