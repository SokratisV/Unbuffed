local ADDON, ns = ...

-- The settings window (/ub), in the visual language of FlareUI by Malkkav (MIT), as the Garu
-- Combat Text window is: bronze trim over Blizzard's Collections tile, the pages in a list on
-- the left, the page's settings in the middle under headings that fold, and on the right what
-- the hovered setting does. Blizzard's own controls throughout. Unbuffed has few pages, so
-- there is no search box, and the nameplate preview sits above the settings on the pages that
-- change how an icon looks, where scrolling can never carry it out of sight.
--
-- Pages are plain data (definePages, below): each row says what it is, what it does, how to
-- read and write its value, and when it applies. The window is drawn from that data and drawn
-- again after every change, so a setting that stops applying (the ring color, once the style
-- has no ring) goes, and comes back when it applies again. Sliders are the exception:
-- redrawing mid-drag would drop the drag, and nothing a slider sets changes what is shown.

local WIDTH, HEIGHT = 860, 640
local HEADER_H = 34
local LEFT_W, RIGHT_W = 150, 220
local PAD = 12
local ROW_H, SECTION_H = 26, 28
local CONTENT_W = WIDTH - 12 - LEFT_W - RIGHT_W - 2 * PAD - 14
local PV_H = 150
local ICON = "Interface\\Icons\\Spell_Holy_WordFortitude"

local BORDER = { 0.80, 0.60, 0.34 }
local BRONZE = { 0.61, 0.48, 0.29 }

local function val(x) if type(x) == "function" then return x() end return x end
local function Sound(kit)
    local id = SOUNDKIT and SOUNDKIT[kit]
    if id and PlaySound then pcall(PlaySound, id) end
end

local Panel = {}
local frame
local page, info = {}, {}
local pages, pageByKey
local current
local closed = {}             -- "page:section" -> folded, for this session
local pools, used, customShown = {}, {}, {}
local navButtons = {}
local pv = {}                 -- the preview
local uid = 0

-- Everything the "Reset" button puts back: how the icons look and where they sit. Deliberately
-- not the tracked list or who is flagged -- those are what you chose to watch, not how it is drawn.
local APPEARANCE_KEYS = {
    "anchor", "xOffset", "yOffset", "iconSize", "iconStyle", "iconZoom", "spacing", "alpha",
    "hideSelf", "flagExpiring", "expiringMinutes", "expireStyle", "expireAlpha",
    "ringColor", "layout", "maxIcons", "outline", "outlineSize",
}

--------------------------------------------------------------------------
-- 1. ROW DEFINITIONS
--------------------------------------------------------------------------
-- Rows read ns.db when asked, never when made.
local function merge(row, extra)
    if extra then for k, v in pairs(extra) do row[k] = v end end
    return row
end
local function Toggle(field, label, desc, extra)
    return merge({ kind = "toggle", label = label, desc = desc,
        get = function() return ns.db[field] and true or false end,
        set = function(v) ns.db[field] = v end }, extra)
end
local function Choice(field, label, desc, choices, extra)
    return merge({ kind = "choice", label = label, desc = desc, choices = choices,
        get = function() return ns.db[field] end,
        set = function(v) ns.db[field] = v end }, extra)
end
local function Slider(field, label, desc, lo, hi, step, extra)
    return merge({ kind = "slider", label = label, desc = desc, min = lo, max = hi, step = step,
        get = function() return tonumber(ns.db[field]) or lo end,
        set = function(v) ns.db[field] = v end }, extra)
end
local function Button(label, desc, text, run, extra)
    return merge({ kind = "button", label = label, desc = desc, buttonText = text, run = run }, extra)
end

local function Choices(list, supported)
    local out = {}
    for _, o in ipairs(list) do
        if not supported or supported(o.key) then out[#out + 1] = { value = o.key, text = o.label } end
    end
    return out
end

--------------------------------------------------------------------------
-- 2. SMALL PIECES
--------------------------------------------------------------------------
local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Line(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.6)
    t:SetHeight(1)
    return t
end

-- A change was made: redraw the real plates and the preview now.
local function Applied()
    ns.RefreshAll()
    if pv.update then pv.update() end
end

-- ...and the window a frame later, since a menu's own click is still running.
local function Changed()
    C_Timer.After(0, function() if frame and frame:IsShown() then Panel.Refresh() end end)
end

--------------------------------------------------------------------------
-- 3. THE RIGHT COLUMN: what the hovered setting does
--------------------------------------------------------------------------
local function ShowInfo(title, desc, tip)
    if not info.title then return end
    info.title:SetText(title or "")
    info.desc:SetText(desc or "")
    info.tip:SetText(tip and ("|cffffd100Tip:|r " .. tip) or "")
end

local function ShowPageInfo()
    local p = pageByKey and pageByKey[current]
    if p then ShowInfo(val(p.title), val(p.desc), "Hover any setting to see what it does.") end
end

--------------------------------------------------------------------------
-- 4. ROWS
--------------------------------------------------------------------------
-- One pool per kind. A row spans the page: its name on the left, its control on the right;
-- hovering it fills the right column.
local Build, Fill = {}, {}

local function RowEnter(self)
    if self.row then ShowInfo(val(self.row.label), val(self.row.desc), self.row.tip) end
    self.hover:Show()
end
local function RowLeave(self)
    self.hover:Hide()
    ShowPageInfo()
end
local function Forward(control, f)
    if not control or not control.HookScript then return end
    control:HookScript("OnEnter", function() RowEnter(f) end)
    control:HookScript("OnLeave", function() RowLeave(f) end)
end

local function NewRow(parent, kind)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(ROW_H)
    f:EnableMouse(true)
    f:SetScript("OnEnter", RowEnter)
    f:SetScript("OnLeave", RowLeave)
    f.hover = f:CreateTexture(nil, "BACKGROUND")
    f.hover:SetAllPoints()
    f.hover:SetColorTexture(1, 0.82, 0, 0.06)
    f.hover:Hide()
    f.label = Text(f, "GameFontHighlight")
    f.label:SetPoint("LEFT", 6, 0)
    f.kind = kind
    Build[kind](f)
    return f
end

local function Acquire(parent, kind)
    pools[kind] = pools[kind] or {}
    local f = table.remove(pools[kind]) or NewRow(parent, kind)
    f:SetParent(parent)
    f:Show()
    used[#used + 1] = f
    return f
end

local function ReleaseAll()
    for _, f in ipairs(used) do
        f:Hide()
        f:ClearAllPoints()
        f.row = nil
        table.insert(pools[f.kind], f)
    end
    wipe(used)
    for _, f in ipairs(customShown) do f:Hide() end
    wipe(customShown)
end

-- toggle: a checkbox at the right
Build.toggle = function(f)
    local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("RIGHT", -4, 0)
    check:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
        if f.row then f.row.set(on); Applied(); Changed() end
    end)
    Forward(check, f)
    f.check = check
end
Fill.toggle = function(f, row)
    f.check:SetChecked(row.get() and true or false)
end

-- choice: Blizzard's stepper from its Settings (a dark box with an arrow either side; the box
-- opens the list, the arrows step through it). Where a client has no such template, a plain
-- dropdown; where it has no menus either, the old one.
local function SetupMenu(dropdown, f)
    dropdown:SetupMenu(function(_, root)
        local row = f.row
        if not row then return end
        for _, c in ipairs(row.choices) do
            root:CreateRadio(c.text,
                function() return row.get() == c.value end,
                function() row.set(c.value); Applied(); Changed() end,
                c.value)
        end
    end)
end

Build.choice = function(f)
    local ok, stepper = pcall(CreateFrame, "Frame", nil, f, "SettingsDropdownWithButtonsTemplate")
    if ok and stepper and stepper.Dropdown and stepper.IncrementButton and stepper.DecrementButton
        and stepper.Dropdown.SetupMenu then
        if stepper.Label then stepper.Label:Hide() end
        stepper:SetPoint("RIGHT", 4, 0)
        stepper.Dropdown:SetWidth(160)
        -- the template lays its arrows out past its own right edge: placed from the row's
        -- right edge instead, so the right arrow is never clipped
        stepper.IncrementButton:ClearAllPoints()
        stepper.IncrementButton:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        stepper.Dropdown:ClearAllPoints()
        stepper.Dropdown:SetPoint("RIGHT", stepper.IncrementButton, "LEFT", -5, 0)
        stepper.DecrementButton:ClearAllPoints()
        stepper.DecrementButton:SetPoint("RIGHT", stepper.Dropdown, "LEFT", -5, 0)
        Forward(stepper.Dropdown, f); Forward(stepper.IncrementButton, f); Forward(stepper.DecrementButton, f)
        SetupMenu(stepper.Dropdown, f)
        f.dropdown = stepper.Dropdown
        f:SetHeight(ROW_H + 6)
        return
    end
    if ok and stepper then stepper:Hide() end

    if MenuUtil then
        local okd, dd = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
        if okd and dd and dd.SetupMenu then
            dd:SetWidth(180)
            dd:SetPoint("RIGHT", -6, 0)
            Forward(dd, f)
            SetupMenu(dd, f)
            f.dropdown = dd
            return
        end
    end

    uid = uid + 1
    local dd = CreateFrame("Frame", "UnbuffedDrop" .. uid, f, "UIDropDownMenuTemplate")
    dd:SetPoint("RIGHT", 10, -2)
    UIDropDownMenu_SetWidth(dd, 150)
    UIDropDownMenu_Initialize(dd, function(_, level)
        local row = f.row
        if not row then return end
        for _, c in ipairs(row.choices) do
            local entry = UIDropDownMenu_CreateInfo()
            entry.text, entry.checked = c.text, (row.get() == c.value)
            entry.func = function() row.set(c.value); CloseDropDownMenus(); Applied(); Changed() end
            UIDropDownMenu_AddButton(entry, level)
        end
    end)
    f.legacy = dd
    f:SetHeight(ROW_H + 6)
end
Fill.choice = function(f, row)
    if f.dropdown then
        f.dropdown:GenerateMenu()
    elseif f.legacy then
        local text = ""
        for _, c in ipairs(row.choices) do if c.value == row.get() then text = c.text end end
        UIDropDownMenu_SetText(f.legacy, text)
    end
end

-- slider: Blizzard's minimal slider with its stepper arrows, and the value in a box you can
-- type into
local function Snap(v, step)
    if step >= 1 then return math.floor(v / step + 0.5) * step end
    local m = 1 / step
    return math.floor(v * m + 0.5) / m
end
local function ValueText(row, v)
    if row.fmt then return row.fmt(v) end
    if row.step < 1 then return string.format("%.1f", v) end
    return tostring(v)
end

local function SliderChanged(f, value)
    local row = f.row
    if f.filling or not row then return end
    value = Snap(value, row.step)
    if value ~= row.get() then row.set(value); Applied() end
    f.edit:SetText(ValueText(row, value))
end

Build.slider = function(f)
    local ok, s = pcall(CreateFrame, "Frame", nil, f, "MinimalSliderWithSteppersTemplate")
    if ok and s and s.Init and s.RegisterCallback and MinimalSliderWithSteppersMixin
        and MinimalSliderWithSteppersMixin.Event then
        s:SetWidth(180)
        s:SetPoint("RIGHT", -54, 0)
        if s.MinText then s.MinText:Hide() end
        if s.MaxText then s.MaxText:Hide() end
        s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
            function(_, value) SliderChanged(f, value) end, f)
        Forward(s, f); Forward(s.Slider, f)
        f.slider = s
    else
        if ok and s then s:Hide() end
        -- no template: a bare slider in the same place
        local bare = CreateFrame("Slider", nil, f)
        bare:SetOrientation("HORIZONTAL")
        bare:SetSize(170, 14)
        bare:SetPoint("RIGHT", -60, 0)
        bare:SetHitRectInsets(0, 0, -6, -6)
        pcall(bare.SetObeyStepOnDrag, bare, true)
        local track = bare:CreateTexture(nil, "ARTWORK")
        track:SetColorTexture(0.30, 0.30, 0.34, 0.9); track:SetHeight(4)
        track:SetPoint("LEFT"); track:SetPoint("RIGHT")
        local thumb = bare:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1); thumb:SetSize(10, 16)
        bare:SetThumbTexture(thumb)
        bare:SetScript("OnValueChanged", function(_, value) SliderChanged(f, value) end)
        Forward(bare, f)
        f.slider = bare
    end

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(52, 18)
    edit:SetPoint("RIGHT", -6, 0)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetMaxLetters(8)
    local function restore(self)
        if f.row then self:SetText(ValueText(f.row, f.row.get())) end
        self:ClearFocus()
    end
    edit:SetScript("OnEditFocusGained", function(self)
        if f.row then self:SetText(tostring(f.row.get())) end
        self:HighlightText()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        local row, v = f.row, tonumber(self:GetText())
        if row and v then
            v = Snap(math.min(row.max, math.max(row.min, v)), row.step)
            f.slider:SetValue(v)
            if v ~= row.get() then row.set(v); Applied() end
        end
        restore(self)
    end)
    edit:SetScript("OnEscapePressed", restore)
    edit:SetScript("OnEditFocusLost", restore)
    Forward(edit, f)
    f.edit = edit
    f:SetHeight(ROW_H + 4)
end
Fill.slider = function(f, row)
    f.filling = true
    local v = row.get()
    if f.slider.Init then
        local steps = math.max(1, math.floor((row.max - row.min) / row.step + 0.5))
        f.slider:Init(v, row.min, row.max, steps, {})
    else
        f.slider:SetMinMaxValues(row.min, row.max)
        f.slider:SetValueStep(row.step)
        f.slider:SetValue(v)
    end
    f.edit:SetText(ValueText(row, v))
    f.edit:SetCursorPosition(0)
    f.filling = false
end

-- button: an action, at the right
Build.button = function(f)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetHeight(22)
    b:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnClick", function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if f.row and f.row.run then f.row.run(); Changed() end
    end)
    Forward(b, f)
    f.button = b
end
Fill.button = function(f, row)
    f.button:SetText(val(row.buttonText) or "")
    f.button:SetWidth(math.max(90, (f.button:GetFontString() and f.button:GetFontString():GetStringWidth() or 60) + 28))
end

local function FillRow(f, row)
    f.row = row
    f.label:SetText(val(row.label) or "")
    Fill[f.kind](f, row)
end

--------------------------------------------------------------------------
-- 5. THE PREVIEW: a mock nameplate with the icon row on it
--------------------------------------------------------------------------
-- The row is drawn by ns.RenderRow and placed by ns.PlaceRow -- the very code the real plates
-- use -- so every choice shows exactly what it does. The plate's proportions are approximate;
-- the icon size, spacing and everything else are real. The third demo icon is the "about to
-- expire" example, with its timer; it appears only while expiry flagging is on, and its
-- countdown is held at half so it stays put, until the Test button runs it down.
local function BuildPreview(parent, header)
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    box:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    box:SetHeight(PV_H)
    pcall(box.SetClipsChildren, box, true)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    local top = Line(box)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    local bottom = Line(box)
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    local label = Text(box, "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", 6, -5)
    label:SetText("Preview")
    pv.box = box

    local mock = CreateFrame("Frame", nil, box)
    mock:SetSize(150, 34)
    mock:SetPoint("CENTER", box, "CENTER", -50, 4)

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

    local row = ns.NewRow(box)
    row:SetFrameLevel(box:GetFrameLevel() + 6)
    local items, list = {}, {}
    for i, key in ipairs({ "fortitude", "motw", "intellect", "bshout" }) do
        items[i] = { icon = ns.PresetIcon(ns.FindPreset(key)), class = ns.ClassOfBuff(key) }
    end
    pv.row = row

    function pv.update()
        local db = ns.db
        items[3].expiring = true
        items[3].left = db.flagExpiring and ns.TestLeft(db) or db.expiringMinutes * 30
        local count = 0
        for i, it in ipairs(items) do
            if i ~= 3 or db.flagExpiring then
                count = count + 1
                list[count] = it
            end
        end
        ns.RenderRow(row, list, count, db, { freeze = true })
        ns.PlaceRow(row, mock, bar, level, db)
        row:Show()
    end

    -- Test: runs the first tracked buff down, here and on every plate (see ns.StartExpiryTest).
    local test = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    test:SetSize(140, 20)
    test:SetPoint("TOPRIGHT", -6, -4)
    test:SetText("Test expiring look")
    test:SetScript("OnClick", function()
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        ns.RunExpiryTest()
    end)
    test:SetScript("OnEnter", function()
        ShowInfo("Test expiring look",
            "Runs the first buff you track down from a full warning window to nothing over 20 seconds, in this preview and on every friendly player's nameplate in view, so you can see the expiring look without waiting for a real buff.",
            "Needs Also flag buffs about to expire. Also /ub test.")
    end)
    test:SetScript("OnLeave", ShowPageInfo)
    pv.test = test

    -- While a test runs the preview redraws every frame, and once more when it ends, which
    -- puts the example back at half.
    local testing = false
    box:SetScript("OnUpdate", function()
        local active = ns.TestActive()
        if active or testing then pv.update() end
        testing = active
    end)
    box:Hide()
end

--------------------------------------------------------------------------
-- 6. THE BUFF LIST: custom rows for the Buffs page
--------------------------------------------------------------------------
-- The tooltip for a buff: the game's own spell tooltip for the rank that suits the character's
-- level, then a line saying so, then what the buff is matched by. `key` names a listed buff;
-- `ids` is the spell id someone typed, for one added by id, whose exact rank is theirs to have
-- chosen and is shown as it is. A buff with no level-based rank on this client (see
-- ns.RankFor), or one the client will not describe, gets just its name.
local TIP_GREY = { 0.62, 0.62, 0.62 }
local function ShowBuffTooltip(owner, key, label, names, ids)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local level = UnitLevel("player") or 1
    local spellID, learnedAt, byLevel
    if key then
        spellID, learnedAt = ns.RankFor(key, level)
        byLevel = spellID ~= nil
    end
    if not spellID and ids and ids[1] then spellID = ids[1] end

    local described = false
    if spellID and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(spellID)
        described = GameTooltip:NumLines() > 0
    end
    if not described then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(label, 1, 1, 1)
    end
    if described and byLevel then
        GameTooltip:AddLine(" ")
        if learnedAt > level then
            GameTooltip:AddLine(("Your level (%d) is below this buff's first rank, which is learned at level %d."):format(level, learnedAt), 1, 0.82, 0, true)
        else
            GameTooltip:AddLine(("Showing the rank for your level (%d)."):format(level), TIP_GREY[1], TIP_GREY[2], TIP_GREY[3])
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Matched by name: " .. table.concat(names or {}, ", ") .. ".", TIP_GREY[1], TIP_GREY[2], TIP_GREY[3], true)
    GameTooltip:Show()
end

local GRID_COLS = 2
local CHIP_H, TICK_H = 24, 26

-- The class's buffs, as a grid of ticks reused as the class changes. Returns the frame and
-- the function that fills it and says how tall it came out.
local function BuildBuffGrid(parent, className, currentClass)
    local grid = CreateFrame("Frame", nil, parent)
    local colW = math.floor(CONTENT_W / GRID_COLS)
    local pool = {}
    local function tick(i)
        local w = pool[i]
        if w then return w end
        w = CreateFrame("CheckButton", nil, grid, "UICheckButtonTemplate")
        w:SetSize(24, 24)
        w.icon = w:CreateTexture(nil, "ARTWORK")
        w.icon:SetSize(16, 16)
        w.icon:SetPoint("LEFT", w, "RIGHT", 2, 0)
        w.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        w.text = w:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        w.text:SetPoint("LEFT", w.icon, "RIGHT", 4, 0)
        w.text:SetWidth(colW - 66)
        w.text:SetJustifyH("LEFT")
        w.text:SetWordWrap(false)
        w:SetScript("OnClick", function(self)
            local preset = self.preset
            if self:GetChecked() then ns.AddTracked(ns.PresetEntry(preset)) else ns.RemoveTracked(preset.key) end
            Applied(); Changed()
        end)
        w:SetScript("OnEnter", function(self)
            ShowBuffTooltip(self, self.preset.key, self.preset.label, self.preset.names)
        end)
        w:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pool[i] = w
        return w
    end
    local empty = Text(grid, "GameFontDisableSmall")
    empty:SetWidth(CONTENT_W - 20)
    empty:SetPoint("TOPLEFT", 8, -4)

    local function render()
        local classKey = currentClass()
        local list = ns.ClassBuffs(classKey)
        for i, preset in ipairs(list) do
            local w = tick(i)
            w.preset = preset
            w.icon:SetTexture(ns.PresetIcon(preset))
            w.text:SetText(preset.label)
            local e = ns.FindTracked(preset.key)
            w:SetChecked(e and e.enabled and true or false)
            local col, row = (i - 1) % GRID_COLS, math.floor((i - 1) / GRID_COLS)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", grid, "TOPLEFT", 4 + col * colW, -(row * TICK_H))
            w:Show()
        end
        for i = #list + 1, #pool do pool[i]:Hide() end
        if #list == 0 then
            empty:SetText(className(classKey) .. " has no buffs worth flagging on other players. "
                .. "Anything else can still be added by name below.")
            empty:Show()
            return 36
        end
        empty:Hide()
        return math.ceil(#list / GRID_COLS) * TICK_H + 4
    end
    return grid, render
end

-- Everything being tracked, from any class, each with a button to drop it.
local function BuildActiveList(parent)
    local list = CreateFrame("Frame", nil, parent)
    local colW = math.floor(CONTENT_W / GRID_COLS)
    local pool = {}
    local function chip(i)
        local c = pool[i]
        if c then return c end
        c = CreateFrame("Frame", nil, list)
        c:SetSize(colW - 8, 22)
        c:EnableMouse(true)
        c:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            -- a listed buff gets its level-appropriate rank; one added by name or id is shown as it is
            local listed = ns.FindPreset(e.key) and e.key or nil
            ShowBuffTooltip(self, listed, e.label or e.key, e.names, e.ids)
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(16, 16)
        c.icon:SetPoint("LEFT", 6, 0)
        c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        c.text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        c.text:SetPoint("LEFT", c.icon, "RIGHT", 5, 0)
        c.text:SetWidth(colW - 8 - 16 - 5 - 6 - 24)
        c.text:SetJustifyH("LEFT")
        c.text:SetWordWrap(false)
        c.del = CreateFrame("Button", nil, c)
        c.del:SetSize(16, 16)
        c.del:SetPoint("RIGHT", 0, 0)
        c.del:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        c.del:GetNormalTexture():SetVertexColor(0.9, 0.4, 0.4)
        c.del:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        c.del:SetScript("OnClick", function()
            if c.entry then ns.RemoveTracked(c.entry.key); Applied(); Changed() end
        end)
        pool[i] = c
        return c
    end
    local empty = Text(list, "GameFontDisableSmall")
    empty:SetWidth(CONTENT_W - 20)
    empty:SetPoint("TOPLEFT", 8, -4)
    empty:SetText("Nothing is being tracked yet. Pick a class above and tick the buffs you want flagged.")

    local function render()
        local n = #ns.db.tracked
        for i, e in ipairs(ns.db.tracked) do
            local c = chip(i)
            c.entry = e
            c.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
            c.text:SetText(e.label or e.key)
            c:SetAlpha(e.enabled == false and 0.5 or 1)
            local col, row = (i - 1) % GRID_COLS, math.floor((i - 1) / GRID_COLS)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", list, "TOPLEFT", 4 + col * colW, -(row * CHIP_H))
            c:Show()
        end
        for i = n + 1, #pool do pool[i]:Hide() end
        empty:SetShown(n == 0)
        if n == 0 then return 28 end
        return math.ceil(n / GRID_COLS) * CHIP_H + 4
    end
    return list, render
end

-- Adding by name or spell id, for anything the classes do not list.
local function BuildAddBox(parent)
    local add = CreateFrame("Frame", nil, parent)
    local box = CreateFrame("EditBox", nil, add, "InputBoxTemplate")
    box:SetSize(220, 22)
    box:SetPoint("TOPLEFT", 12, -4)
    box:SetAutoFocus(false)
    local btn = CreateFrame("Button", nil, add, "UIPanelButtonTemplate")
    btn:SetSize(70, 22)
    btn:SetPoint("LEFT", box, "RIGHT", 6, 0)
    btn:SetText("Add")
    local hint = Text(add, "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 12, -32)
    hint:SetWidth(CONTENT_W - 20)
    hint:SetText("Buff name or spell ID. A name matches every rank; an ID also survives combat.")

    local function doAdd()
        local text = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return end
        local entry, err = ns.EntryFromInput(text)
        if not entry then ns.Print(err); return end
        ns.AddTracked(entry)
        box:SetText("")
        box:ClearFocus()
        Applied(); Changed()
        ns.Print("now flagging |cffffd100" .. entry.label .. "|r.")
    end
    btn:SetScript("OnClick", doAdd)
    box:SetScript("OnEnterPressed", doAdd)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return add, function() return 56 end
end

-- Sending your buff list to another player: a name, a button to take the one you are targeting, a
-- button to send, and the line saying how it is going (see Share.lua).
local function BuildShareRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(190, 22)
    box:SetPoint("TOPLEFT", 12, -6)
    box:SetAutoFocus(false)
    if ChatFontNormal then box:SetFontObject(ChatFontNormal) end
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local status = Text(row, "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 12, -38)
    status:SetWidth(CONTENT_W - 24)
    status:SetHeight(34)
    status:SetJustifyV("TOP")
    local function say(text) ns.shareStatus = text; status:SetText(text) end
    local function send()
        box:ClearFocus()
        local ok, err = ns.SendBuffs(box:GetText())
        if not ok then say(err) end
    end
    box:SetScript("OnEnterPressed", send)
    local function button(text, x, onClick)
        local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        b:SetSize(70, 22)
        b:SetPoint("TOPLEFT", x, -6)
        b:SetText(text)
        b:SetScript("OnClick", function() Sound("IG_MAINMENU_OPTION_CHECKBOX_ON"); onClick() end)
        return b
    end
    button("Target", 210, function()
        local name = ns.ShareTargetName()
        if name then box:SetText(name) else say("Target a player first.") end
    end)
    button("Send", 286, send)
    ns.ShareSink = function(text) status:SetText(text) end
    local function render()
        status:SetText(ns.shareStatus ~= "" and ns.shareStatus
            or "They are asked first. Only buffs they don't already track are added; nothing of theirs is changed.")
        return 80
    end
    return row, render
end

--------------------------------------------------------------------------
-- 7. PAGES
--------------------------------------------------------------------------
-- What the Reset button does once confirmed.
function ns.ResetAppearance()
    for _, key in ipairs(APPEARANCE_KEYS) do ns.db[key] = ns.defaults[key] end
    Applied()
    if frame and frame:IsShown() then Panel.Refresh() end
end

-- Start the expiring-look test, as the Test button and /ub test do.
function ns.RunExpiryTest()
    if not ns.db.flagExpiring then
        ns.Print("turn on |cffffd100Also flag buffs about to expire|r first; there is nothing to test while it is off.")
        return
    end
    ns.StartExpiryTest()
    ns.RefreshAll()
end

local function definePages()
    local classList = ns.ClassList()
    local defaultClass = ns.PlayerClass() or classList[1].key   -- start on your own class
    local function currentClass() return ns.db.browseClass or defaultClass end
    local function className(key)
        for _, c in ipairs(classList) do if c.key == key then return c.name end end
        return key
    end
    local classChoices = {}
    for _, c in ipairs(classList) do classChoices[#classChoices + 1] = { value = c.key, text = c.label } end

    -- The style as it is actually drawn: a round one the client has no art for is Square.
    local function style()
        local s = ns.db.iconStyle
        return ns.IconStyleSupported(s) and s or "SQUARE"
    end
    local function isRing() return style() == "RING" end
    local function hasOutline() return style() == "SQUARE" or style() == "ROUND" end
    local function outlineOn() return hasOutline() and ns.db.outline and true or false end
    local function custom() return ns.db.anchor == "CUSTOM" end
    local function flagging() return ns.db.flagExpiring and true or false end

    local grid, renderGrid = BuildBuffGrid(page.content, className, currentClass)
    local active, renderActive = BuildActiveList(page.content)
    local addBox, renderAdd = BuildAddBox(page.content)
    local shareRow, renderShare = BuildShareRow(page.content)

    -- Two clicks rather than a popup: a StaticPopup shown from addon code can hang the client
    -- in Gamepad mode, and this needs no dialog of its own. The first click arms the button
    -- and says so; it disarms itself if the second never comes.
    local RESET_LABEL = "Reset position and look"
    local confirming, armed = false, 0
    local function resetClick()
        if confirming then
            confirming = false
            ns.ResetAppearance()
            return
        end
        confirming = true
        armed = armed + 1
        local mine = armed
        C_Timer.After(4, function()
            if armed == mine and confirming then
                confirming = false
                if frame and frame:IsShown() then Panel.Refresh() end
            end
        end)
    end

    pages = {
        {
            key = "buffs", title = "Buffs",
            desc = "Pick the buffs you care about. A friendly player who is missing one gets its icon beside their nameplate; a fully buffed player shows nothing at all.",
            sections = {
                { title = "Buffs to flag", key = "flag", rows = {
                    { kind = "choice", label = "Class",
                      desc = "Lists every buff this class casts on other players. Tick any number, and switch class to add more: the choices accumulate. It starts on your own class.",
                      tip = "Hover a buff for its tooltip, at the rank that suits your level.",
                      choices = classChoices, get = currentClass, set = function(v) ns.db.browseClass = v end },
                    { kind = "custom", frame = grid, render = renderGrid },
                } },
                { title = function() return "Active buffs (" .. #ns.db.tracked .. ")" end, key = "active", rows = {
                    { kind = "custom", frame = active, render = renderActive },
                } },
                { title = "Add another buff", key = "add", rows = {
                    { kind = "custom", frame = addBox, render = renderAdd },
                } },
            },
        },
        {
            key = "look", title = "Look", preview = true,
            desc = "How the icons look, how they sit together, and where they go on the nameplate. The preview above shows every change as you make it.",
            sections = {
                { title = "Icons", key = "icons", rows = {
                    Slider("iconSize", "Icon size", "How big each icon is, in pixels.", 8, 40, 1),
                    Slider("alpha", "Opacity", "How opaque the icons are. A buff about to expire can fade further; see the Expiring page.", 0.2, 1, 0.05,
                        { fmt = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end }),
                    Choice("layout", "Layout", "How several missing buffs sit side by side. Overlapped lets each icon cover the edge of the last.",
                        Choices(ns.LAYOUTS)),
                    Slider("spacing", "Spacing", "The gap between icons, in pixels.", 0, 12, 1,
                        { vis = function() return ns.db.layout ~= "OVERLAP" end }),
                    Slider("maxIcons", "Most icons shown",
                        "The most things drawn at once. When more buffs are missing than that, the last slot becomes a red +N chip standing for the rest. All the way up means no limit.",
                        ns.MIN_ICON_LIMIT, ns.NO_ICON_LIMIT, 1,
                        { fmt = function(v) return v >= ns.NO_ICON_LIMIT and "No limit" or tostring(v) end }),
                } },
                { title = "Style", key = "style", rows = {
                    Choice("iconStyle", "Icon style",
                        "Square is the stock spell icon. Round clips it to a circle. Gold ring puts a ring round the round icon. The round styles use Blizzard's own circle art.",
                        Choices(ns.ICON_STYLES, ns.IconStyleSupported)),
                    Choice("ringColor", "Ring color",
                        "Plain gold, or the color of the class that casts the buff (white for a Priest's buff, orange for a Druid's) so you can tell who to ask. A buff you added by name has no known class and keeps the gold ring.",
                        Choices(ns.RING_COLORS), { vis = isRing }),
                    Toggle("outline", "Black outline",
                        "A black outline along the icon's edge, so it stands out against a busy background. It is laid over the icon's edge, so the art keeps its size and only its outermost pixels are covered. The gold ring has an edge of its own.",
                        { vis = hasOutline }),
                    Slider("outlineSize", "Outline thickness", "How thick the outline is, in pixels. A small icon holds it to a quarter of its size.", 1, 4, 1,
                        { vis = outlineOn }),
                    Slider("iconZoom", "Icon zoom",
                        "Crops into the icon art. At 0% you see the whole texture, Blizzard's own border included; higher values magnify the middle. It does not change the icon's size.",
                        0, ns.MAX_ZOOM, 1, { fmt = function(v) return v .. "%" end }),
                } },
                { title = "Position", key = "position", rows = {
                    Choice("anchor", "Anchor", function()
                        for _, a in ipairs(ns.ANCHORS) do if a.key == ns.db.anchor then return a.help end end
                    end, Choices(ns.ANCHORS)),
                    Slider("xOffset", "Horizontal offset", "How far right (or left, below zero) of the plate's centre the icons sit.", -200, 200, 1, { vis = custom }),
                    Slider("yOffset", "Vertical offset", "How far above (or below, under zero) the plate's centre the icons sit.", -100, 100, 1, { vis = custom }),
                } },
            },
        },
        {
            key = "expiring", title = "Expiring", preview = true,
            desc = "A buff that is about to run out can be flagged too, with the minutes left on it, so it reads differently from one that was never cast.",
            sections = {
                { title = "Buffs about to expire", key = "expiring", rows = {
                    Toggle("flagExpiring", "Also flag buffs about to expire",
                        "Keeps the icon showing, with the minutes left on it, once a buff drops below the threshold. A buff whose remaining time this client won't report is never flagged.",
                        { tip = "Press Test expiring look in the preview to see it without waiting." }),
                    Slider("expiringMinutes", "Warn under (minutes)", "How little time must be left before the buff is flagged.", 1, 30, 1, { vis = flagging }),
                    Choice("expireStyle", "Show them as",
                        "Amber tint turns the icon amber. Faded icon makes it more transparent instead. Countdown sweep leaves the icon alone and darkens it like a clock as time runs out, with the label turning amber, then orange under two minutes and red under one.",
                        Choices(ns.EXPIRE_STYLES), { vis = flagging }),
                    Slider("expireAlpha", "Faded opacity", "How opaque a faded icon is. Only the icon fades: the minutes label stays fully readable.", 10, 100, 5,
                        { fmt = function(v) return v .. "%" end,
                          vis = function() return flagging() and ns.db.expireStyle == "FADE" end }),
                } },
            },
        },
        {
            key = "share", title = "Share",
            desc = "Send your list of tracked buffs to another player who has Unbuffed. They are asked first, and only buffs they don't already track are added.",
            sections = {
                { title = "Send your buffs", key = "send", rows = {
                    { kind = "custom", frame = shareRow, render = renderShare },
                } },
                { title = "Receiving", key = "receive", rows = {
                    Toggle("shareReceive", "Let other players offer me their buffs",
                        "When someone offers to share their buffs you get an Accept / Decline prompt. Nothing arrives unless you accept, and only buffs you don't already track are added. Off declines every offer."),
                } },
            },
        },
        {
            key = "general", title = "General",
            desc = "Who gets an icon, and putting the look back the way it was.",
            sections = {
                { title = "General", key = "general", rows = {
                    Toggle("hideSelf", "Skip my own nameplate", "Leaves the personal resource display alone."),
                    Toggle("groupOnly", "Only show for party and raid members",
                        "Skips everyone who is not in your party or raid, so strangers' plates never get an icon. With this on and no group, nothing is shown. Your own plate is covered by the option above."),
                    Button("Reset position and look", "Puts the position, size, opacity, style, layout and expiry settings back to their defaults. Which buffs you track and who is flagged are left alone.",
                        function() return confirming and "|cffff5555Click again to confirm|r" or RESET_LABEL end, resetClick),
                } },
            },
        },
    }
    pageByKey = {}
    for _, p in ipairs(pages) do pageByKey[p.key] = p end
end

--------------------------------------------------------------------------
-- 8. THE MIDDLE COLUMN: the page
--------------------------------------------------------------------------
local function SectionClick(h)
    if not h.sectionKey then return end
    Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    closed[h.sectionKey] = not closed[h.sectionKey] or nil
    Panel.Refresh()
end

local function SectionHeader(parent, text, y, sectionKey)
    pools.section = pools.section or {}
    local h = table.remove(pools.section)
    if not h then
        h = CreateFrame("Frame", nil, parent)
        h:SetHeight(SECTION_H)
        h.kind = "section"
        h.text = Text(h, "GameFontNormal")
        h.text:SetPoint("BOTTOMLEFT", 6, 6)
        h.sign = Text(h, "GameFontNormal")
        h.sign:SetPoint("BOTTOMRIGHT", -10, 6)
        h.line = Line(h)
        h.line:SetPoint("BOTTOMLEFT", 0, 2)
        h.line:SetPoint("BOTTOMRIGHT", 0, 2)
        h.hover = h:CreateTexture(nil, "BACKGROUND")
        h.hover:SetAllPoints()
        h.hover:SetColorTexture(1, 0.82, 0, 0.06)
        h.hover:Hide()
        h:EnableMouse(true)
        h:SetScript("OnEnter", function(self) self.hover:Show() end)
        h:SetScript("OnLeave", function(self) self.hover:Hide() end)
        h:SetScript("OnMouseUp", SectionClick)
    end
    h:SetParent(parent)
    h.sectionKey = sectionKey
    h.sign:SetText(sectionKey and (closed[sectionKey] and "+" or "-") or "")
    h.text:SetText(text)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", 0, y)
    h:SetWidth(CONTENT_W)
    h:Show()
    used[#used + 1] = h
    return SECTION_H
end

-- Lays rows out from y down and returns the new y.
local function PlaceRows(parent, rows, y)
    for _, row in ipairs(rows) do
        if row.kind == "custom" then
            local f = row.frame
            f:SetParent(parent)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 0, y)
            f:SetWidth(CONTENT_W)
            local h = row.render()
            f:SetHeight(h)
            f:Show()
            customShown[#customShown + 1] = f
            y = y - h
        else
            local f = Acquire(parent, row.kind)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", 0, y)
            f:SetWidth(CONTENT_W)
            FillRow(f, row)
            y = y - f:GetHeight()
        end
    end
    return y
end

local function visibleRows(section)
    local out = {}
    for _, row in ipairs(section.rows) do
        if not row.vis or row.vis() then out[#out + 1] = row end
    end
    return out
end

local function UpdateNav()
    for key, b in pairs(navButtons) do
        b.selected:SetShown(key == current)
        b.text:SetText(val(pageByKey[key].title))
    end
end

function Panel.Refresh()
    if not frame then return end
    ReleaseAll()
    local p = pageByKey[current]

    page.title:SetText(val(p.title))
    pv.box:SetShown(p.preview and true or false)
    page.scroll:ClearAllPoints()
    page.scroll:SetPoint("TOPLEFT", p.preview and pv.box or page.header, "BOTTOMLEFT", 0, -6)
    page.scroll:SetPoint("BOTTOMRIGHT")
    if p.preview then
        local on = ns.db.flagExpiring and true or false
        pv.test:SetAlpha(on and 1 or 0.4)
        pv.test:EnableMouse(on)
        pv.update()
    end

    local y = 0
    for _, section in ipairs(p.sections) do
        local rows = visibleRows(section)
        if #rows > 0 then
            local key = p.key .. ":" .. section.key
            y = y - SectionHeader(page.content, val(section.title), y, key)
            if not closed[key] then y = PlaceRows(page.content, rows, y) - 4 end
        end
    end
    page.content:SetHeight(math.max(1, -y + 8))
    if page.scrollLine then page.scrollLine.Update() end
    UpdateNav()
end

function Panel.Select(key)
    if not pageByKey[key] then return end
    current = key
    ns.db.optionsPage = key
    page.scroll:SetVerticalScroll(0)
    Panel.Refresh()
    ShowPageInfo()
end

--------------------------------------------------------------------------
-- 9. THE WINDOW
--------------------------------------------------------------------------
-- A thin scroll line beside the page, like FlareUI's: a faint track and a bronze thumb, shown
-- only when there is something to scroll; the wheel scrolls the page.
local function AttachScrollLine(scroll, parent)
    local line = CreateFrame("Frame", nil, parent)
    line:SetWidth(8)
    line:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    line:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    line.track = line:CreateTexture(nil, "ARTWORK")
    line.track:SetWidth(2); line.track:SetPoint("TOP"); line.track:SetPoint("BOTTOM")
    line.track:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.25)
    line.thumb = line:CreateTexture(nil, "OVERLAY")
    line.thumb:SetWidth(2)
    line.thumb:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    function line.Update()
        local range = scroll:GetVerticalScrollRange() or 0
        local h = line:GetHeight() or 0
        if not scroll:IsShown() or range <= 0.5 or h <= 0 then line:Hide() return end
        line:Show()
        local visible = scroll:GetHeight() / (scroll:GetHeight() + range)
        local th = math.max(16, h * visible)
        line.thumb:SetHeight(th)
        line.thumb:ClearAllPoints()
        line.thumb:SetPoint("TOP", line, "TOP", 0, -(h - th) * ((scroll:GetVerticalScroll() or 0) / range))
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
    scroll:HookScript("OnVerticalScroll", line.Update)
    scroll:HookScript("OnScrollRangeChanged", line.Update)
    scroll:HookScript("OnSizeChanged", line.Update)
    return line
end

local function BuildWindow()
    current = ns.db.optionsPage or "buffs"

    frame = CreateFrame("Frame", "UnbuffedOptions", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
    frame:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 1)
    -- a dark base, Blizzard's Collections tile over it, and a black wash (FlareUI's)
    local base = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    base:SetPoint("TOPLEFT", 5, -5); base:SetPoint("BOTTOMRIGHT", -5, 5)
    base:SetColorTexture(0.06, 0.055, 0.045, 0.97)
    local art = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetAllPoints(base)
    art:SetTexture("Interface\\Collections\\CollectionsBackgroundTile", "REPEAT", "REPEAT")
    art:SetHorizTile(true); art:SetVertTile(true)
    local wash = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    wash:SetAllPoints(base)
    wash:SetColorTexture(0, 0, 0, 0.5)
    frame:Hide()
    tinsert(UISpecialFrames, "UnbuffedOptions")
    frame:SetScript("OnShow", function()
        Sound("IG_CHARACTER_INFO_OPEN")
        Panel.Refresh()
        ShowPageInfo()
    end)
    frame:SetScript("OnHide", function() Sound("IG_CHARACTER_INFO_CLOSE") end)

    -- header: name, version, close
    local title = Text(frame, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD + 4, -12)
    title:SetText("Unbuffed")
    local version = Text(frame, "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    version:SetText(meta and meta(ADDON, "Version") or "")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local headerLine = Line(frame)
    headerLine:SetPoint("TOPLEFT", 6, -HEADER_H)
    headerLine:SetPoint("TOPRIGHT", -6, -HEADER_H)

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 6, -HEADER_H - 1)
    body:SetPoint("BOTTOMRIGHT", -6, 6)

    -- left column: the pages
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LEFT_W)
    local leftLine = Line(body)
    leftLine:SetWidth(1)
    leftLine:SetPoint("TOPLEFT", left, "TOPRIGHT"); leftLine:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")

    local y = -PAD + 4
    for _, key in ipairs({ "buffs", "look", "expiring", "share", "general" }) do
        local b = CreateFrame("Button", nil, left)
        b:SetSize(LEFT_W - 2 * PAD, 24)
        b:SetPoint("TOPLEFT", PAD, y)
        b.selected = b:CreateTexture(nil, "BACKGROUND")
        b.selected:SetAllPoints()
        b.selected:SetColorTexture(1, 0.82, 0, 0.12)
        b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
        b:GetHighlightTexture():SetAlpha(0.25)
        b.text = Text(b, "GameFontHighlight")
        b.text:SetPoint("LEFT", 8, 0)
        b:SetScript("OnClick", function()
            Sound("IG_CHARACTER_INFO_TAB")
            Panel.Select(key)
        end)
        navButtons[key] = b
        y = y - 24
    end

    -- right column: what the hovered setting does
    local right = CreateFrame("Frame", nil, body)
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(RIGHT_W)
    local rightBg = right:CreateTexture(nil, "BACKGROUND")
    rightBg:SetAllPoints()
    rightBg:SetColorTexture(0, 0, 0, 0.25)
    local rightLine = Line(body)
    rightLine:SetWidth(1)
    rightLine:SetPoint("TOPRIGHT", right, "TOPLEFT"); rightLine:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    local icon = right:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", PAD, -PAD)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    info.title = Text(right, "GameFontNormalLarge")
    info.title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    info.title:SetPoint("RIGHT", -PAD, 0)
    info.title:SetWordWrap(true)
    info.desc = Text(right, "GameFontHighlight")
    info.desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
    info.desc:SetPoint("RIGHT", -PAD, 0)
    info.desc:SetSpacing(3)
    info.desc:SetTextColor(0.85, 0.85, 0.85)
    info.tip = Text(right, "GameFontNormalSmall")
    info.tip:SetPoint("TOPLEFT", info.desc, "BOTTOMLEFT", 0, -10)
    info.tip:SetPoint("RIGHT", -PAD, 0)
    info.tip:SetSpacing(2)

    -- middle column: the page, with the preview pinned above its settings where there is one
    local middle = CreateFrame("Frame", nil, body)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT", PAD, -PAD)
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -PAD - 10, PAD)

    local header = CreateFrame("Frame", nil, middle)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    header:SetHeight(34)
    page.header = header
    page.title = Text(header, "GameFontNormalHuge")
    page.title:SetPoint("LEFT", 4, 0)

    BuildPreview(middle, header)

    local scroll = CreateFrame("ScrollFrame", nil, middle)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(content)
    page.scroll, page.content = scroll, content
    page.scrollLine = AttachScrollLine(scroll, middle)

    definePages()
    if not pageByKey[current] then current = "buffs" end
end

function ns.ToggleOptions()
    if not ns.dbReady then return end
    if not frame then BuildWindow() end
    frame:SetShown(not frame:IsShown())
end

-- Open the window on a given page, from outside it (/ub share).
function ns.ShowOptionsPage(key)
    if not ns.dbReady then return end
    if not frame then BuildWindow() end
    frame:Show()
    Panel.Select(key)
end

-- Something outside the window changed a setting: redraw it.
function ns.RefreshOptions()
    if frame and frame:IsShown() then Panel.Refresh() end
end

--------------------------------------------------------------------------
-- The entry in the game's own AddOns settings: a button that opens the window
--------------------------------------------------------------------------
local stub = CreateFrame("Frame")
stub.name = "Unbuffed"
local stubText = stub:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
stubText:SetPoint("TOPLEFT", 16, -16)
stubText:SetText("Unbuffed has its own settings window.")
local stubButton = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
stubButton:SetSize(190, 24)
stubButton:SetPoint("TOPLEFT", 16, -46)
stubButton:SetText("Open Unbuffed settings")
stubButton:SetScript("OnClick", function()
    if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and HideUIPanel then
        pcall(HideUIPanel, SettingsPanel)
    end
    if not (frame and frame:IsShown()) then ns.ToggleOptions() end
end)
stub.OnRefresh = function() end
stub.OnCommit  = function() end
stub.OnDefault = function() end

if Settings and Settings.RegisterCanvasLayoutCategory then
    -- Deliberately NOT overwriting category.ID with the addon name: on 12.x Settings.OpenToCategory
    -- wants a numeric id and throws on a string.
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(stub, stub.name))
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(stub)
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
        ns.ToggleOptions()
    elseif cmd == "add" then
        local entry, err = ns.EntryFromInput(rest)
        if not entry then ns.Print(err); return end
        ns.AddTracked(entry)
        ns.RefreshAll()
        ns.RefreshOptions()
        ns.Print("now flagging |cffffd100" .. entry.label .. "|r.")
    elseif cmd == "remove" or cmd == "rem" then
        local target = rest:lower()
        for _, e in ipairs(ns.db.tracked) do
            if e.key:lower() == target or e.label:lower() == target then
                ns.RemoveTracked(e.key)
                ns.RefreshAll()
                ns.RefreshOptions()
                ns.Print("stopped flagging |cffffd100" .. e.label .. "|r.")
                return
            end
        end
        ns.Print("not tracking anything called '" .. rest .. "'.")
    elseif cmd == "test" then
        ns.RunExpiryTest()
    elseif cmd == "share" then
        if rest == "" then
            ns.ShowOptionsPage("share")
        else
            local ok, err = ns.SendBuffs(rest)
            if not ok then ns.Print(err) else ns.Print("offered your buffs to " .. rest .. "; they are asked first.") end
        end
    elseif cmd == "list" then
        if #ns.db.tracked == 0 then ns.Print("nothing tracked."); return end
        ns.Print("tracking:")
        for _, e in ipairs(ns.db.tracked) do
            print("   - " .. e.label .. (e.enabled and "" or " |cff888888(off)|r")
                .. "  |cff888888[" .. table.concat(e.names, " / ") .. "]|r")
        end
    else
        ns.Print("/ub  |cff888888(settings)|r  ·  add <name|id>  ·  remove <name>  ·  list  ·  test  ·  share [name]")
    end
end
