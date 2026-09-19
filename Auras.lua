local ADDON, ns = ...

-- Reading another player's buffs is the restricted part of this addon on Midnight,
-- so all of that lives here.
--
-- What the client allows, worst case first:
--   * Aura ITERATION (GetAuraDataByIndex) throws outright while auras are secret.
--   * GetUnitAuraBySpellID keeps answering in combat, but only for the spell ids
--     Blizzard whitelisted -- which is exactly the long-term raid buffs this addon
--     exists for. C_Secrets.ShouldSpellAuraBeSecret says whether a given id is one.
--   * A refusal looks like "returned nothing", not like an error, so a nil answer
--     is ambiguous unless we asked permission first.
--
-- Hence the three-value result from HasBuff: true / false / nil, where nil means
-- "the client wouldn't say". nil must never be drawn as missing -- under a
-- restriction that would paint a "needs buff" icon on every player in sight, which
-- is worse than drawing nothing.

local IsSecret = ns.IsSecret

local GetUnitAuraBySpellID   = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
local GetAuraDataBySpellName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local GetAuraDataByIndex     = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local MAX_AURA_SLOTS = 40

-- Is the client hiding aura data from addons right now?
function ns.AurasRestricted()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, restricted = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and type(restricted) == "boolean" then return restricted end
    end
    return false
end

-- Will this client answer questions about this particular spell's aura?
function ns.SpellReadable(spellID)
    if not spellID then return false end
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellID)
        if ok and type(secret) == "boolean" then return not secret end
    end
    -- No per-spell answer available: fall back to the coarse "are auras secret at
    -- all" test, which is the whole story on clients with no C_Secrets.
    return not ns.AurasRestricted()
end

-- Walk every buff on the unit looking for one of `names`. Rank-proof, but it is
-- the first thing the client takes away, so it is the last thing we try.
local function scanByName(unit, names)
    if GetAuraDataByIndex then
        for i = 1, MAX_AURA_SLOTS do
            local ok, aura = pcall(GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok then return nil end          -- restricted mid-scan: no answer
            if aura == nil then return false end   -- ran off the end: definitely absent
            local n = aura.name
            if n and not IsSecret(n) then
                for j = 1, #names do
                    if n == names[j] then return true, aura end
                end
            end
        end
        return false
    end

    -- Pre-Midnight clients. UnitBuff's sixth return is the expiration time; wrap it
    -- so callers see the same shape as the modern aura record.
    if _G.UnitBuff then
        for i = 1, MAX_AURA_SLOTS do
            local ok, n, _, _, _, _, expires = pcall(_G.UnitBuff, unit, i)
            if not ok then return nil end
            if not n then return false end
            for j = 1, #names do
                if n == names[j] then return true, { expirationTime = expires } end
            end
        end
        return false
    end

    return nil
end

-- Seconds left on an aura, or nil when that can't be known: no duration at all
-- (expirationTime 0, which is how a permanent buff reports), or a client that
-- won't hand over the number. nil must not be read as "about to expire".
function ns.AuraRemaining(aura)
    if type(aura) ~= "table" then return nil end
    local exp = aura.expirationTime
    if IsSecret(exp) or type(exp) ~= "number" or exp <= 0 then return nil end
    return exp - GetTime()
end

-- Returns found, aura:
--   true  = has it (aura is the record, when the client handed one over)
--   false = definitely missing
--   nil   = couldn't tell
function ns.HasBuff(unit, entry)
    local ids, names = entry.ids, entry.names

    -- 1. By spell id. This is the form that survives combat, but note what it can
    --    and cannot prove: on Vanilla-era content a buff is a family of per-rank
    --    ids, so "no aura with id 1243" means "not THAT rank", not "not buffed".
    --    The id path may therefore only ever conclude PRESENCE. Absence is decided
    --    by name below -- otherwise tracking Fortitude by one id would flag every
    --    player carrying a different rank of it.
    if ids and GetUnitAuraBySpellID then
        for i = 1, #ids do
            if ns.SpellReadable(ids[i]) then
                local ok, aura = pcall(GetUnitAuraBySpellID, unit, ids[i])
                if ok and aura ~= nil and not IsSecret(aura) then return true, aura end
            end
        end
    end

    -- An id-only entry has nothing else to go on, so there the id answer is final.
    if not names or #names == 0 then
        if ids and GetUnitAuraBySpellID then
            for i = 1, #ids do
                if ns.SpellReadable(ids[i]) then return false end
            end
        end
        return nil
    end

    -- 2. By name. Rank-proof, and matches the aliases too -- somebody under Prayer
    --    of Fortitude is not missing Fortitude.
    if GetAuraDataBySpellName and not ns.AurasRestricted() then
        local answered = false
        for i = 1, #names do
            local ok, aura = pcall(GetAuraDataBySpellName, unit, names[i], "HELPFUL")
            if ok then
                answered = true
                if aura ~= nil and not IsSecret(aura) then return true, aura end
            end
        end
        if answered then return false end
    end

    -- 3. Full scan, for clients with no name query and for anything the above
    --    declined to answer.
    return scanByName(unit, names)
end

--------------------------------------------------------------------------
-- Diagnostics (/unbuffed check)
--------------------------------------------------------------------------
-- Prints what this client will and won't tell us, per tracked buff, against the
-- current target. Worth having: the restriction rules differ by client and by
-- content, and this turns "the icons aren't showing" into a specific answer.
function ns.RunDiagnostics()
    ns.Print("diagnostics")
    print("  client interface: " .. tostring(select(4, GetBuildInfo()))
        .. (ns.IsForever and "  (WoW Forever)" or ""))
    print("  C_Secrets present: " .. tostring(C_Secrets ~= nil)
        .. " | auras restricted right now: " .. tostring(ns.AurasRestricted()))
    print("  aura APIs: GetUnitAuraBySpellID=" .. tostring(GetUnitAuraBySpellID ~= nil)
        .. " GetAuraDataBySpellName=" .. tostring(GetAuraDataBySpellName ~= nil)
        .. " GetAuraDataByIndex=" .. tostring(GetAuraDataByIndex ~= nil))

    local unit = "target"
    if ns.Truth(UnitExists(unit)) ~= true then
        print("  |cffffd100No target.|r Target a friendly player and run this again to test live reads.")
        return
    end
    -- Whether ns.db is the real SavedVariables table or still the load-time
    -- stand-in. If this ever says false, ADDON_LOADED didn't reach us and every
    -- setting is being read from, and written to, a table nobody saves.
    print("  SavedVariables linked: " .. tostring(ns.db == UnbuffedDB)
        .. "  |  panel built against real db: " .. tostring(ns.dbReady == true))
    local function line(s)
        if not s then return "  (not recorded)" end
        return ("  at %-14s UnbuffedDB is %s with %d keys  side=%s iconSize=%s")
            :format(s.when, s.kind, s.keys, tostring(s.side), tostring(s.iconSize))
    end
    print(line(ns.loaded))
    print(line(ns.loadedLate))
    print("  in memory now:  side=" .. tostring(ns.db.side) .. " iconSize=" .. tostring(ns.db.iconSize)
        .. " tracked=" .. #ns.db.tracked)
    if ns.loaded and ns.loaded.keys == 0 then
        if ns.loadedLate and ns.loadedLate.keys > 0 then
            print("  |cffffd100Saved settings arrive after ADDON_LOADED on this client|r -- picked up at login.")
        else
            print("  |cffff5555Saved settings never reach the addon.|r Every session starts from")
            print("  defaults, which is why they look lost on reload. This is the client not")
            print("  handing over SavedVariables, not the addon discarding them.")
        end
    end

    local isPlayer = ns.Truth(UnitIsPlayer(unit))
    local isFriend = ns.Truth(UnitIsFriend("player", unit))
    print("  target: isPlayer=" .. tostring(isPlayer) .. " isFriend=" .. tostring(isFriend)
        .. (isPlayer == nil and "  |cffff5555(identity restricted)|r" or ""))

    if #ns.db.tracked == 0 then
        print("  nothing tracked yet.")
        return
    end
    for _, e in ipairs(ns.db.tracked) do
        local has, aura = ns.HasBuff(unit, e)
        local left = ns.AuraRemaining(aura)
        local verdict = (has == true and ("|cff55ff55has it|r"
                .. (left and (" (" .. math.floor(left / 60) .. "m left)") or " (no readable duration)")))
            or (has == false and "|cffff5555MISSING|r")
            or "|cff888888no answer -- not flagged|r"
        local idNote = ""
        if e.ids and e.ids[1] then
            idNote = "  [id " .. e.ids[1] .. " readable=" .. tostring(ns.SpellReadable(e.ids[1])) .. "]"
        end
        print("   - " .. e.label .. ": " .. verdict .. idNote)
    end
end
