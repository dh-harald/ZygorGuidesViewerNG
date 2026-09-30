-- Ported from the reference Zygor codebase's Goal.lua, scoped to leveling guides on 1.12.1.
-- Dropped entirely (not needed for leveling): achievement-bound goals, scenario-bound goals.
-- OR-logic goal groups are Step-level (see Step.lua); condition_visible/condition_complete are
-- evaluated by Parser.lua's EvaluateCondition. Coordinates are parsed and handed
-- to TomTom (Waypoints.lua), but arrival-based completion isn't computed here -- that would
-- need a pathing/position library equivalent to LibRover.

local Goal = {}
ZGV.GoalProto = Goal
ZGV.GoalProto_mt = { __index = Goal }

function Goal:New(data)
    setmetatable(data, ZGV.GoalProto_mt)
    return data
end

local GOALTYPES = {}
ZGV.GOALTYPES = GOALTYPES
local empty_table = {}
setmetatable(GOALTYPES, { __index = function() return empty_table end })

-- Colours of the named parts of a goal's text, as in ZygorGuidesViewerClassic.
local COLOR_LOC = "|cffffee77"
local COLOR_COUNT = "|cffffffcc"
local COLOR_ITEM = "|cffaaeeff"
local COLOR_QUEST = "|cffeebbff"
local COLOR_NPC = "|cffaaffaa"
local COLOR_MONSTER = "|cffffaaaa"
-- "(X/Y)" progress suffix: incomplete, and not currently possible.
local COLOR_PROGRESS = "|cffffbbbb"
local COLOR_PROGRESS_IMPOSSIBLE = "|cffaaaaaa"

local function Colored(color, s)
    return color..s.."|r"
end

local function QuestTitle(quest)
    return Colored(COLOR_QUEST, "'"..(quest or "?").."'")
end

-- Ported from Parser.lua's ParseID. The DSL tokenizer that calls this (Parser:ParseEntry)
-- isn't ported yet, but GOALTYPES parsing already needs this to split "Name##ID" params.
local function ParseID(str)
    local name, id, nid, obj
    name, id = string.match(str, "(.*)##([0-9/]*)")
    if not name then id = string.match(str, "^([0-9/]*)$") end
    if id then
        nid, obj = string.match(id, "([0-9]*)/([0-9]*)")
        if nid then id = nid end
    end
    if id then id = tonumber(id) end
    if obj then obj = tonumber(obj) end
    if not name and not id then name = str end
    return name, id, obj
end
ZGV.ParseID = ParseID

--- Goal status/completion dispatch (scoped down from the reference source)
-- @return status: "hidden" | "pending" | "passive" | "complete" | "impossible" | "incomplete"

function Goal:IsVisible()
    if self.hidden then return false end
    if self.notinsticky and self.parentStep:IsCurrentlySticky() then return false end
    -- A standalone (not goal-attached) |only/|if on a step gates every goal in it --
    -- see Parser.lua's only/if handling. step.hidden is the immediate bare-list form
    -- (baked once at parse time); step.condition_visible is the live "if <condition>"
    -- form (re-checked every call, since quest state/level change during a session).
    if self.parentStep.hidden then return false end
    if self.parentStep.condition_visible and not self.parentStep.condition_visible() then return false end
    -- "|only if <condition>" chunk-attached directly to this goal (see above).
    if self.condition_visible and not self.condition_visible() then return false end
    return true
end

local always_completable = {
    get = true, collect = true, accept = true, turnin = true, buy = true,
    home = true, hearth = true, learn = true,
}

function Goal:IsCompleteable()
    -- "|n" makes the goal passive, even when a quest is attached (e.g. "buy Grimoire of
    -- Blood Pact (Rank 1)##16321 |n", whose item is used up in the same step).
    if self.force_nocomplete then return false end
    if self.questid then return true end
    if self.condition_complete then return true end

    local goaltype = GOALTYPES[self.action]
    if goaltype.iscompletable then return goaltype.iscompletable(self) end
    if goaltype.iscomplete then return true end

    return always_completable[self.action] or false
end

--- @return complete, possible, numdone, numneeded
function Goal:IsComplete()
    -- "|complete <expression>" overrides the goal's own check when it is true. When it is
    -- false it decides alone, unless a quest (or |future) is attached to the goal, whose
    -- check then still runs -- the reference's order.
    if self.condition_complete then
        if self.condition_complete() then return true, true, 1, 1 end
        if not (self.questid or self.future) then return false, true, 0, 1 end
    end

    -- accept/turnin/confirm are checked via their own action type even when a |q is
    -- attached (e.g. "Click Here to Continue |confirm |q 5441" -- a manual fallback
    -- button, still clickable regardless of that quest's own progress). See
    -- GOALTYPES['confirm'].iscomplete for how it still folds a |q attachment in as an
    -- alternate, non-primary completion path.
    if self.action == "accept" or self.action == "turnin" or self.action == "confirm" then
        return GOALTYPES[self.action].iscomplete(self)
    end

    -- A quest-bound goal (self.questid set) is normally checked via its quest's live
    -- progress, not its own action type. But the reference source only treats that as FINAL
    -- when the quest check is actually complete, or the goal is bound to a specific
    -- objective number (self.objnum), or the quest is flat-out impossible and not |future --
    -- otherwise it falls through to ALSO try the goal's own action-type check (Goal.lua:2708-
    -- 2717 in the reference). This matters for a real, shipped pattern: "home Bloodhoof
    -- Village |q 860 |future" -- questid attached for context/tracking, but with no objnum
    -- and |future set, so it's meant to complete via its own type's check (GetBindLocation()
    -- for home) regardless of quest 860's state, not be gated on quest progress at all.
    -- Without this fallthrough, that goal's own iscomplete never ran -- confirmed by the user
    -- in-game via a debug trace that the home goal's iscomplete was simply never reached.
    if self.questid then
        local complete, possible, numdone, numneeded = GOALTYPES['q'].iscomplete(self)
        if complete or self.objnum or (not possible and not self.future) then
            return complete, possible, numdone, numneeded
        end

        local goaltype = GOALTYPES[self.action]
        if goaltype.iscomplete then
            local complete2, possible2, numdone2, numneeded2 = goaltype.iscomplete(self)
            return complete2, possible2 or possible or self.future, numdone or numdone2, numneeded or numneeded2
        end
        return complete, possible, numdone, numneeded
    end

    local goaltype = GOALTYPES[self.action]
    if goaltype.iscomplete then
        return goaltype.iscomplete(self)
    end

    return false, false
end

function Goal:GetStatus()
    if not self:IsVisible() then return "hidden" end
    -- Accepting is gated on Data/QuestPrereqs.lua's prerequisite list (turnin is not -- if the
    -- quest is already in the log, its own prereq was necessarily met when it was accepted).
    -- Visible-but-inert rather than hidden: the player should still see the quest waiting,
    -- just grayed out, and this status is what lets Step:IsComplete's existing "nothing
    -- actionable" shortcut skip the step forward without needing new step-level logic.
    if self.action == "accept" and self.questid and not ZGV:IsQuestPrereqMet(self.questid) then
        return "pending"
    end
    if not self:IsCompleteable() then return "passive" end

    local complete, possible, numdone, numneeded = self:IsComplete()
    if complete then return "complete", numdone, numneeded end
    if not possible then return "impossible" end
    return "incomplete", numdone, numneeded
end

function Goal:UpdateStatus()
    -- numdone/numneeded (e.g. 3/10 Kobold Vermin slain) are kept on the goal, not just
    -- returned, so the frame's row rendering (progress text + red->green color gradient)
    -- doesn't need to re-run completion checks a second time.
    self.status, self.numdone, self.numneeded = self:GetStatus()
    return self.status
end

--- The part of the goal an action bar button acts on, for the button's tooltip (see
--- ActionBar.lua): "Talk to X", "Click X", "Kill X", "Cast X", without the count or the
--- goal's own free-form text.
function Goal:GetActionText()
    if self.action == "talk" then return "Talk to "..Colored(COLOR_NPC, self.npc or "?") end
    if self.action == "clicknpc" then return "Click "..Colored(COLOR_ITEM, self.npc or "?") end
    if self.action == "kill" then return "Kill "..Colored(COLOR_MONSTER, self.target or "?") end
    if self.castspell then return "Cast "..Colored(COLOR_ITEM, self.castspell) end
    return "Use "..Colored(COLOR_ITEM, self.item or "?")
end

--- Human-readable display text ("Talk to X" / "Accept 'Y'"), matching the reference
-- addon's per-GOALTYPES `gettext` functions (see media/screen_1.jpg for the target look).
-- Falls back to the goal's own free-form text (step notes, "Click Here to Continue" before
-- a |confirm) or its raw action verb for types with no gettext defined. Appends "(X/Y)"
-- whenever there's a tracked count of more than 1, regardless of action type -- covers
-- kill/collect goals and quest-objective progress (GOALTYPES['q']) uniformly.
function Goal:GetText()
    local text

    -- self.text (free-form text written directly in the guide) ALWAYS wins over a
    -- GOALTYPES gettext when present -- matches the reference's own dispatch order. This
    -- matters a lot in practice: real guide data often writes a line's own instruction as
    -- plain text and then tacks on a |q/|goto/|accept etc. for data/tracking purposes only
    -- (e.g. "Awaken #5# Lazy Peons |q 5441/1 |goto 44.98,69.13") -- since
    -- "goal.action = goal.action or cmd" (Parser.lua) lets that later chunk's command claim
    -- the goal's action, using the generic GOALTYPES[action].gettext instead would silently
    -- throw away the actual instruction text the guide author wrote.
    if self.text then
        -- "#N#" is a placeholder for the goal's own count (e.g. "Awaken #5# Lazy Peons") --
        -- prefer the live remaining amount from numdone/numneeded (already computed by
        -- UpdateStatus by the time GetText runs) over the static N once quest/kill progress
        -- is actually being tracked, same idea as the reference's "remaining" value.
        text = string.gsub(self.text, "#(%d+)#", function(n)
            self.count = self.count or tonumber(n)
            local remaining = self.numneeded and math.max(0, self.numneeded - (self.numdone or 0))
            return Colored(COLOR_COUNT, tostring(remaining or self.count))
        end)
    else
        local goaltype = GOALTYPES[self.action]
        if goaltype.gettext then
            -- A malformed/unexpected goal (missing a field its gettext assumes, e.g. a nil
            -- self.npc) shouldn't take down the whole step's render -- fall back instead.
            local ok, result = pcall(goaltype.gettext, self)
            if ok and result then text = result end
        end
    end

    text = text or self.action or "?"

    if self.numneeded and self.numneeded > 1 then
        local progress = "("..(self.numdone or 0).."/"..self.numneeded..")"
        if self.status == "incomplete" then
            progress = Colored(COLOR_PROGRESS, progress)
        elseif self.status ~= "complete" then
            progress = Colored(COLOR_PROGRESS_IMPOSSIBLE, progress)
        end
        text = text.." "..progress
    end

    return text
end

local function CountedTarget(target, count)
    if count and count > 1 then
        return count.."x "..target
    end
    return target
end

--- Shared item/NPC/recipe parser: "[count ]Name##ID[+]"
GOALTYPES['_item'] = {
    parse = function(self, params)
        local count, objinfo = string.match(params, "^([0-9]+)%s+(.+)$")
        if not count then objinfo = params end

        local plural
        local name = string.match(objinfo, "^(.+)(%+)$")
        if name then
            objinfo = name
            plural = true
        end

        local target, targetid = ParseID(objinfo)

        self.count = tonumber(count)
        self.target, self.targetid = target, targetid
        self.plural = plural

        if not self.targetid and not self.target then return "no parameter" end
    end,
}

-- Pure item-count check, no quest API involved at all.
GOALTYPES['get'] = {
    parse = GOALTYPES['_item'].parse,
    iscomplete = function(self)
        if not self.targetid then return false, true end
        local count = self.count or 1
        local got = ZGV:GetItemCount(self.targetid)
        return got >= count, true, got, count
    end,
    gettext = function(self) return "Collect "..CountedTarget(Colored(COLOR_ITEM, self.target), self.count) end,
}
GOALTYPES['collect'] = GOALTYPES['get']

-- Opposite of get: complete once the item is gone (e.g. "trash this junk item").
GOALTYPES['trash'] = {
    parse = GOALTYPES['_item'].parse,
    iscomplete = function(self)
        if not self.targetid then return false, true end
        local got = ZGV:GetItemCount(self.targetid)
        return got == 0, true, (got == 0) and 1 or 0, 1
    end,
    gettext = function(self) return "Discard "..CountedTarget(Colored(COLOR_ITEM, self.target), self.count) end,
}
-- Reference source aliases "bank" straight to "trash" (both are "get this out of your
-- bags" -- bank just implies putting it in the bank rather than vendoring/destroying it,
-- same item-count-reaches-zero check either way).
GOALTYPES['bank'] = GOALTYPES['trash']

GOALTYPES['buy'] = {
    parse = function(self, params)
        self.future = true
        local err = GOALTYPES['_item'].parse(self, params)
        if err then return err end
        self.count = self.count or 1
    end,
    iscomplete = GOALTYPES['get'].iscomplete,
    gettext = function(self) return "Buy "..CountedTarget(Colored(COLOR_ITEM, self.target), self.count) end,
}

-- No standalone iscomplete for kill/use/click/talk: in practice these are quest-objective-
-- bound (self.questid set on the goal), and get checked via GOALTYPES['q'] instead -- see
-- Goal:IsComplete()'s dispatch order above. A bare non-quest kill/use/click/talk goal (rare
-- in leveling guides per the confirmed DSL vocabulary sample) would have no way to complete
-- on its own here; that's a known, deferred gap, not a silent bug.
GOALTYPES['kill'] = {
    parse = GOALTYPES['_item'].parse,
    gettext = function(self) return "Kill "..CountedTarget(Colored(COLOR_MONSTER, self.target), self.count) end,
}

-- Same "no standalone completion" situation as kill/use/click/talk above -- the reference
-- source doesn't have one for "cast" either, only quest-bound via |q in practice.
GOALTYPES['cast'] = {
    parse = function(self, params)
        local err = GOALTYPES['_item'].parse(self, params)
        if err then return err end
        self.castspell, self.castspellid = self.target, self.targetid
    end,
    gettext = function(self) return "Cast "..Colored(COLOR_ITEM, self.castspell or "?") end,
}

GOALTYPES['use'] = {
    parse = function(self, params)
        local err = GOALTYPES['_item'].parse(self, params)
        if err then return err end
        self.item, self.itemid = self.target, self.targetid
    end,
    gettext = function(self) return "Use "..Colored(COLOR_ITEM, self.item) end,
}

GOALTYPES['click'] = {
    parse = GOALTYPES['_item'].parse,
    gettext = function(self) return "Click "..Colored(COLOR_ITEM, self.target) end,
}

GOALTYPES['clicknpc'] = {
    parse = function(self, params)
        local err = GOALTYPES['_item'].parse(self, params)
        if err then return err end
        self.npc, self.npcid = self.target, self.targetid
    end,
    gettext = function(self) return "Click "..Colored(COLOR_ITEM, self.npc or "?") end,
}

GOALTYPES['talk'] = {
    parse = function(self, params)
        local err = GOALTYPES['_item'].parse(self, params)
        if err then return err end
        self.npc, self.npcid = self.target, self.targetid
        if not self.npc and not self.npcid then return "no npc" end
    end,
    gettext = function(self) return "Talk to "..Colored(COLOR_NPC, self.npc) end,
}

-- As in ZygorGuidesViewerClassic: complete once this NPC's merchant window has been opened and
-- closed again. OnMerchantShow below sets self.vendor_opened on MERCHANT_SHOW and tracks
-- ZGV.merchantOpen. The NPC is matched by name, as the vanilla client has no unit GUID.
GOALTYPES['vendor'] = {
    parse = function(self, params)
        local err = GOALTYPES['_item'].parse(self, params)
        if err then return err end
        self.npc, self.npcid = self.target, self.targetid
        if not self.npc and not self.npcid then return "no npc" end
    end,
    iscomplete = function(self)
        return (self.vendor_opened and not ZGV.merchantOpen) or false, true
    end,
    gettext = function(self) return "Visit "..Colored(COLOR_NPC, self.npc or "?") end,
}

-- Recipe learning: parse only for now. Completion needs a profession-recipe-known check
-- (ZGV.Professions:KnowsRecipe in the reference source), and professions are out of scope
-- for the leveling-only phase of this addon -- deferred.
GOALTYPES['learn'] = {
    parse = function(self, params)
        self.recipe, self.recipeid = ParseID(params)
        if not self.recipeid then return "'learn': no recipe found" end
    end,
    gettext = function(self) return "Learn "..Colored(COLOR_ITEM, self.recipe) end,
}

-- Reference source checks IsSpellKnown(spellid), which needs numeric-ID spell lookup --
-- unconfirmed whether that (or GetSpellInfo(id) for display text) actually works on 1.12.1,
-- and real usage here is always spells with real vanilla IDs, unlike havebuff/nobuff's
-- retail-only ones (mage teleports, Pick Pocket). Sidesteps the question entirely by
-- matching on the spell NAME the guide data already gives us (self.spell, from ParseID)
-- against a spellbook scan -- GetSpellName/BOOKTYPE_SPELL are old, foundational spellbook
-- APIs, same vanilla-safety tier as everything else name-matched in this file.
GOALTYPES['learnspell'] = {
    parse = function(self, params)
        self.spell, self.spellid = ParseID(params)
        if not self.spell and not self.spellid then return "'learnspell': no spell found" end
    end,
    iscomplete = function(self)
        for i = 1, 300 do
            local name = GetSpellName(i, BOOKTYPE_SPELL)
            if not name then break end
            if name == self.spell then return true, true end
        end
        return false, true
    end,
    gettext = function(self) return "Learn "..Colored(COLOR_ITEM, self.spell or "?") end,
}

-- Name and rank of each pet spell ID the guides reference. The rank cannot be read from the
-- ID on this client, and the name tells nothing on its own: an imp has Firebolt (Rank 1)
-- before it is taught Rank 2. The table's name also wins over the guide's, which is wrong
-- in places ("Teach Your Imp Firebolt (Rank 2) |learnpetspell Blood Pact##7799").
local PET_SPELLS = {
    [6307]  = { "Blood Pact", 1 },
    [7799]  = { "Firebolt", 2 },
    [7812]  = { "Sacrifice", 1 },
    [17767] = { "Consume Shadows", 1 },
}

-- Checks the pet spellbook, which only lists the spells of the pet currently summoned: with
-- no pet, or another one, the goal stays incomplete, as IsSpellKnown(id, true) does in
-- Classic. Any rank at or above the required one counts. An ID missing from PET_SPELLS is
-- matched on the guide's spell name alone.
GOALTYPES['learnpetspell'] = {
    parse = function(self, params)
        self.spell, self.spellid = ParseID(params)
        local known = self.spellid and PET_SPELLS[self.spellid]
        if known then self.spell, self.rank = known[1], known[2] end
        if not self.spell then return "'learnpetspell': no spell found" end
    end,
    iscomplete = function(self)
        for i = 1, 100 do
            local name, rank = GetSpellName(i, "pet")
            if not name then break end
            if name == self.spell then
                local r = tonumber(string.match(rank or "", "(%d+)")) or 0
                if not self.rank or r >= self.rank then return true, true end
            end
        end
        return false, true
    end,
    gettext = function(self)
        if self.rank then return "Teach your pet "..Colored(COLOR_ITEM, self.spell).." (Rank "..self.rank..")" end
        return "Teach your pet "..Colored(COLOR_ITEM, self.spell)
    end,
}

-- "skill Lockpicking,95": the skill line's rank reaches the level; possible once its maximum
-- rank allows it. "skillmax First Aid,75": the maximum rank reaches the level, i.e. the
-- trainer rank is learned. Both as in ZygorGuidesViewerClassic, by the English skill name.
GOALTYPES['skill'] = {
    parse = function(self, params)
        local skill, level = string.match(params, "^(.+),(%d+)$")
        if not skill then return "'skill*': no skill found" end
        self.skill, self.skilllevel = skill, tonumber(level)
    end,
    iscomplete = function(self)
        local rank, maxrank = ZGV:GetSkillRank(self.skill)
        return rank >= self.skilllevel, maxrank >= self.skilllevel
    end,
    gettext = function(self) return "Achieve "..Colored(COLOR_ITEM, self.skill).." level "..self.skilllevel end,
}

GOALTYPES['skillmax'] = {
    parse = GOALTYPES['skill'].parse,
    iscomplete = function(self)
        local _, maxrank = ZGV:GetSkillRank(self.skill)
        return maxrank >= self.skilllevel, true
    end,
    gettext = function(self) return "Learn "..Colored(COLOR_ITEM, self.skill).." profession" end,
}

-- "ding <level>[,<exp>]" -- complete once the player reaches a given level (and, if an
-- exp target is given, at least that much XP into it). Ported from the reference's
-- GOALTYPES['level'] ("ding" is just an alias for it there too, resolved by rewriting cmd
-- at parse time -- here it's a direct table alias instead, see below, so no special
-- dispatch handling is needed). numdone/numneeded here are the player's live XP progress
-- toward that level, which reuses the same "(X/Y)" text suffix and red->green row
-- coloring already built for kill/collect goals (see ZGV:UpdateFrame) --
-- no separate progress-bar-coloring logic needed on top of what's already there.
GOALTYPES['level'] = {
    parse = function(self, params)
        local level, exp = string.match(params, "([0-9]*),([0-9]*)")
        if exp and exp ~= "" then
            self.level = tonumber(level)
            self.exp = tonumber(exp)
        else
            self.level = tonumber(params)
        end
        if not self.level then return "'level'/'ding': invalid level value" end
    end,
    iscomplete = function(self)
        local level = ZGV:GetPlayerPreciseLevel()
        if level < self.level - 1 then
            return false, true, 0, 100
        elseif math.floor(level) > self.level then
            return true, true
        elseif math.floor(level) >= self.level and UnitXP("player") >= (self.exp or 0) then
            return true, true
        else
            return false, true, UnitXP("player"), self.exp or UnitXPMax("player")
        end
    end,
    gettext = function(self)
        if self.exp then
            return "Reach level "..Colored(COLOR_NPC, self.level).." ("..Colored(COLOR_NPC, self.exp).." xp)"
        end
        return "Reach level "..Colored(COLOR_NPC, self.level)
    end,
}
GOALTYPES['ding'] = GOALTYPES['level']

GOALTYPES['home'] = {
    parse = function(self, params)
        self.param = params
        if not self.param then return "no parameter" end
    end,
    iscomplete = function(self)
      local current = GetBindLocation()
      return current ~= nil and current == self.param, true
    end,
    gettext = function(self) return "Set hearthstone location in "..Colored(COLOR_LOC, self.param) end,
}

-- A flight point is resolved through LibTaxi-1.0 on first use, not at parse time: the node's
-- position tag only exists once LibTaxi:Startup has run (ZGV:StartTravel). Completion reads
-- ZGV.db.char.taxis, LibTaxi's saved table, under the tag, or the English name when the node
-- has none, as ZygorGuidesViewerClassic does.
local function ResolveTaxi(goal)
    if goal.taxiident or not (ZGV.LibTaxi and ZGV.LibTaxi.ready) then return end
    local node = ZGV.LibTaxi:FindTaxi(goal.fpathname)
    if node then
        goal.fpathlocalname = node.localname
        goal.taxiident = node.taxitag or node.name
    else
        goal.taxiident = goal.fpathname
    end
end

GOALTYPES['fpath'] = {
    parse = function(self, params)
        -- Named self.fpathname/self.fpathid (not self.quest/self.questid, despite reusing
        -- ParseID) so this never accidentally sets self.questid -- Goal:IsComplete would
        -- otherwise route it through GOALTYPES['q'] instead of this iscomplete the moment
        -- any guide line happened to add a "##N" suffix.
        self.fpathname, self.fpathid = ParseID(params)
        if not self.fpathname and not self.fpathid then return "no parameter" end
    end,
    iscomplete = function(self)
        ResolveTaxi(self)
        return self.taxiident and ZGV.db.char.taxis[self.taxiident] and true or false, true
    end,
    gettext = function(self)
        ResolveTaxi(self)
        return "Discover flight point: "..Colored(COLOR_LOC, self.fpathlocalname or self.fpathname or "?")
    end,
}

GOALTYPES['hearth'] = {
    parse = function(self, params)
        self.item = "Hearthstone"
        self.itemid = 6948
        self.param = params
    end,
    iscomplete = function(self)
        return GetZoneText() == self.param
            or GetMinimapZoneText() == self.param
            or GetSubZoneText() == self.param, true
    end,
    gettext = function(self) return "Hearth to "..Colored(COLOR_LOC, self.param) end,
}

-- The guide data references a buff by its icon's FileDataID ("havebuff 132331") or by spell ID
-- ("havebuff spell:25678"), but this client's UnitBuff/UnitDebuff only ever return the icon
-- path -- no spell ID, no name. ZGV.BuffTextures (Data/BuffTextures.lua) maps both forms to
-- the icon key; an ID with no entry defaults to "condition met" rather than blocking guide
-- progress on a check we can't evaluate -- same permissive-default convention as an
-- unhandled |only/|if.
-- The icon path differs per client (Interface\Icons\Name on vanilla,
-- /Game/Interface/Icons/Name_TEX on Unreal Azeroth), so both sides are compared as the
-- lowercase file name without directory, extension or "_tex" suffix.
local function IconKey(texture)
    if type(texture) ~= "string" then return nil end
    local key = string.lower(texture)
    key = string.gsub(key, "^.*[\\/]", "")
    key = string.gsub(key, "%.[a-z0-9]+$", "")
    key = string.gsub(key, "_tex$", "")
    return key
end

local function HasBuffTexture(key)
    for i = 1, 32 do
        local t = UnitBuff("player", i)
        if not t then break end
        if IconKey(t) == key then return true end
    end
    for i = 1, 40 do
        local t = UnitDebuff("player", i)
        if not t then break end
        if IconKey(t) == key then return true end
    end
    return false
end

GOALTYPES['havebuff'] = {
    parse = function(self, params)
        local name, id = ParseID(params)
        self.buffid = tonumber(id) or tonumber(name)
        if not self.buffid and name and string.find(name, "^spell:%d+$") then self.buffid = name end
        if not self.buffid then return "'havebuff': no spell id found" end
    end,
    iscomplete = function(self)
        local texture = ZGV.BuffTextures[self.buffid]
        if not texture then return true, true end
        return HasBuffTexture(texture), true
    end,
    gettext = function(self) return "Have buff: "..Colored(COLOR_ITEM, self.buffid) end,
}

GOALTYPES['nobuff'] = {
    parse = GOALTYPES['havebuff'].parse,
    iscomplete = function(self)
        local texture = ZGV.BuffTextures[self.buffid]
        if not texture then return true, true end
        return not HasBuffTexture(texture), true
    end,
    gettext = function(self) return "No buff: "..Colored(COLOR_ITEM, self.buffid) end,
}

-- Quest acceptance/turn-in. "Already done" reuses the same completed-quest history
-- QuestTracking.lua builds; "currently accepted" is a live questlog check via
-- ZGV:GetQuestObjectiveProgress (only its first return value, inLog, is used here).
GOALTYPES['accept'] = {
    parse = function(self, params)
        self.quest, self.questid = ParseID(params)
        if not self.quest and not self.questid then return "no quest parameter" end
    end,
    iscomplete = function(self)
        if ZGV.db.char.quests[self.questid] then return true, true end
        local inLog = ZGV:GetQuestObjectiveProgress(self.questid)
        return inLog and true or false, true
    end,
    gettext = function(self) return "Accept "..QuestTitle(self.quest) end,
}

GOALTYPES['turnin'] = {
    parse = GOALTYPES['accept'].parse,
    iscomplete = function(self)
        if not ZGV.db.char.quests[self.questid] then return false, true end
        -- AND, not just the completed-history check: a repeatable quest can be both
        -- flagged completed AND back in the log at the same time (re-accepted). Only
        -- count it done here once it's also no longer active -- same guard the reference
        -- source uses for this exact repeatable-quest edge case.
        local inLog = ZGV:GetQuestObjectiveProgress(self.questid)
        return not inLog, true
    end,
    gettext = function(self) return "Turn in "..QuestTitle(self.quest) end,
}

-- Quest-objective progress (the goal type most quest-bound talk/kill/collect/use/click
-- goals actually dispatch to -- see Goal:IsComplete() above). Built entirely on
-- QuestTracking.lua's ZGV.db.char.quests (completed-quest history) and
-- ZGV:GetQuestObjectiveProgress (live per-objective progress), both already 1.12-safe.
GOALTYPES['q'] = {
    parse = function(self, params)
        self.quest, self.questid, self.objnum = ParseID(params)
        if not self.questid then return "|q: no questid in parameter" end
    end,
    iscomplete = function(self)
        if ZGV.db.char.quests[self.questid] then return true, true end

        local inLog, done, num, needed = ZGV:GetQuestObjectiveProgress(self.questid, self.objnum)
        if not inLog then return false, false end
        if not self.objnum then return false, true end

        -- The goal's own count ("kill 12 X", "|count 6") is the target, as in
        -- ZygorGuidesViewerClassic: a step can end at part of an objective.
        if not done and self.count and num then
            return num >= self.count, true, num, self.count
        end
        return done or false, true, num, needed
    end,
    -- Rare as a primary action (usually a |q modifier tacked onto another goal, which
    -- keeps that goal's own gettext) -- only shown if |q was the only chunk on the line.
    gettext = function(self) return "Progress: "..QuestTitle(self.quest) end,
}

-- Standalone goto/at (no other action on the line got a chance to claim goal.action --
-- see Parser.lua's "goal.action = goal.action or cmd" rule). Just display text for now;
-- there's no distance-to-waypoint check here (would need a LibRover-equivalent pathing
-- library), so these aren't completable on their own -- same limitation as a bare non-
-- quest kill/use/click/talk. The waypoint arrow itself (TomTom) is driven separately, by
-- whichever goal on the current step has map/x/y set, regardless of its action type.
GOALTYPES['goto'] = {
    -- A goto's own free text ("Enter the building |goto 44.32,76.21") is the intended
    -- display, not an auto-generated "Go to X" -- that's only a fallback for a bare
    -- goto/at with no text of its own.
    gettext = function(self)
        if self.text then return self.text end
        return "Go to "..Colored(COLOR_LOC, self.mapname or "location")
    end,
}
GOALTYPES['at'] = GOALTYPES['goto']

-- "Click Here to Continue |confirm"-style manual-advance goals. The row itself is made
-- clickable when this is the goal's action (see ZGV:UpdateFrame's RenderGoal),
-- which sets self.manually_confirmed on click. A |q attachment (e.g. "|confirm |q 5441" --
-- a fallback for "click here if you haven't finished the tracked objective yet") is folded
-- in as an ALTERNATE completion path, not the primary one: Goal:IsComplete() dispatches
-- confirm goals here directly rather than through GOALTYPES['q'], precisely so the click
-- always works even while that quest is still active.
GOALTYPES['confirm'] = {
    parse = function() end,
    iscomplete = function(self)
        if self.manually_confirmed then return true, true end
        if self.questid and ZGV.db.char.quests[self.questid] then return true, true end
        return false, true
    end,
}

-- GOALTYPES['home'].iscomplete above reads GetBindLocation() live, but the vanilla client
-- has no event for a completed bind (no HEARTHSTONE_BOUND). Binding always goes through an
-- innkeeper's gossip, so GOSSIP_CLOSED re-renders right away, and because the gossip window
-- closes before the bind confirmation popup is accepted, the bind location is then watched for a
-- while: the viewer re-renders as soon as it changes.
local BIND_WATCH_INTERVAL = 1
local BIND_WATCH_TICKS = 30

local bindWatchTimer, bindWatchFrom, bindWatchLeft

local function StopBindWatch()
    if bindWatchTimer then ZGV:CancelTimer(bindWatchTimer) end
    bindWatchTimer = nil
end

local function CheckBindLocation()
    bindWatchLeft = bindWatchLeft - 1
    if GetBindLocation() ~= bindWatchFrom then
        StopBindWatch()
        ZGV:UpdateFrame()
    elseif bindWatchLeft <= 0 then
        StopBindWatch()
    end
end

function ZGV:OnGossipClosed()
    ZGV:UpdateFrame()

    StopBindWatch()
    bindWatchFrom = GetBindLocation()
    bindWatchLeft = BIND_WATCH_TICKS
    bindWatchTimer = ZGV:ScheduleRepeatingTimer(CheckBindLocation, BIND_WATCH_INTERVAL)
end
ZGV:RegisterEvent("GOSSIP_CLOSED", "OnGossipClosed")

-- GOALTYPES['vendor'] above: opening a vendor's merchant window marks every vendor goal for
-- that NPC in the current step and its stickies; closing the window completes them.
local function MarkVendorGoals(step, npc)
    for _, goal in ipairs(step.goals) do
        if goal.action == "vendor" and goal.npc == npc then goal.vendor_opened = true end
    end
end

function ZGV:OnMerchantShow()
    ZGV.merchantOpen = true
    local npc = UnitName("npc")
    if npc and ZGV.CurrentStep then
        MarkVendorGoals(ZGV.CurrentStep, npc)
        for _, stickystep in ipairs(ZGV.CurrentStickies or {}) do
            MarkVendorGoals(stickystep, npc)
        end
    end
    ZGV:UpdateFrame()
end

function ZGV:OnMerchantClosed()
    ZGV.merchantOpen = nil
    ZGV:UpdateFrame()
end
ZGV:RegisterEvent("MERCHANT_SHOW", "OnMerchantShow")
ZGV:RegisterEvent("MERCHANT_CLOSED", "OnMerchantClosed")
