local ADDON, ns = ...
local L = ns.L

-- The icon row that hangs off a friendly player's nameplate.
--
-- Nameplate frames are recycled by the client, so the row is built once per plate
-- and cached on it; NAME_PLATE_UNIT_ADDED/REMOVED only rebind which unit it is
-- currently describing.

local active = {}   -- [unitToken] = plate frame, for the plates on screen right now

local GetNamePlateForUnit = C_NamePlate and C_NamePlate.GetNamePlateForUnit

-- An empty icon row. The caller sets its frame level before the first RenderRow, since the
-- slots take theirs from it as they are made. `icons` and `labels` mirror the slots'
-- icon textures and timer labels, by position.
function ns.NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(1, 1)
    row.slots, row.icons, row.labels = {}, {}, {}
    return row
end

local function getRow(plate)
    local row = plate.UnbuffedRow
    if row then return row end
    row = ns.NewRow(plate)
    -- Above the nameplate art, so the icons aren't buried by the health bar.
    row:SetFrameLevel((plate:GetFrameLevel() or 0) + 10)
    plate.UnbuffedRow = row
    return row
end

-- Icon looks. SQUARE is the stock icon with its border trimmed, which is what the
-- addon has always drawn. ROUND clips it to a circle, and RING puts a gold ring round
-- that. Both use Blizzard's own atlases -- the ones FlareUI uses for its round aura
-- icons -- so there is no art of ours to ship. The options preview builds its icons
-- through these same two functions, so it cannot drift from the real ones.
local ROUND_MASK  = "talents-node-circle-mask"
local RING_ART    = "talents-node-circle-gray"   -- grey art, so it takes a tint
local RING_TINT   = { 1.0, 0.82, 0.25 }
local IGNORE_SIZE = TextureKitConstants and TextureKitConstants.IgnoreAtlasSize

-- Those atlases are known to exist on Forever, but this addon also runs on TBC
-- Classic, where they may not. A style is offered, and drawn, only when the client
-- confirms it has the art; otherwise it quietly falls back to SQUARE.
local supported = {}
local function atlasKnown(name)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
end
function ns.IconStyleSupported(style)
    if supported[style] == nil then
        if style == "ROUND" then supported[style] = atlasKnown(ROUND_MASK)
        elseif style == "RING" then supported[style] = atlasKnown(ROUND_MASK) and atlasKnown(RING_ART)
        else supported[style] = true end
    end
    return supported[style]
end

-- An icon texture plus what a style may add to it. The icon, its mask and the round outline's
-- disc live in `parent`. The ring and the square outline's four edges live in `overlay` (the
-- parent again if none is given), which a slot makes a frame ABOVE its countdown sweep: so the
-- sweep darkens the icon only, and never the ring or the outline round it.
function ns.NewIcon(parent, overlay)
    overlay = overlay or parent
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetDrawLayer("OVERLAY", 0)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim the stock icon border
    t.mask = parent:CreateMaskTexture()
    t.ring = overlay:CreateTexture(nil, "OVERLAY")
    t.ring:SetDrawLayer("OVERLAY", 1)       -- over the icon, under the minutes label
    t.ring:Hide()
    t.host = parent
    -- ROUND's outline: a black disc behind the icon, as big as the slot; the icon's own circular
    -- mask is drawn in from the edge, so the disc shows as a ring there. Clipped to a circle by
    -- a mask of its own, made the first time it is needed.
    t.edge = parent:CreateTexture(nil, "BORDER")
    t.edge:SetColorTexture(0, 0, 0, 1)
    t.edge:SetAllPoints(parent)
    t.edge:Hide()
    -- SQUARE's outline: four black bars laid over the icon's own edge, on top of it.
    t.bars = {}
    for i = 1, 4 do
        local bar = overlay:CreateTexture(nil, "OVERLAY")
        bar:SetDrawLayer("OVERLAY", 0)
        bar:SetColorTexture(0, 0, 0, 1)
        bar:Hide()
        t.bars[i] = bar
    end
    return t
end

-- Lay the four bars along the icon's edges, `px` thick: top and bottom full width, left and
-- right between them, so the corners are not drawn twice.
local function sizeBars(t, px)
    local top, bottom, left, right = t.bars[1], t.bars[2], t.bars[3], t.bars[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
    top:SetHeight(px)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(px)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -px)
    left:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, px)
    left:SetWidth(px)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, -px)
    right:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, px)
    right:SetWidth(px)
end

-- Apply a style to an icon from NewIcon. `tr, tg, tb` recolour the ring of the RING style.
-- `outline` gives the SQUARE and ROUND styles a black outline `outlineSize` pixels thick, held
-- to a quarter of `size` so a small icon is never swallowed by it. Safe to call every sweep:
-- the mask, ring and outline are set up once and after that only switched on or off.
function ns.StyleIcon(t, style, alpha, zoom, tr, tg, tb, outline, outlineSize, size)
    local mask, ring = t.mask, t.ring
    if not ns.IconStyleSupported(style) then style = "SQUARE" end

    -- Zoom is how much of the art's edge is cropped away, in percent per side: 0 shows
    -- the whole texture, Blizzard's own border included, and more magnifies the middle.
    -- It crops the art; it does not resize the icon, which is the size slider's job.
    -- Clamped so a bad saved value can never invert the crop.
    local inset = math.min(ns.MAX_ZOOM / 100, math.max(0, (tonumber(zoom) or ns.defaults.iconZoom) / 100))
    if t.inset ~= inset then
        t:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
        t.inset = inset
    end
    if style == "ROUND" or style == "RING" then
        if not t.masked then
            if not mask.ready then
                mask:SetAtlas(ROUND_MASK, IGNORE_SIZE)
                mask:SetAllPoints(t)
                mask.ready = true
            end
            t:AddMaskTexture(mask)
            t.masked = true
        end
    elseif t.masked then
        t:RemoveMaskTexture(mask)
        t.masked = false
    end

    if style == "RING" then
        if not ring.ready then
            ring:SetAtlas(RING_ART, IGNORE_SIZE)
            ring:SetAllPoints(t)
            ring.ready = true
        end
        -- Gold unless a colour is given (the class of the buff, when that is chosen).
        local r, g, b = tr or RING_TINT[1], tg or RING_TINT[2], tb or RING_TINT[3]
        if ring.cr ~= r or ring.cg ~= g or ring.cb ~= b then
            ring:SetVertexColor(r, g, b)
            ring.cr, ring.cg, ring.cb = r, g, b
        end
        ring:SetAlpha(alpha or 1)
        ring:Show()
    else
        ring:Hide()
    end

    -- The outline. Clamped, so a bad saved value can neither hide it nor swallow the icon.
    local px = 0
    local round = style == "ROUND"
    if outline and (style == "SQUARE" or round) then
        px = math.floor(tonumber(outlineSize) or ns.defaults.outlineSize)
        px = math.min(4, math.floor((size or ns.defaults.iconSize) / 4), math.max(1, px))
        px = math.max(1, px)
    end

    -- A round outline lies over the icon's edge, as the square one does: the art stays exactly as
    -- big as it was, and only the circle that clips it is drawn in by the thickness, so the black
    -- disc behind shows as a ring. (Drawing the art smaller instead reads as a zoom.)
    local pad = (round and px > 0) and px or 0
    if t.pad ~= pad then
        mask:ClearAllPoints()
        if pad == 0 then
            mask:SetAllPoints(t)
        else
            mask:SetPoint("TOPLEFT", t, "TOPLEFT", pad, -pad)
            mask:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -pad, pad)
        end
        t.pad = pad
    end

    local edge = t.edge
    if round and px > 0 then
        if not t.edgeMask then
            t.edgeMask = t.host:CreateMaskTexture()
            t.edgeMask:SetAtlas(ROUND_MASK, IGNORE_SIZE)
            t.edgeMask:SetAllPoints(edge)
            edge:AddMaskTexture(t.edgeMask)
        end
        edge:SetAlpha(alpha or 1)
        edge:Show()
    else
        edge:Hide()
    end

    if style == "SQUARE" and px > 0 then
        if t.barPx ~= px then
            sizeBars(t, px)
            t.barPx = px
        end
        for _, bar in ipairs(t.bars) do
            bar:SetAlpha(alpha or 1)
            bar:Show()
        end
    else
        for _, bar in ipairs(t.bars) do bar:Hide() end
    end
end

-- The ring and the outline are their own regions, so hiding the icon alone would leave them.
function ns.HideIcon(t)
    t:Hide()
    t.ring:Hide()
    t.edge:Hide()
    for _, bar in ipairs(t.bars) do bar:Hide() end
end

-- Amber for "running out", so it reads as a warning rather than the plain
-- full-colour icon that means "not buffed at all".
local EXPIRING_TINT = { 1.0, 0.72, 0.15 }

-- What an about-to-expire icon looks like: its vertex colour and a multiplier for its
-- opacity. TINT recolours it amber at full opacity; FADE leaves the colour alone and
-- lowers the opacity instead. SWEEP leaves the icon alone entirely: its signal is the
-- countdown drawn over it (see RenderRow). Shared with the options preview. The label that says how
-- many minutes are left is not part of this -- it is deliberately left untouched.
function ns.ExpiringLook(db)
    if db.expireStyle == "SWEEP" then return 1, 1, 1, 1 end   -- the sweep is the signal, not the icon
    if db.expireStyle == "FADE" then
        -- clamped, so a bad saved value can neither hide the icon nor exceed full opacity
        local pct = math.min(100, math.max(10, tonumber(db.expireAlpha) or ns.defaults.expireAlpha))
        return 1, 1, 1, pct / 100
    end
    return EXPIRING_TINT[1], EXPIRING_TINT[2], EXPIRING_TINT[3], 1
end

-- The colour of the minutes-left label while a buff runs out, in SWEEP style: amber, then
-- orange under two minutes, then red under one.
function ns.UrgencyColor(left)
    if left <= 60 then return 1.0, 0.30, 0.28 end
    if left <= 120 then return 1.0, 0.55, 0.15 end
    return 1.0, 0.82, 0.30
end

-- How far right of the row's left edge slot i (1-based) sits. OVERLAP steps by part of an
-- icon, so the next one covers the edge of the last, and ignores the spacing setting.
function ns.SlotOffset(layout, i, size, spacing)
    if layout == "OVERLAP" then
        return (i - 1) * math.floor(size * 0.6 + 0.5)
    end
    return (i - 1) * (size + spacing)   -- ROW, and anything unrecognised
end

-- How wide a row of n slots is. It is always one icon tall.
function ns.RowWidth(layout, n, size, spacing)
    if n < 1 then return size end
    return ns.SlotOffset(layout, n, size, spacing) + size
end

-- Testing the expiring look. Waiting for a real buff to run down is not a test, so this
-- pretends the first buff you track has the whole warning window left and lets it run out
-- over TEST_SECONDS, on every plate that would show an icon and in the options preview.
local TEST_SECONDS = 20
local testStart

function ns.StartExpiryTest() testStart = GetTime() end

function ns.TestActive()
    return testStart ~= nil and GetTime() - testStart < TEST_SECONDS
end

-- Seconds the pretend buff has left, or nil when no test is running.
function ns.TestLeft(db)
    if not ns.TestActive() then
        testStart = nil
        return nil
    end
    -- multiplied out before dividing, so a whole number of seconds stays whole
    return math.max(1, db.expiringMinutes * 60 * (TEST_SECONDS - (GetTime() - testStart)) / TEST_SECONDS)
end

-- One icon's place in the row. Everything that belongs to the icon lives in this frame, so
-- it can be moved and layered as one piece, from the bottom up:
--   icon  the spell texture, with its mask (and a round outline's disc behind it)
--   cd    the countdown sweep, made only when first needed, over the icon
--   top   a frame above both, holding the ring, the square outline and the minutes-left label,
--         so the sweep never darkens any of them
local function getSlot(row, i)
    local h = row.slots[i]
    if h then return h end
    h = CreateFrame("Frame", nil, row)
    h:SetSize(1, 1)
    h:SetFrameLevel(row:GetFrameLevel() + 1 + (i - 1) * 4)
    h.top = CreateFrame("Frame", nil, h)
    h.top:SetAllPoints(h)
    h.top:SetFrameLevel(h:GetFrameLevel() + 3)
    h.icon = ns.NewIcon(h, h.top)
    h.icon:SetAllPoints(h)
    -- Minutes left, drawn above the icon so an expiring buff says how urgent it is.
    h.label = h.top:CreateFontString(nil, "OVERLAY")
    h.label:SetDrawLayer("OVERLAY", 2)
    h.label:Hide()
    row.slots[i], row.icons[i], row.labels[i] = h, h.icon, h.label
    return h
end

local SWEEP_REVERSE = true   -- the dark wedge grows as time is used up, rather than shrinks
local ROUND_SWEEP   = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function makeCooldown(h)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, h, "CooldownFrameTemplate")
    if not ok or not cd then return nil end
    cd:SetAllPoints(h)
    cd:SetFrameLevel(h:GetFrameLevel() + 1)
    cd.noCooldownCount = true   -- the minutes label is ours; keep cooldown-text addons off it
    pcall(cd.SetHideCountdownNumbers, cd, true)
    pcall(cd.SetDrawEdge, cd, false)
    pcall(cd.SetDrawBling, cd, false)
    pcall(cd.SetReverse, cd, SWEEP_REVERSE)
    return cd
end

-- Show the sweep for a buff with `left` seconds of a `window`-second warning period left. It
-- is set once and then runs by itself; it is only set again if the buff's end has moved,
-- which a refreshed buff does. `freeze` holds it still, for the preview and the test, where
-- the time shown is made up and changes faster than a real clock.
local function setSweep(h, on, left, window, round, freeze)
    if not on then
        if h.cd then h.cd:Hide(); h.cdEnd = nil end
        return
    end
    local cd = h.cd
    if not cd then
        cd = makeCooldown(h)
        h.cd = cd
        if not cd then return end
    end
    if h.cdRound ~= round then
        pcall(cd.SetSwipeTexture, cd, round and ROUND_SWEEP or "Interface\\Buttons\\WHITE8X8")
        pcall(cd.SetUseCircularEdge, cd, round and true or false)
        pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0.65)
        h.cdRound = round
    end
    local endAt = GetTime() + left
    if not h.cdEnd or math.abs(h.cdEnd - endAt) > 1.5 or h.cdWindow ~= window or h.cdFrozen ~= freeze then
        if h.cdFrozen and not freeze and cd.Resume then pcall(cd.Resume, cd) end
        cd:SetCooldown(endAt - window, window)
        if freeze and cd.Pause then pcall(cd.Pause, cd) end
        h.cdEnd, h.cdWindow, h.cdFrozen = endAt, window, freeze
    end
    cd:Show()
end

local function hideSlot(h)
    ns.HideIcon(h.icon)
    h.label:Hide()
    if h.cd then h.cd:Hide(); h.cdEnd = nil end
    h:Hide()
end

local CHIP_COLOR = { 0.72, 0.18, 0.12 }

-- Draw a row. `items` holds `count` entries of { icon, class, expiring, left, freeze }: the
-- buffs to show, in order. Both the nameplates and the options preview draw through here, so
-- the preview cannot show something the plates do not. Handles the layout, the cap with its
-- "+N" chip, the icon style, ring colour and outline, and the expiring look. Returns how many
-- slots it used; the caller places the row. `opts.freeze` holds every countdown sweep still.
function ns.RenderRow(row, items, count, db, opts)
    local size, spacing, layout = db.iconSize, db.spacing, db.layout
    local limit = math.max(ns.MIN_ICON_LIMIT, tonumber(db.maxIcons) or ns.NO_ICON_LIMIT)
    local drawn, extra = count, 0
    if limit < ns.NO_ICON_LIMIT and count > limit then
        drawn = limit - 1
        extra = count - drawn
    end
    local n = drawn + (extra > 0 and 1 or 0)

    local style = db.iconStyle
    if not ns.IconStyleSupported(style) then style = "SQUARE" end
    local round = style == "ROUND" or style == "RING"
    local sweep = db.expireStyle == "SWEEP"
    local classRing = style == "RING" and db.ringColor == "CLASS"
    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

    for i = 1, n do
        local h = getSlot(row, i)
        local it = i <= drawn and items[i] or nil
        local t, fs = h.icon, h.label

        h:SetSize(size, size)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", row, "TOPLEFT", ns.SlotOffset(layout, i, size, spacing), 0)

        -- The ring takes the colour of the class that casts the buff, where that is known.
        local tr, tg, tb
        if it and classRing then tr, tg, tb = ns.ClassColor(it.class) end

        -- The icon's own look: the opacity setting, and for one about to expire whatever
        -- ns.ExpiringLook says on top of it. The icon, its ring and its outline all take this
        -- opacity, so they fade together.
        local alpha, r, g, b = db.alpha, 1, 1, 1
        if it then
            t:SetTexture(it.icon)
            if it.expiring then
                local er, eg, eb, ea = ns.ExpiringLook(db)
                r, g, b, alpha = er, eg, eb, db.alpha * ea
            end
        else
            t:SetColorTexture(CHIP_COLOR[1], CHIP_COLOR[2], CHIP_COLOR[3], 1)
        end
        t:SetAlpha(alpha)
        t:SetVertexColor(r, g, b)
        ns.StyleIcon(t, style, alpha, db.iconZoom, tr, tg, tb, db.outline, db.outlineSize, size)

        if it then
            if it.expiring then
                local left = it.left
                fs:SetFont(fontPath, math.max(7, math.floor(size * 0.46)), "OUTLINE")
                fs:ClearAllPoints()
                if layout == "OVERLAP" then
                    fs:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", -2, -2)   -- the next icon covers the right
                else
                    fs:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 2, -2)
                end
                if sweep then
                    fs:SetText(left < 60 and L["%ds"]:format(math.max(1, math.ceil(left))) or L["%dm"]:format(math.ceil(left / 60)))
                    fs:SetTextColor(ns.UrgencyColor(left))
                else
                    fs:SetText(L["%dm"]:format(math.max(1, math.ceil(left / 60))))
                    fs:SetTextColor(1, 1, 1)
                end
                fs:SetAlpha(1)   -- only the icon fades, never the timer beside it
                fs:Show()
                setSweep(h, sweep, left, db.expiringMinutes * 60, round, (opts and opts.freeze) or it.freeze or false)
            else
                fs:Hide()
                setSweep(h, false)
            end
        else
            -- the "+N" chip standing for everything past the cap
            fs:SetFont(fontPath, math.max(8, math.floor(size * 0.5)), "OUTLINE")
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", t, "CENTER", 0, 0)
            fs:SetText("+" .. extra)
            fs:SetTextColor(1, 1, 1)
            fs:SetAlpha(1)
            fs:Show()
            setSweep(h, false)
        end

        h:Show()
        t:Show()
    end

    for i = n + 1, #row.slots do hideSlot(row.slots[i]) end

    row:SetSize(ns.RowWidth(layout, n, size, spacing), size)
    return n
end

-- The parts of a nameplate an icon row can attach to, found the way FlareUI finds
-- them on WoW Forever: the health bar sits at UnitFrame.HealthBarsContainer.healthBar
-- and the level box is UnitFrame.PlayerLevelDiffFrame. Either may be absent -- a
-- friendly plate often has no level box, and one in name-only mode has no bar -- and
-- a part that isn't showing has no meaningful edge, so it counts as absent too. The
-- placement below falls back from the level box to the bar to the plate itself.
function ns.PlateParts(plate)
    local unitFrame = plate.UnitFrame
    if not unitFrame then return nil, nil end
    local container = unitFrame.HealthBarsContainer
    local bar = container and container.healthBar
    if bar and (bar:IsForbidden() or not bar:IsShown()) then bar = nil end
    local level = unitFrame.PlayerLevelDiffFrame
    if level and (level:IsForbidden() or not level:IsShown()) then level = nil end
    return bar, level
end

local PRESET_GAP = 4   -- pixels between the icon row and the part it sits against

-- Place `row` according to db.anchor. `bar` and `level` may be nil. Shared with the
-- options panel's preview, which hands in a mock plate, so what the preview shows is
-- decided by exactly this code and cannot drift from what the real plates do.
--
-- The row grows away from the part it sits against: rightwards past the level box,
-- leftwards from the bar's left end, and outwards from the middle when centred.
-- Only CUSTOM reads the offsets; the presets are meant to need none.
function ns.PlaceRow(row, plate, bar, level, db)
    row:ClearAllPoints()
    local anchor = db.anchor
    if anchor == "LEVEL_RIGHT" then
        row:SetPoint("LEFT", level or bar or plate, "RIGHT", PRESET_GAP, 0)
    elseif anchor == "BAR_LEFT" then
        row:SetPoint("RIGHT", bar or plate, "LEFT", -PRESET_GAP, 0)
    elseif anchor == "BAR_BELOW" then
        row:SetPoint("TOP", bar or plate, "BOTTOM", 0, -PRESET_GAP)
    else
        row:SetPoint("CENTER", plate, "CENTER", db.xOffset, db.yOffset)
    end
end

local function hideRow(plate)
    local row = plate and plate.UnbuffedRow
    if row then row:Hide() end
end

-- Whether the client says this unit is in your party or raid: true or false, or nil when it
-- will not say. A secret answer is treated as no answer, as everywhere else here, because
-- guessing would show an icon on a stranger or hide one on a friend. UnitInRaid gives the
-- raid index (0 is a real member, and 0 is truthy in Lua) or nil, while UnitInParty gives a
-- boolean on newer clients and 1 or nil on older ones; either way, truthiness is the test.
local function inYourGroup(unit)
    local party, raid = UnitInParty(unit), UnitInRaid(unit)
    if ns.IsSecret(party) or ns.IsSecret(raid) then return nil end
    return (party and true or false) or raid ~= nil
end

local items = {}   -- scratch list handed to RenderRow, reused so a sweep makes no garbage

local function updatePlate(unit, plate)
    if not plate then return end
    local db = ns.db

    -- Unit identity can be restricted too, and then UnitIsPlayer answers nothing
    -- rather than false. Only a real boolean counts: an unknown unit is not a
    -- friendly player as far as we're concerned.
    if ns.Truth(UnitIsPlayer(unit)) ~= true then hideRow(plate); return end
    if ns.Truth(UnitIsFriend("player", unit)) ~= true then hideRow(plate); return end
    if db.hideSelf and ns.Truth(UnitIsUnit(unit, "player")) == true then hideRow(plate); return end
    -- Only a definite yes counts: a client that will not say is not "in your group".
    if db.groupOnly and inYourGroup(unit) ~= true then hideRow(plate); return end

    local row = getRow(plate)

    -- Work out what is missing, then let RenderRow draw it. Only a definite "missing" counts:
    -- nil means the client refused to answer, and guessing there would flag people who are
    -- actually buffed. An aura with no readable duration is likewise left alone.
    local count = 0
    local window = db.expiringMinutes * 60
    local testLeft = db.flagExpiring and ns.TestLeft(db) or nil   -- a test in progress, if any
    for _, entry in ipairs(db.tracked) do
        if entry.enabled and ns.EntryUsable(entry) then
            local expiring, left, found, aura, simulated
            if testLeft then
                -- the first buff tracked stands in for one running out, whatever the unit has
                found, expiring, left, simulated = true, true, testLeft, true
                testLeft = nil
            else
                found, aura = ns.HasBuff(unit, entry)
                if found == true and db.flagExpiring then
                    local remaining = ns.AuraRemaining(aura)
                    if remaining and remaining > 0 and remaining <= window then
                        expiring, left = true, remaining
                    end
                end
            end
            if found == false or expiring then
                count = count + 1
                local it = items[count]
                if not it then it = {}; items[count] = it end
                it.icon, it.class = entry.icon or ns.FALLBACK_ICON, ns.ClassOfBuff(entry.key)
                it.expiring, it.left, it.freeze = expiring, left, simulated
            end
        end
    end

    if ns.RenderRow(row, items, count, db) == 0 then
        row:Hide()
        return
    end
    local bar, level = ns.PlateParts(plate)
    ns.PlaceRow(row, plate, bar, level, db)
    row:Show()
end

local function updateUnit(unit)
    local plate = active[unit]
    if plate then updatePlate(unit, plate) end
end

function ns.RefreshAll()
    for unit, plate in pairs(active) do updatePlate(unit, plate) end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit)
    if not unit or not GetNamePlateForUnit then return end
    local ok, plate = pcall(GetNamePlateForUnit, unit)
    if not ok or not plate then return end
    active[unit] = plate
    updatePlate(unit, plate)
end)

ns.On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    if not unit then return end
    hideRow(active[unit])
    active[unit] = nil
end)

-- UNIT_AURA is the fast path: it fires for the exact unit whose buffs changed.
ns.On("UNIT_AURA", function(_, unit)
    if unit and active[unit] then updateUnit(unit) end
end)

ns.On("PLAYER_ENTERING_WORLD", function() ns.RefreshAll() end)

-- ...and a slow sweep behind it. UNIT_AURA doesn't always reach us for units we
-- don't otherwise track, buffs expire without an event we can see, and the aura
-- restriction can lift mid-fight -- at which point every plate needs re-reading.
local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < (ns.TestActive() and 0.1 or (ns.db.refresh or 0.5)) then return end
    since = 0
    ns.RefreshAll()
end)
