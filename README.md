# Unbuffed

**Flags friendly player nameplates that are missing the buffs you track.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Version](https://img.shields.io/badge/version-1.8.0-brightgreen)
![WoW](https://img.shields.io/badge/WoW-Forever%20%2F%20TBC%20Classic-f8b700)
![Interface](https://img.shields.io/badge/interface-16001%20%7C%2020505-555)

Pick the buffs you care about. Any friendly player whose nameplate is on screen and who
is **missing** one gets a small row of those buffs' icons beside their plate. A fully
buffed player shows nothing at all, so every icon you can see is something to cast.

> **Client support.** Runs on **WoW Forever** (interface `16001`) and on the
> **TBC Classic / Anniversary** client (interface `20505`) from the same files.

## Using it

- `/unbuffed` (or `/ub`) opens the settings window. Pick a class and tick the buffs to flag. It has
  five pages -- **Buffs**, **Look**, **Expiring**, **Share** and **General** -- in the style of FlareUI: the
  pages on the left, the settings in the middle, and on the right what the setting you are pointing
  at does. Settings that don't apply to your choices (the ring color, once the style has no ring)
  are not shown. The entry under AddOns in the game's own settings just opens this window.
- `/ub add <name or spell ID>` adds anything the class lists don't have.
- `/ub remove <name>`, `/ub list`.
- `/ub test` runs the expiring-buff look for 20 seconds, so you can see it.
- `/ub share [name]` sends your buff list to another player, or opens the Share page.
- `/ub export` and `/ub import` open the Profile page, to copy your whole setup or paste one in.

## Choosing buffs

The **Buffs** page has a **Class** choice with all nine classes. Pick one
and it lists every buff that class casts on other players: for example the Paladin's
blessings and auras, the Shaman's totem buffs, the Priest's Fortitude, Spirit and Shadow
Protection. The dropdown starts on your own class. Tick any number of buffs, and switch
class to add more: the choices accumulate.

Under the class list, **Active buffs** shows everything currently tracked, whichever
class it came from (or none, for a buff added by name), each with a button to drop it.
Unticking a buff in its class does the same.

Hover any buff, in the class list or the Active list, for its tooltip: the game's own
description of the spell, for the **rank that suits your character's level** -- the
highest rank you could have learned by now, so a level-25 character sees Blessing of Might
rank 3 and a level-60 one rank 6. A character below a buff's first rank sees that rank,
with a note saying at which level it is learned. The ranks come from the trainer data for
your client (Forever's or TBC's), so a TBC character sees the TBC-only higher ranks.
Buffs with no level-based rank have a plain tooltip instead, naming what they match:
Blessing of Sanctuary and Blood Pact (talent and pet spells, in no trainer list) and, on
TBC, Blessing of Kings (a talent there). A buff you added by spell ID shows exactly that
spell.

A Rogue has no buffs of that kind, so that class's list is empty; anything else can
always be added by name or spell ID. A few buffs exist only on the TBC clients
(Commanding Shout, Tranquil Air, Wrath of Air Totem) and are left out on Forever.

**Every character has its own list**, made the first time it logs in, with its class's main buffs
already ticked:

| Class | Ticked for you |
| --- | --- |
| Priest | Fortitude |
| Druid | Mark of the Wild |
| Mage | Arcane Intellect |
| Warrior | Battle Shout |
| Paladin | Blessing of Kings, Might and Wisdom |
| Shaman, Warlock, Hunter, Rogue | nothing: every buff is still in the list to tick |

A main is ticked **the first time the character knows the spell**, so a new Paladin gets Might at
level 4 and Wisdom when it learns it. It is ticked once: untick it and it stays unticked. Each
character's list, and the class it last looked at in the Buffs page, are its own, so a new character
never opens on another character's buffs.

**A buff of your own class is only flagged once you know a rank of it** (any rank counts, and a talent
counts once it is taken). Until then it stays in the list, with a note in its tooltip, but draws no
icon. Another class's buff, which you can only ask for, and anything you added by name or ID, is
always flagged. A buff cast by a pet (Blood Pact) can't be in your spellbook, so it counts as known.

Characters from before this version keep what they had: the old shared list is carried over to each
character where it fits (a Priest keeps its Fortitude, a new Paladin does not inherit it), and
anything you added by name or ID goes to every character.

## Sharing your buffs

The **Share** page (or `/ub share <name>`) sends your list of tracked buffs to another player who has
Unbuffed, over a whisper: type their name, or press **Target** to take the player you are targeting,
then **Send**. They are asked first, with an Accept / Decline prompt of Unbuffed's own, and nothing
arrives unless they accept. Only the buffs you track go across, not your look, and only buffs they
don't already track are added: nothing of theirs is removed, changed, or switched on.

A listed buff is sent as its key and looked up on the other side, so it comes with the receiver's own
names and icon, and one that doesn't exist on their client (a TBC-only buff on WoW Forever) is skipped
and reported. A buff you added by name or spell ID is sent as that name or ID. Anything that arrives is
checked and size-capped. **Let other players offer me their buffs** on the same page turns offers off
(they are declined for you). Transfers go in small paced messages, the same way Thumber shares its marks.

## Profiles: copy your setup

The **Profile** page (or `/ub export`, `/ub import`) turns your whole setup into one piece of text you can
copy, and reads it back on another character or another install. It holds **every setting on every
page** -- where the icons go (anchor and offsets), their size, style, ring color, outline, zoom,
layout and cap, the expiring look, and the filters -- and **this character's buff list**, switched-off
buffs included. Another character's list, and which page the window was on, are not part of it.

Press **Export** and copy the text from the box. To use one, paste it and press **Preview import**, which
says how many settings differ from yours; then **Import everything** replaces your settings and this
character's buff list, and **Import settings only** leaves the buff list alone. It applies at once, with
no reload. A setting the text doesn't mention takes its default, a value that isn't allowed is held to
what the setting allows or dropped, and anything that isn't an Unbuffed profile, or was made by a
different version, is refused with a plain message rather than an error.

## Who gets an icon

Any friendly player whose nameplate is on screen. Two options in **General** narrow that:
**Skip my own nameplate**, and **Only show for party and raid members**, which limits the
icons to people in your group, so strangers in a city or a dungeon never get one. With the
second on and no group, nothing is shown. If the client won't say whether someone is in your
group, they are treated as not being in it, the same way an unreadable buff is never drawn
as missing.

## Where the icons go

The **Look** page's **Position** section chooses where the icon row attaches. Above the settings
on the Look and Expiring pages sits a live **preview** of a nameplate that stays put while the page
scrolls, so each choice shows what it does as you make it. The icon row can attach to:

- **Right of the level text** (the default): just past the level number.
- **Left of the health bar**: against the bar's left end.
- **Centered under the health bar**.
- **Custom**: measured from the centre of the plate. The horizontal and vertical
  offset sliders appear only while this is selected.

These follow the plate's own parts, so they work at any nameplate width. A part the
plate doesn't have falls back down a chain: level box, then health bar, then the plate
itself -- friendly plates often have no level box, in which case the icon sits at the
right end of the bar instead.

The **Look** page covers icon size, opacity, **layout**, spacing, a **cap** on how many icons are
drawn, the **icon style** with the options that belong to it, **icon zoom**, and the position.

**Icon zoom** crops into or out of the icon art. At 0% you see the whole texture,
including Blizzard's own border; higher values magnify the middle. It is separate from
icon size, which changes how big the icon is. The default is 0%, the whole icon.

The styles are:

- **Square**: the stock spell icon.
- **Round**: the icon clipped to a circle.
- **Gold ring** (the default): the round icon inside a gold ring.

The round styles use Blizzard's own circle art, so they ship nothing of their own, and
they are offered only on clients that have it; elsewhere the choice is just Square.

Each style shows its own options and hides the rest: the gold ring has a **ring color**; Square and
Round have a **black outline** with a **thickness**.

**Ring color** applies to the gold ring style: plain **Gold**, or **Class of the buff**, the
color of the class that casts it (white for a Priest's buff, orange for a Druid's, and so on), so
you can tell who to ask. A buff you added by name has no known class and keeps the gold ring.

**Layout** is how several missing buffs sit side by side: **Row**, or **Overlapped**, where each
icon covers the edge of the last (the spacing setting is ignored then).

**Most icons shown** caps the group. When more buffs are missing than the cap, the last slot
becomes a red **+N** chip standing for the rest. At the top of the slider there is no limit.

**Black outline** (Square and Round) lays a black edge along the icon's border, from 1 to 4 pixels
thick, laid over the icon's edge: the art keeps its size and only its outermost pixels are covered,
square or round. A small icon holds it to a quarter of its size. The gold ring has an edge of its
own, so it has no outline option.

**Reset position and look** (two clicks,
no popup) puts those back to their defaults and leaves the buffs you track alone.

Settings saved by an earlier version carry over: the old *right* and *left* become
*Right of the level text* and *Left of the health bar*, and *centered* becomes *Custom*
with its offsets unchanged.

## Buffs about to expire

With **Also flag buffs about to expire** on, a buff that has less than the warning
threshold left (5 minutes by default) is shown too, with the minutes remaining on it, so
it reads differently from a buff that was never cast at all. **Show them as** picks how:

- **Amber tint** (the default): the icon turns amber.
- **Faded icon**: the icon keeps its colour and becomes more transparent instead, by
  the **Faded opacity** you set (50% by default).
- **Countdown sweep**: the icon stays as it is, and a clock-style wedge darkens it as the time
  runs out. The wedge lies between the icon and its ring or outline, so the ring stays clean. The label turns amber, then orange under two minutes and red under one, and counts
  seconds in the last minute.

To see any of these without waiting for a real buff to run down, press **Test expiring look** (or
type `/ub test`). For 20 seconds the first buff you track counts down from a full warning window to
nothing, in the preview and on every friendly player's nameplate in view.

Only the icon fades: the minutes-left label stays fully opaque, so it is always
readable. The preview includes an expiring example, so you can
see the effect as you change it. A buff whose remaining time this client will not report is never flagged, for the
same reason an unreadable buff is never drawn as missing.

## Why buffs are matched by name

Every listed buff matches on its **name**, not a spell ID, and that is deliberate. On
Vanilla-era content a buff is a *family* of per-rank spell IDs — Power Word: Fortitude
alone is 1243, 1244, 1245, 2791, 10937 and 10938 — so a single ID would only ever match
one rank and would report everyone else as unbuffed.

Names also let an entry carry the group version, because somebody under **Prayer of
Fortitude** is not missing Fortitude.

Adding a buff by spell ID stores the ID *and* its name. The ID is the form that keeps
working during combat (see below); the name is what makes it rank-proof. A spell ID is
only ever used to prove a buff is **present** — never that it is absent.

### On a client in another language

Aura names are whatever the client calls them, so on a German, French or other non-English client the
English names alone would never match. Unbuffed asks the client what the buff's spell and its group
spell are called -- Power Word: Fortitude and Prayer of Fortitude, Greater Blessing of Might -- and
matches those too, keeping the English names as a fallback, and the list shows each buff by the client's
own spell name. This covers every listed buff **except the Shaman's totem buffs and the Warlock's
Soulstone**, whose aura is a different spell from the one cast, so there is no spell ID to ask about:
on a client in another language, add those by the name the buff shows in the game (a buff added by
name is matched by exactly what you typed).

## Languages

The settings window, the chat messages, the buff list's own text and the AddOns-list description are
translated into **German, French, Spanish (Spain and Latin America), Brazilian Portuguese, Russian,
Korean, Simplified and Traditional Chinese, and Italian**. English is the fallback for any text that has
no translation. Spell names, tooltips and class names always come from the game, so they read in
your language already; the slash commands stay English. The text tables are in `Locales/`, one file per
client language.

## What the client will and won't tell an addon

Midnight (and so WoW Forever) restricts reading other players' auras:

- Aura **iteration** (`C_UnitAuras.GetAuraDataByIndex`) throws outright while auras are
  secret.
- `C_UnitAuras.GetUnitAuraBySpellID` keeps answering during combat, but only for spell
  IDs Blizzard whitelisted — which includes the long-term raid buffs this addon is for.
- A refusal looks like *"returned nothing"*, not like an error, so `C_Secrets` is used to
  ask permission first and tell a genuine "not buffed" apart from "won't say".

Unbuffed therefore treats a buff check as three-valued: **has it**, **definitely
missing**, or **no answer**. Only a definite *missing* draws an icon. Guessing on a
refusal would paint a "needs buff" icon on every player in sight the moment the client
clamped down, which is worse than drawing nothing.

### When icons don't appear

The usual reason is simply that **friendly player nameplates are switched off** — the
addon says so once at login if it detects that.

Another nameplate addon, or a UI suite's own nameplates, can also replace the default
plates in a way that hides the icons. Try with the other addon disabled.

## License

MIT. See [LICENSE](LICENSE).
