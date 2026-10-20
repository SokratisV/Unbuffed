local ADDON, ns = ...

-- The buffs worth watching for, by the class that casts them.
--
-- Matched by NAME, not spell id, and that is deliberate: on Vanilla-era content a buff
-- is a family of per-rank spell ids (Power Word: Fortitude alone is 1243, 1244, 1245,
-- 2791, 10937, 10938), so one id would only ever match one rank. `names` also carries
-- the group version, because someone under Prayer of Fortitude is not missing
-- Fortitude. These are the names the BUFF shows on a player, which is not always the
-- spell's: a Shaman casts "Strength of Earth Totem" and the players it covers carry
-- "Strength of Earth".
--
-- `id` is a spell id used only to find the icon, via the client, when `icon` (a literal
-- path) is not given. Looking it up means no icon file name has to be right by hand,
-- and a missing one falls back to a question mark rather than a broken texture. Every
-- id that appears in the trainer data for this class was checked against it; the few
-- that are talent or quest spells are not in any trainer list, so those could not be.
--
-- `tbc` marks buffs that only exist on the TBC clients, and are left out on Forever.
--
-- Icons are literal for the nine buffs that shipped before this list was organised by
-- class, so they stay exactly as they were. The keys of those nine are also what saved
-- profiles refer to: never rename one.
ns.CLASS_BUFFS = {
    DRUID = {
        { key = "motw",   label = "Mark of the Wild", icon = "Interface\\Icons\\Spell_Nature_Regeneration",
          names = { "Mark of the Wild", "Gift of the Wild" }, id = 1126 },
        { key = "thorns", label = "Thorns",           icon = "Interface\\Icons\\Spell_Nature_Thorns",
          names = { "Thorns" }, id = 467 },
    },
    HUNTER = {
        { key = "trueshot",   label = "Trueshot Aura",       names = { "Trueshot Aura" },       id = 19506 },
        { key = "aspectwild", label = "Aspect of the Wild",  names = { "Aspect of the Wild" },  id = 20043 },
        { key = "aspectpack", label = "Aspect of the Pack",  names = { "Aspect of the Pack" },  id = 13159 },
    },
    MAGE = {
        { key = "intellect", label = "Arcane Intellect", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
          names = { "Arcane Intellect", "Arcane Brilliance" }, id = 1459 },
        { key = "dampen",    label = "Dampen Magic",     names = { "Dampen Magic" },  id = 604 },
        { key = "amplify",   label = "Amplify Magic",    names = { "Amplify Magic" }, id = 1008 },
    },
    PALADIN = {
        { key = "might",  label = "Blessing of Might",  icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",
          names = { "Blessing of Might", "Greater Blessing of Might" }, id = 19740 },
        { key = "wisdom", label = "Blessing of Wisdom", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
          names = { "Blessing of Wisdom", "Greater Blessing of Wisdom" }, id = 19742 },
        { key = "kings",  label = "Blessing of Kings",  icon = "Interface\\Icons\\Spell_Magic_MageArmor",
          names = { "Blessing of Kings", "Greater Blessing of Kings" }, id = 20217 },
        { key = "salvation", label = "Blessing of Salvation",
          names = { "Blessing of Salvation", "Greater Blessing of Salvation" }, id = 1038 },
        { key = "light",     label = "Blessing of Light",
          names = { "Blessing of Light", "Greater Blessing of Light" }, id = 19977 },
        { key = "sanctuary", label = "Blessing of Sanctuary",
          names = { "Blessing of Sanctuary", "Greater Blessing of Sanctuary" }, id = 20911 },
        { key = "devotion",      label = "Devotion Aura",          names = { "Devotion Aura" },          id = 465 },
        { key = "retribution",   label = "Retribution Aura",       names = { "Retribution Aura" },       id = 7294 },
        { key = "concentration", label = "Concentration Aura",     names = { "Concentration Aura" },     id = 19746 },
        { key = "fireresaura",   label = "Fire Resistance Aura",   names = { "Fire Resistance Aura" },   id = 19891 },
        { key = "frostresaura",  label = "Frost Resistance Aura",  names = { "Frost Resistance Aura" },  id = 19888 },
        { key = "shadowresaura", label = "Shadow Resistance Aura", names = { "Shadow Resistance Aura" }, id = 19876 },
    },
    PRIEST = {
        { key = "fortitude", label = "Fortitude",     icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
          names = { "Power Word: Fortitude", "Prayer of Fortitude" }, id = 1243 },
        { key = "spirit",    label = "Divine Spirit", icon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
          names = { "Divine Spirit", "Prayer of Spirit" }, id = 14752 },
        { key = "shadowprot", label = "Shadow Protection",
          names = { "Shadow Protection", "Prayer of Shadow Protection" }, id = 976 },
        { key = "fearward",   label = "Fear Ward", names = { "Fear Ward" }, id = 6346 },
    },
    ROGUE = {},   -- nothing a Rogue casts on other players that is worth flagging
    SHAMAN = {
        { key = "strength",    label = "Strength of Earth",  names = { "Strength of Earth" }, id = 8075 },
        { key = "grace",       label = "Grace of Air",       names = { "Grace of Air" },      id = 8835 },
        { key = "windfury",    label = "Windfury Totem",     names = { "Windfury Totem" },    id = 8512 },
        { key = "manaspring",  label = "Mana Spring",        names = { "Mana Spring" },       id = 5675 },
        { key = "healstream",  label = "Healing Stream",     names = { "Healing Stream" },    id = 6375 },
        { key = "stoneskin",   label = "Stoneskin",          names = { "Stoneskin" },         id = 8154 },
        { key = "fireres",     label = "Fire Resistance Totem",   names = { "Fire Resistance" },   id = 8184 },
        { key = "frostres",    label = "Frost Resistance Totem",  names = { "Frost Resistance" },  id = 8181 },
        { key = "natureres",   label = "Nature Resistance Totem", names = { "Nature Resistance" }, id = 10595 },
        { key = "tranquil",    label = "Tranquil Air",       names = { "Tranquil Air" },       id = 25908, tbc = true },
        { key = "wrathofair",  label = "Wrath of Air Totem", names = { "Wrath of Air Totem" }, id = 3738,  tbc = true },
    },
    WARLOCK = {
        -- Soulstone's id is the spell that creates the stone, which shares the buff's icon.
        { key = "soulstone",    label = "Soulstone",       names = { "Soulstone Resurrection" }, id = 693 },
        { key = "bloodpact",    label = "Blood Pact",      names = { "Blood Pact" },             id = 6307 },
        { key = "unendbreath",  label = "Unending Breath", names = { "Unending Breath" },        id = 5697 },
    },
    WARRIOR = {
        { key = "bshout", label = "Battle Shout", icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
          names = { "Battle Shout" }, id = 6673 },
        { key = "cshout", label = "Commanding Shout", names = { "Commanding Shout" }, id = 469, tbc = true },
    },
}

-- Which rank of a buff's spell suits a character's level: { level it is learned at, spell id },
-- lowest rank first. Taken from TrainerSpells' trainer data (Forever's and TBC's), in which every
-- family below was checked to run through consecutive rank numbers at increasing levels. `tbc` is
-- given only where the TBC client differs from Forever (extra high ranks, usually); a buff with no
-- entry for a client has no level-based rank there -- talents, pet spells and quest spells are
-- not in any trainer list -- and gets a plain tooltip instead.
ns.RANKS = {
    amplify = { forever = { { 18, 1008 }, { 30, 8455 }, { 42, 10169 }, { 54, 10170 } }, tbc = { { 18, 1008 }, { 30, 8455 }, { 42, 10169 }, { 54, 10170 }, { 63, 27130 }, { 69, 33946 } } },
    aspectpack = { forever = { { 40, 13159 } } },
    aspectwild = { forever = { { 46, 20043 }, { 56, 20190 } }, tbc = { { 46, 20043 }, { 56, 20190 }, { 68, 27045 } } },
    bshout = { forever = { { 1, 6673 }, { 12, 5242 }, { 22, 6192 }, { 32, 11549 }, { 42, 11550 }, { 52, 11551 } }, tbc = { { 1, 6673 }, { 12, 5242 }, { 22, 6192 }, { 32, 11549 }, { 42, 11550 }, { 52, 11551 }, { 60, 25289 } } },
    concentration = { forever = { { 22, 19746 } } },
    cshout = { tbc = { { 68, 469 } } },
    dampen = { forever = { { 12, 604 }, { 24, 8450 }, { 36, 8451 }, { 48, 10173 }, { 60, 10174 } }, tbc = { { 12, 604 }, { 24, 8450 }, { 36, 8451 }, { 48, 10173 }, { 60, 10174 }, { 67, 33944 } } },
    devotion = { forever = { { 1, 465 }, { 10, 10290 }, { 20, 643 }, { 30, 10291 }, { 40, 1032 }, { 50, 10292 }, { 60, 10293 } }, tbc = { { 1, 465 }, { 10, 10290 }, { 20, 643 }, { 30, 10291 }, { 40, 1032 }, { 50, 10292 }, { 60, 10293 }, { 70, 27149 } } },
    fearward = { forever = { { 20, 6346 } } },
    fireres = { forever = { { 28, 8184 }, { 42, 10537 }, { 58, 10538 } }, tbc = { { 28, 8184 }, { 42, 10537 }, { 58, 10538 }, { 68, 25563 } } },
    fireresaura = { forever = { { 36, 19891 }, { 48, 19899 }, { 60, 19900 } }, tbc = { { 36, 19891 }, { 48, 19899 }, { 60, 19900 }, { 70, 27153 } } },
    fortitude = { forever = { { 1, 1243 }, { 12, 1244 }, { 24, 1245 }, { 36, 2791 }, { 48, 10937 }, { 60, 10938 } }, tbc = { { 1, 1243 }, { 12, 1244 }, { 24, 1245 }, { 36, 2791 }, { 48, 10937 }, { 60, 10938 }, { 70, 25389 } } },
    frostres = { forever = { { 24, 8181 }, { 38, 10478 }, { 54, 10479 } }, tbc = { { 24, 8181 }, { 38, 10478 }, { 54, 10479 }, { 67, 25560 } } },
    frostresaura = { forever = { { 32, 19888 }, { 44, 19897 }, { 56, 19898 } }, tbc = { { 32, 19888 }, { 44, 19897 }, { 56, 19898 }, { 68, 27152 } } },
    grace = { forever = { { 42, 8835 }, { 56, 10627 } }, tbc = { { 42, 8835 }, { 56, 10627 }, { 60, 25359 } } },
    healstream = { forever = { { 30, 6375 }, { 40, 6377 }, { 50, 10462 }, { 60, 10463 } }, tbc = { { 30, 6375 }, { 40, 6377 }, { 50, 10462 }, { 60, 10463 }, { 69, 25567 } } },
    intellect = { forever = { { 1, 1459 }, { 14, 1460 }, { 28, 1461 }, { 42, 10156 }, { 56, 10157 } }, tbc = { { 1, 1459 }, { 14, 1460 }, { 28, 1461 }, { 42, 10156 }, { 56, 10157 }, { 70, 27126 } } },
    kings = { forever = { { 20, 20217 } }, tbc = {  } },
    light = { forever = { { 40, 19977 }, { 50, 19978 }, { 60, 19979 } }, tbc = { { 40, 19977 }, { 50, 19978 }, { 60, 19979 }, { 69, 27144 } } },
    manaspring = { forever = { { 26, 5675 }, { 36, 10495 }, { 46, 10496 }, { 56, 10497 } }, tbc = { { 26, 5675 }, { 36, 10495 }, { 46, 10496 }, { 56, 10497 }, { 65, 25570 } } },
    might = { forever = { { 4, 19740 }, { 12, 19834 }, { 22, 19835 }, { 32, 19836 }, { 42, 19837 }, { 52, 19838 } }, tbc = { { 4, 19740 }, { 12, 19834 }, { 22, 19835 }, { 32, 19836 }, { 42, 19837 }, { 52, 19838 }, { 60, 25291 }, { 70, 27140 } } },
    motw = { forever = { { 1, 1126 }, { 10, 5232 }, { 20, 6756 }, { 30, 5234 }, { 40, 8907 }, { 50, 9884 }, { 60, 9885 } }, tbc = { { 1, 1126 }, { 10, 5232 }, { 20, 6756 }, { 30, 5234 }, { 40, 8907 }, { 50, 9884 }, { 60, 9885 }, { 70, 26990 } } },
    natureres = { forever = { { 30, 10595 }, { 44, 10600 }, { 60, 10601 } }, tbc = { { 30, 10595 }, { 44, 10600 }, { 60, 10601 }, { 69, 25574 } } },
    retribution = { forever = { { 16, 7294 }, { 26, 10298 }, { 36, 10299 }, { 46, 10300 }, { 56, 10301 } }, tbc = { { 16, 7294 }, { 26, 10298 }, { 36, 10299 }, { 46, 10300 }, { 56, 10301 }, { 66, 27150 } } },
    salvation = { forever = { { 26, 1038 } } },
    shadowprot = { forever = { { 30, 976 }, { 42, 10957 }, { 56, 10958 } }, tbc = { { 30, 976 }, { 42, 10957 }, { 56, 10958 }, { 68, 25433 } } },
    shadowresaura = { forever = { { 28, 19876 }, { 40, 19895 }, { 52, 19896 } }, tbc = { { 28, 19876 }, { 40, 19895 }, { 52, 19896 }, { 63, 27151 } } },
    soulstone = { forever = { { 18, 693 }, { 30, 20752 }, { 40, 20755 }, { 50, 20756 }, { 60, 20757 } }, tbc = { { 18, 693 }, { 30, 20752 }, { 40, 20755 }, { 50, 20756 }, { 60, 20757 }, { 70, 27238 } } },
    spirit = { forever = { { 30, 14752 }, { 40, 14818 }, { 50, 14819 }, { 60, 27841 } }, tbc = { { 40, 14818 }, { 50, 14819 }, { 60, 27841 }, { 70, 25312 } } },
    stoneskin = { forever = { { 14, 8154 }, { 24, 8155 }, { 34, 10406 }, { 44, 10407 }, { 54, 10408 } }, tbc = { { 14, 8154 }, { 24, 8155 }, { 34, 10406 }, { 44, 10407 }, { 54, 10408 }, { 63, 25508 }, { 70, 25509 } } },
    strength = { forever = { { 10, 8075 }, { 24, 8160 }, { 38, 8161 }, { 52, 10442 } }, tbc = { { 10, 8075 }, { 24, 8160 }, { 38, 8161 }, { 52, 10442 }, { 60, 25361 }, { 65, 25528 } } },
    thorns = { forever = { { 6, 467 }, { 14, 782 }, { 24, 1075 }, { 34, 8914 }, { 44, 9756 }, { 54, 9910 } }, tbc = { { 6, 467 }, { 14, 782 }, { 24, 1075 }, { 34, 8914 }, { 44, 9756 }, { 54, 9910 }, { 64, 26992 } } },
    tranquil = { tbc = { { 50, 25908 } } },
    trueshot = { forever = { { 40, 19506 }, { 50, 20905 }, { 60, 20906 } }, tbc = { { 50, 20905 }, { 60, 20906 }, { 70, 27066 } } },
    unendbreath = { forever = { { 16, 5697 } } },
    windfury = { forever = { { 32, 8512 }, { 42, 10613 }, { 52, 10614 } }, tbc = { { 32, 8512 }, { 42, 10613 }, { 52, 10614 }, { 61, 25585 }, { 70, 25587 } } },
    wisdom = { forever = { { 14, 19742 }, { 24, 19850 }, { 34, 19852 }, { 44, 19853 }, { 54, 19854 } }, tbc = { { 14, 19742 }, { 24, 19850 }, { 34, 19852 }, { 44, 19853 }, { 54, 19854 }, { 60, 25290 }, { 65, 27142 } } },
    wrathofair = { tbc = { { 64, 3738 } } },
}

-- The spell id of the rank that suits `level`, and the level that rank is learned at: the highest
-- rank learned at or below the level. A character below the first rank gets that first rank (the
-- second value then exceeds their level, so the caller can say so). nil when this client has no
-- level-based rank for the buff, which is the signal to show a plain tooltip.
function ns.RankFor(key, level)
    local r = ns.RANKS[key]
    if not r then return nil end
    -- Spelled out, not `a and b or c`: that would fall through to the TBC list on Forever for a
    -- buff that has none of its own there.
    local list
    if ns.IsForever then list = r.forever else list = r.tbc or r.forever end
    if not list or #list == 0 then return nil end
    local pick = list[1]
    for _, rank in ipairs(list) do
        if rank[1] <= level then pick = rank else break end
    end
    return pick[2], pick[1]
end

-- The playable classes on the clients this addon supports, in no particular order --
-- the panel sorts them by their localized names. A fixed list rather than asking the
-- client, which on Forever could name classes that do not exist in this game.
local CLASS_TOKENS = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

-- Does this client have the buff? TBC-only ones are hidden on Forever, which has none
-- of that content.
local function available(entry)
    return not (entry.tbc and ns.IsForever)
end

-- The buffs a class offers on this client, in the order they are written above.
function ns.ClassBuffs(classToken)
    local out = {}
    for _, entry in ipairs(ns.CLASS_BUFFS[classToken] or {}) do
        if available(entry) then out[#out + 1] = entry end
    end
    return out
end

-- Every class, as { key, label, name }: the label carries the class's own colour, the
-- name is plain. Sorted by the name as the player sees it.
function ns.ClassList()
    local names = _G.LOCALIZED_CLASS_NAMES_MALE or {}
    local colors = _G.RAID_CLASS_COLORS or {}
    local list = {}
    for _, token in ipairs(CLASS_TOKENS) do
        local name = names[token] or token
        local c = colors[token]
        local label = c and ("|cff%02x%02x%02x%s|r"):format(
            math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), name) or name
        list[#list + 1] = { key = token, label = label, name = name }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- The class of the character logged in, if it is one we know about.
function ns.PlayerClass()
    local _, token = UnitClass("player")
    if token and ns.CLASS_BUFFS[token] then return token end
end

-- Find a buff by its key, whichever class it belongs to. TBC-only ones are found too:
-- a saved profile may mention one even where it is hidden.
function ns.FindPreset(key)
    for _, list in pairs(ns.CLASS_BUFFS) do
        for _, entry in ipairs(list) do
            if entry.key == key then return entry end
        end
    end
end

-- The class that casts a listed buff, by its key; nil for one added by name or id, which
-- has no class we know of. Built once, on first use.
local classOf
function ns.ClassOfBuff(key)
    if not classOf then
        classOf = {}
        for token, list in pairs(ns.CLASS_BUFFS) do
            for _, entry in ipairs(list) do classOf[entry.key] = token end
        end
    end
    return key and classOf[key] or nil
end

-- The class's colour as r, g, b, or nil where the client has none for it.
function ns.ClassColor(token)
    local c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
end

-- The icon for a buff: the literal path when it has one, else whatever the client says
-- the spell's icon is, else a question mark.
function ns.PresetIcon(preset)
    if preset.icon then return preset.icon end
    if preset.id then
        local _, icon = ns.SpellNameAndIcon(preset.id)
        if icon and icon ~= ns.FALLBACK_ICON then return icon end
    end
    return ns.FALLBACK_ICON
end

-- A buff in the shape the tracked list stores. The names are copied, so editing a saved
-- entry can never alter the list above.
function ns.PresetEntry(preset)
    return {
        key = preset.key, label = preset.label, icon = ns.PresetIcon(preset),
        names = { unpack(preset.names) },
    }
end
