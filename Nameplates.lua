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

-- Amber for "running out", so it reads as a warning rather than the plain
-- full-colour icon that means "not buffed at all".
local EXPIRING_TINT = { 1.0, 0.72, 0.15 }

local function getIcon(row, i)
    local t = row.icons[i]
    if t then return t, row.labels[i] end
    t = row:CreateTexture(nil, "OVERLAY")
    t:SetDrawLayer("OVERLAY", 0)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim the stock icon border
    -- Minutes left, drawn above the icon so a expiring buff says how urgent it is.
    local fs = row:CreateFontString(nil, "OVERLAY")
    fs:SetDrawLayer("OVERLAY", 2)
    fs:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 2, -2)
    fs:Hide()
    row.icons[i], row.labels[i] = t, fs
    return t, fs
end

-- db.side is one of "RIGHT", "LEFT" or "CENTER" (the key predates the centre
-- option; renaming it would orphan everyone's saved setting).
--
-- The offsets mean slightly different things per position, and deliberately so.
-- Beside the plate, xOffset is a GAP: it reads as "distance away from the plate"
-- on both sides, so the sign is flipped for LEFT and a negative value pulls the
-- row back over the plate either way. Centred, there is no gap to describe, so
-- xOffset is a plain nudge -- positive right, negative left -- and 0, 0 sits the
-- row dead centre on the nameplate, over the name.
local function anchorRow(row, plate)
    local db = ns.db
    row:ClearAllPoints()
    if db.side == "CENTER" then
        row:SetPoint("CENTER", plate, "CENTER", db.xOffset, db.yOffset)
    elseif db.side == "LEFT" then
        row:SetPoint("RIGHT", plate, "LEFT", -db.xOffset, db.yOffset)
    else
        row:SetPoint("LEFT", plate, "RIGHT", db.xOffset, db.yOffset)
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
        row.icons[i]:Hide()
        row.labels[i]:Hide()
    end

    if shown == 0 then
        row:Hide()
        return
    end
    row:SetSize(shown * size + (shown - 1) * spacing, size)
    anchorRow(row, plate)
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
