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
