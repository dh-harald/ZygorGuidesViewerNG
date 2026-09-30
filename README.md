![GitHub Release](https://img.shields.io/github/v/release/dh-harald/ZygorGuidesViewerNG) ![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/dh-harald/ZygorGuidesViewerNG/package.yaml) ![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/dh-harald/ZygorGuidesViewerNG/total)
# ZygorGuidesViewerNG

A from-scratch clone of the Zygor Guides Viewer, built specifically to run the
**original Zygor Classic leveling guides** on a **1.12.1 "vanilla" private/broken
server** — the kind of server the real Zygor addon was never built to support — and on
**Unreal Azeroth**, the Unreal Engine rebuild of that same client.

If you've got Zygor's exported Classic guide data and a vanilla server where the real
addon simply won't load, that's the exact problem this project exists to solve: fast,
guided leveling with waypoints, quest tracking, and automation, on a client Zygor itself
doesn't target.

## What it does

- **Renders Zygor's own guide DSL.** `Parser.lua` reads the same `[[ ... ]]` guide text
  format Zygor's guides ship in (`accept`/`turnin`/`goto`/`kill`/`use`/`|tip`/`|only`/
  sticky steps/etc.) and turns it into steps and goals the viewer can track and display.
  **No guide data is included** — you supply a leveling guide from your own Zygor install,
  see "Guide data" below.
- **Tracks quest completion without any of the APIs later clients have.** Vanilla has no
  `IsQuestFlaggedCompleted` equivalent and no way to read a quest's numeric ID off the
  quest log — `QuestTracking.lua` resolves log entries against an offline quest database
  (title + objective text, ~4400 quests) and watches the log itself to notice when a
  quest disappears (turned in) versus gets abandoned.
- **Shows a waypoint arrow** for the current step's coordinates via TomTom
  (`Waypoints.lua`), with every location of the step as a marker on the world map and the
  minimap; clicking a goal with coordinates points the arrow there, and arriving at one moves
  the arrow on to the next. A step that
  only has a patrol path (e.g. a mob that walks around an area) gets an arrow that walks the path.
  The travel route and the patrol path are also drawn as lines on the world map and the minimap
  (Options → Maps).
- **Suggests gear upgrades** as you loot them: the Gear Advisor (`Item-Upgrades.lua`)
  scans a new bag item's tooltip (LibGratuity-2.0, with LibItemBonusLib-1.0's localized
  stat patterns), checks it's actually usable (via the game's own red-text "can't use this"
  convention) and scores it against your class's stat weights, popping up an equip/ignore
  choice in a standard game dialog (skinned by ElvUI/pfUI) when it's a real upgrade.
- **Suggests talents** level by level: the Talent Advisor follows a leveling build you pick
  in the options — marking the talent frame with the build's ranks and "+n" hints, adding
  the build's rank to talent tooltips, and asking before you learn a talent the build
  doesn't call for. Ships 25 builds, all nine classes, converted from Wowhead's WoW Classic
  leveling guides. Its advice window docks to the talent frame and opens with it. No
  automatic learning.
- **Automates the repetitive parts of questing.** `QuestAutoAccept.lua` can auto-accept
  and auto-turn-in quests the current guide step is already asking for, and auto-pick a
  quest's reward when there's a choice — preferring a real stat upgrade, falling back to
  whichever choice is worth the most gold at the vendor if none of them are.
- **Step navigation like Zygor's.** A finished step moves on past every step that is
  already done (and, optionally, steps that can't be done); the next arrow steps once on a
  left click and fast-forwards to the next incomplete step on a right click. Branching steps
  (e.g. "Yes, create a wand" / "No, I already have one") jump to the branch you pick.
- **Sticky reminders.** A step can stay pinned as a reminder across later steps
  (Zygor's own "sticky step" feature) until its own goal is actually done.

## Requirements

- A 1.12.1 client, or an Unreal Azeroth client (the Unreal Engine rebuild of 1.12.1). Both are
  supported targets.
- [TomTom](https://github.com/dh-harald/TomTom) installed, for the waypoint arrow.
- Ace3 and a couple of small standalone libraries, pulled in at build time (see below) —
  not something you need to install yourself.
- A leveling guide file from your own ZygorGuidesViewerClassic installation — see
  "Guide data" below.

**3.3.5a (Wrath) is not supported yet.** The `.toc`'s `Interface: 11210,30350` line and the
`#@version-wrath@` markers are groundwork for that client, and the code keeps Wrath-compatible
spellings where it can — but there is no Wrath build definition yet, and no Wrath testing or
feature work has happened. It's a planned future target, not a currently working one.

## Guide data

**This project ships no guide data, and never will.** Zygor's guides are paid subscription
content that belongs to Zygor; only the viewer is published here. Nothing in `Guides/` other
than `Autoload.xml` is part of this repository.

To actually use the addon, copy one of the leveling guide files out of your own
ZygorGuidesViewerClassic installation into `Guides/`, and add it to `Guides/Autoload.xml`:

```xml
<Script file="ZygorLevelingHordeCLASSIC.lua"/>
```

The addon was developed against **ZygorGuidesViewerClassic 1.1.29103**; guide files exported by
a different version may use DSL commands this viewer does not implement yet.

Each guide file registers itself through `ZGV:RegisterGuide` when it loads, so no further
wiring is needed. `Guides/*.lua` is gitignored, so a guide you drop in cannot be committed by
accident.

## Slash commands

| Command | What it does |
|---|---|
| `/zygor`, `/zygor help` | lists the arguments below |
| `/zygor show` | shows or hides the guide viewer |
| `/zygor config` | opens the options window |
| `/zygor qqc` | imports every quest the server says this character has completed, on server cores that support it |

## Building

This addon's dependencies (`LibStub`, `CallbackHandler-1.0`, all of Ace3, plus
`LibConfig-1.0`, `LibDataBroker-1.1` and `LibDBIcon-1.0` for the config UI and minimap icon) are
**not committed to this repo** — they're fetched at package time by the
[BigWigs packager](https://github.com/BigWigsMods/packager), via `.pkgmeta-vanilla`. Run the
packager against the repo to produce an installable addon folder; don't expect the `lib\...`
paths in the `.toc` to resolve without it.

## Talent builds

`TalentBuilds/` holds the builds the Talent Advisor offers. To add your own, create a new
`.lua` file there and list it in `TalentBuilds/Autoload.xml`. A build is the list of talent
points in the order you learn them, one `{tree, tier, column}` position per point, counted
from 1 (the comments are optional). The tree is the standard vanilla tab order — e.g. Mage
is Arcane 1, Fire 2, Frost 3 — even on a client that orders the tabs differently:

```lua
ZGV:RegisterTalentBuild("WARRIOR", "My Arms", {
    source = "where the build comes from (optional)",
    {1,1,2}, -- L10 Deflection (1/5)
    {1,1,2}, -- L11 Deflection (2/5)
    {1,1,3}, -- L12 Improved Rend (1/3)
})
```

The class is the English class token (`WARRIOR`, `PALADIN`, `HUNTER`, `ROGUE`, `PRIEST`,
`SHAMAN`, `MAGE`, `WARLOCK`, `DRUID`). A position with no talent on it, or more points in
a talent than it has ranks, marks the build as broken in the options.

## Known limitations / not implemented

This is a leveling-guide viewer, not a full Zygor replacement:

- **Leveling guides only.** Dungeon, profession, reputation, gold, and achievement guide
  types exist as data enum values but have no supporting logic — they're explicitly out
  of scope for now.
- **Partial condition language.** `|only`/`|if`/`|complete`/`|condition` expressions are
  evaluated with race/class, level, quest state, item counts, weapon and profession skills,
  zone/subzone, warlock pet and `walking` checks, all by English name. The gold-guide
  inventory and money scans aren't supported.
- **Travel routing is on the TomTom arrow only.** With the Travel System on (options), the
  arrow leads leg by leg — flight paths you know, boats, zeppelins, city gates, the
  hearthstone — but the viewer itself does not show the travel instruction yet.
  `talknpcs` and the general "find any of these NPCs by wandering" behavior aren't ported.
- **`|autoscript` is intentionally unimplemented.** It lets guide data execute arbitrary
  embedded Lua; that's a deliberately separate, higher-risk decision from everything
  else, not just an oversight.
- **Profession guides are out of scope.** The leveling guides' own skill goals (`|skill`,
  `|skillmax`: train First Aid, reach Lockpicking 95) are checked against your skill ranks;
  `openskill`, `talknpcs` and `findcity` only appear in Zygor's Startup Guide Wizard, which
  is hidden from the guide list as in Zygor's own viewer.
- **Quest-completion tracking has no memory before the addon was first run.** Without a
  live "was this quest ever completed" API, it can only learn about completions it
  personally observes happen — nothing retroactive. Some server cores expose a bulk-sync
  extension that would fix this; it's wired up as `/zygor qqc`, but not available on the
  server this was built against.
- **A first-login-only bug**: right after logging in on a fresh character, the two bundled
  guide files can occasionally register 0 guides ("Loaded 0 guides" in chat) because the
  vanilla client hasn't populated faction info yet at the exact moment they load.
  Re-opening the guide selection dropdown (or a `/reload`) after login fixes it for that
  session. Unresolved by design for now — flagged here rather than silently patched over.
- **The Talent Advisor is untested in-game** so far, on every client. It covers your own
  talents only (vanilla has no pet talents, glyphs, dual spec or talent preview).
- Gear Advisor scoring uses Zygor Classic's per-spec stat weights for the spec you pick
  in its options, or that your talent build picks; without either it falls back to a
  single static table per class. The weights themselves are not user-editable.

## Credits

- Zygor Guides — the original addon and guide format this project is a compatible
  viewer for.
- [pfQuest](https://github.com/shagu/pfQuest) by Eric Mauser (Shagu, MIT license) —
  source of the generated vanilla quest/zone databases this addon ships
  (`Data/QuestNames.lua`, `Data/ZoneIDs.lua`; see `LICENSE` for the full third-party license text).
- [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0) — source of the
  generated quest prerequisite table (`Data/QuestPrereqs.lua`).
- [Wowhead](https://www.wowhead.com) — the WoW Classic leveling guides the shipped talent
  builds (`TalentBuilds/`) are converted from; each build names its guide.
- [TomTom](https://github.com/superzunder/TomTom) for the waypoint arrow this addon
  drives.
- [Ace3](https://www.wowace.com/projects/ace3), LibDataBroker-1.1, and LibDBIcon-1.0 for
  the addon framework, config UI, and minimap button.

Large parts of this codebase — the Lua 5.0 compatibility layer, quest tracking, the Gear
Advisor, and the quest automation feature — were written with the help of
[Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant, guided
and tested in-game by the project's author.

## License

MIT — see `LICENSE`.
