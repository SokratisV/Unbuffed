local ADDON, ns = ...

-- The icon row that hangs off a friendly player's nameplate.
--
-- Nameplate frames are recycled by the client, so the row is built once per plate
-- and cached on it; NAME_PLATE_UNIT_ADDED/REMOVED only rebind which unit it is
-- currently describing.

local active = {}   -- [unitToken] = plate frame, for the plates on screen right now

local GetNamePlateForUnit = C_NamePlate and C_NamePlate.GetNamePlateForUnit

local function getRow(plate)
    local row = plate.UnbuffedRow
    if row then return row end
    row = CreateFrame("Frame", nil, plate)
    row:SetSize(1, 1)
    -- Above the nameplate art, so the icons aren't buried by the health bar.
    row:SetFrameLevel((plate:GetFrameLevel() or 0) + 10)
    row.icons, row.labels = {}, {}
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

-- An icon texture plus the two extras a style may use: a mask and a ring.
function ns.NewIcon(parent)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetDrawLayer("OVERLAY", 0)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim the stock icon border
    t.mask = parent:CreateMaskTexture()
    t.ring = parent:CreateTexture(nil, "OVERLAY")
    t.ring:SetDrawLayer("OVERLAY", 1)       -- over the icon, under the minutes label
    t.ring:Hide()
    return t
end

-- Apply a style to an icon from NewIcon. Safe to call every sweep: the mask and ring
-- are set up once and after that only switched on or off as the style changes.
function ns.StyleIcon(t, style, alpha, zoom)
    local mask, ring = t.mask, t.ring
    if not ns.IconStyleSupported(style) then style = "SQUARE" end

    -- Zoom is how much of the art's edge is cropped away, in percent per side: 0 shows
    -- the whole texture, Blizzard's own border included, and more magnifies the middle.
    -- It crops the art; it does not resize the icon, which is the size slider's job.
    -- Clamped so a bad saved value can never invert the crop.
    local inset = math.min(0.4, math.max(0, (tonumber(zoom) or 7) / 100))
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
            ring:SetVertexColor(RING_TINT[1], RING_TINT[2], RING_TINT[3])
            ring.ready = true
        end
        ring:SetAlpha(alpha or 1)
        ring:Show()
    else
        ring:Hide()
    end
end

-- The ring is its own region, so hiding the icon alone would leave it behind.
function ns.HideIcon(t)
    t:Hide()
    t.ring:Hide()
end

-- Amber for "running out", so it reads as a warning rather than the plain
-- full-colour icon that means "not buffed at all".
local EXPIRING_TINT = { 1.0, 0.72, 0.15 }

local function getIcon(row, i)
    local t = row.icons[i]
    if t then return t, row.labels[i] end
    t = ns.NewIcon(row)
    -- Minutes left, drawn above the icon so a expiring buff says how urgent it is.
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetDrawLayer("OVERLAY", 2)
    fs:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 2, -2)
    fs:Hide()
    row.icons[i], row.labels[i] = t, fs
    return t, fs
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

local function updatePlate(unit, plate)
    if not plate then return end
    local db = ns.db
    if not db or not db.enabled then hideRow(plate); return end

    -- Unit identity can be restricted too, and then UnitIsPlayer answers nothing
    -- rather than false. Only a real boolean counts: an unknown unit is not a
    -- friendly player as far as we're concerned.
    if ns.Truth(UnitIsPlayer(unit)) ~= true then hideRow(plate); return end
    if ns.Truth(UnitIsFriend("player", unit)) ~= true then hideRow(plate); return end
    if db.hideSelf and ns.Truth(UnitIsUnit(unit, "player")) == true then hideRow(plate); return end

    local row = getRow(plate)
    local size, spacing = db.iconSize, db.spacing
    local shown = 0

    for _, entry in ipairs(db.tracked) do
        if entry.enabled then
            -- Only a definite "missing" draws an icon. nil means the client refused
            -- to answer, and guessing there would flag people who are actually
            -- buffed. An aura with no readable duration is likewise left alone.
            local found, aura = ns.HasBuff(unit, entry)
            local expiring, minsLeft
            if found == true and db.flagExpiring then
                local left = ns.AuraRemaining(aura)
                if left and left > 0 and left <= db.expiringMinutes * 60 then
                    expiring = true
                    minsLeft = math.max(1, math.ceil(left / 60))
                end
            end

            if found == false or expiring then
                shown = shown + 1
                local t, fs = getIcon(row, shown)
                t:SetTexture(entry.icon or ns.FALLBACK_ICON)
                t:SetSize(size, size)
                t:SetAlpha(db.alpha)
                t:ClearAllPoints()
                t:SetPoint("LEFT", row, "LEFT", (shown - 1) * (size + spacing), 0)
                ns.StyleIcon(t, db.iconStyle, db.alpha, db.iconZoom)
                if expiring then
                    t:SetVertexColor(EXPIRING_TINT[1], EXPIRING_TINT[2], EXPIRING_TINT[3])
                    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
                        math.max(7, math.floor(size * 0.46)), "OUTLINE")
                    fs:SetText(minsLeft .. "m")
                    fs:Show()
                else
                    t:SetVertexColor(1, 1, 1)
                    fs:Hide()
                end
                t:Show()
            end
        end
    end
    for i = shown + 1, #row.icons do
        ns.HideIcon(row.icons[i])
        row.labels[i]:Hide()
    end

    if shown == 0 then
        row:Hide()
        return
    end
    row:SetSize(shown * size + (shown - 1) * spacing, size)
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
    if not ns.db or not ns.db.enabled then return end
    since = since + dt
    if since < (ns.db.refresh or 0.5) then return end
    since = 0
    ns.RefreshAll()
end)
