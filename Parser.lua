-- Ported from the reference Zygor codebase's Parser.lua (Parser:ParseEntry), scoped to
-- leveling guides on 1.12.1. This turns a guide's raw DSL text (the [[ ... ]] string
-- passed to ZGV:RegisterGuide) into the guide.steps / step.goals object tree that
-- Guide.lua/Step.lua/Goal.lua operate on.
--
-- Not supported: #include / leechsteps (cross-guide step reuse), macro guides, scripts and
-- models. Goal-level |sticky (force_sticky) is parsed and stored, but nothing acts on it.
--
-- Conditions (|only, |if, |complete, |condition, |stickyif) are evaluated live by
-- EvaluateCondition below. Sticky steps (stickystart/stickystop/step-level sticky) collect
-- step.sticky_labels, which Guide:Parse resolves into step.stickies.
--
-- map/goto/at take the "[ZoneName ]x,y[<dist|>dist]" form (no floor or dungeon level),
-- resolved through Data/ZoneIDs.lua. A missing zone name inherits the last zone resolved
-- earlier in the same guide (prevmap, below), since real guide data names the zone only on
-- the first goto/map in an area. A step-level path is parsed into step.waypath and followed
-- by the arrow; its ants and markers options are ignored.

ZGV.Parser = {}
local Parser = ZGV.Parser

local GOALTYPES = ZGV.GOALTYPES

-- "_text_" in free-form goal text and |tip text is shown in the highlight colour, as in the
-- reference viewer. "\_" is a literal underscore: it is cloaked as "\001" while the
-- highlight pairs are matched, then restored.
local HIGHLIGHT_COLOR = "|cffffee88"
-- "[x,y]" coordinates written into goal text, in the reference viewer's location colour.
local COORDS_COLOR = "|cffffee77"
local function HighlightText(text)
    text = string.gsub(text, "\\_", "\001")
    text = string.gsub(text, "_(.-)_", HIGHLIGHT_COLOR.."%1|r")
    text = string.gsub(text, "\001", "_")
    return text
end

-- "[ZoneName ]x,y[<dist|>dist]" -> mapid, x, y (as 0..1 fractions), mapname, dist.
-- Returns nil if there's no usable coordinate pair. If no zone name is given, falls back
-- to prevmap/prevmapname (the last zone resolved earlier in the same guide) -- mapname is
-- always returned alongside the id when a zone is resolved at all (inherited or explicit),
-- since TomTom's AddMFWaypoint (see Waypoints.lua) needs the name, not our numeric id, to
-- place a waypoint. dist is the number after < or >, negated for ">" (matching the
-- reference convention: "<40" means "arrive within 40 yards", ">40" means "leave the area").
local function ParseZoneXY(params, prevmap, prevmapname)
    local dist, disttype
    local rest, dt, d = string.match(params, "^(.-)%s*([<>])%s*(%-?[%d%.]+)%s*$")
    if rest then
        params = rest
        disttype, dist = dt, tonumber(d)
        if disttype == ">" and dist then dist = -dist end
    end

    local mapname, x, y = string.match(params, "^(.-)%s*,?%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*$")
    if not x then return nil end

    local mapid
    if mapname ~= "" then
        mapid = ZGV.ZoneIDs[mapname]
    else
        mapid = prevmap
        mapname = prevmapname
    end
    if not mapid then return nil end

    return mapid, tonumber(x) / 100, tonumber(y) / 100, mapname, dist
end
Parser.ParseZoneXY = ParseZoneXY

-- Stand-in for the reference's condition system (ZGV.Parser.ConditionEnv/MakeCondition).
-- Evaluated FRESH every time (not baked in once at parse time -- see Goal:IsVisible in
-- Goal.lua, which calls EvaluateCondition live), since quest state and level change
-- during a session. Handles, in order:
--   - a bare class/race name, or comma list of them, OR'd ("|only if Priest",
--     "|only Priest,Paladin") -- kept as plain word-matching, no function needed, matching
--     how the reference itself treats race/class specially (word-substitution before
--     falling to its general expression evaluator), not a real ConditionEnv function.
--   - a two-word "Race Class" combo, AND'd ("|only if Tauren Warrior", "|only if Scourge
--     Warlock") -- same reference convention (races and classes get combined with "and"
--     before evaluation).
--   - "level<op><number>" ("level>=20"), using ZGV:GetPlayerPreciseLevel() (fractional,
--     continuously up to date) -- the reference doesn't call a "level()" function either,
--     it keeps a live-updated `level` value in ConditionEnv and lets expressions reference
--     it directly.
--   - a single quest-state function call spanning the whole condition ("haveq(1234)",
--     "completedq(1234,5678)", "readyq(1234)") -- matching the reference ConditionEnv
--     functions of the same names. Comma-separated args here are OR'd. Built on
--     QuestTracking.lua's existing ZGV.db.char.quests/ZGV.ActiveQuests.
--   - anything else ("(Orc or Troll) and Rogue", "not (Hunter or Warlock)", "Shaman and
--     itemcount(1234) == 0") is already valid Lua syntax once race/class names and the
--     functions above are plain identifiers -- so instead of hand-rolling an and/or/not/
--     parens expression parser, this compiles the text as a real Lua chunk (loadstring)
--     and runs it in a sandboxed environment (setfenv) exposing those names. This is very
--     likely what the reference's ConditionEnv/MakeCondition does under the hood too.
--     loadstring/setfenv are both plain Lua 5.0 base-library functions (present unmodified
--     since 5.0, not a 5.1-ism), so this works as-is on the 1.12 client.
-- Anything that still can't be evaluated (syntax error, unknown identifier) returns the
-- caller's fallback -- visible (true) for |only/|if, not complete (false) for |complete -- and
-- prints the raw condition text once (see warnedConditions) so it's obvious what still needs
-- support.

local RACE_CLASS_WORDS = {
    warrior = true, paladin = true, hunter = true, rogue = true, priest = true,
    shaman = true, mage = true, warlock = true, druid = true,
    human = true, dwarf = true, nightelf = true, gnome = true,
    orc = true, undead = true, scourge = true, tauren = true, troll = true,
}
local RACE_CLASS_ALIASES = { undead = "scourge" }

local function PlayerMatchesWord(word)
    word = RACE_CLASS_ALIASES[word] or word

    local _, class = UnitClass("player")
    if class and string.lower(class) == word then return true end

    local _, race = UnitRace("player")
    if race then
        race = string.lower((string.gsub(race, "[%s%-']", "")))
        race = RACE_CLASS_ALIASES[race] or race
        if race == word then return true end
    end

    return false
end

-- Quest-condition functions, matching the reference ConditionEnv's haveq/completedq/
-- readyq. Each takes a single quest id (the dispatcher below handles comma-separated
-- OR-lists, e.g. "completedq(1234,5678)"); add more here as needed.
local QUEST_CONDITION_FUNCS = {
    haveq = function(id)
        local inLog = ZGV:GetQuestObjectiveProgress(id)
        return inLog and true or false
    end,
    completedq = function(id)
        return ZGV.db.char.quests[id] and true or false
    end,
    readyq = function(id)
        local q = ZGV.ActiveQuests[id]
        if not q then return false end
        if q.complete or not q.goals then return true end
        for objnum, goal in pairs(q.goals) do
            if not goal.done then return false end
        end
        return true
    end,
}

-- Canonical identifier casing for the general-expression fallback below (e.g. "(Orc or
-- Troll) and Rogue", "not (Hunter or Warlock)"). Kept separate from RACE_CLASS_WORDS
-- (lowercase, used by the plain word-list form above) since Lua identifiers are
-- case-sensitive and guide authors write these capitalized.
local RACE_CLASS_CANONICAL = {
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid",
    "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Undead", "Scourge", "Tauren", "Troll",
}

local function BuildConditionEnv()
    local env = {}
    for _, name in ipairs(RACE_CLASS_CANONICAL) do
        env[name] = PlayerMatchesWord(string.lower(name))
    end
    env.level = ZGV:GetPlayerPreciseLevel()
    -- As in ZygorGuidesViewerClassic: route hints ("|only if walking") show unless the
    -- player is flying.
    env.walking = not (IsFlying and IsFlying())
    env.itemcount = function(id) return ZGV:GetItemCount(id) end
    env.weaponskill = function(tag) return ZGV:GetWeaponSkill(tag) end
    env.hasprof = function(name, minlevel) return ZGV:GetSkillRank(name) >= (minlevel or 1) end
    -- The reference prompts to open each profession window once for its gold guides; there
    -- is no profession scan here, so there is never anything left to scan.
    env.hasprofunscanned = function() return false end
    env.subzone = function(name) return GetMinimapZoneText() == name end
    env.zone = function(name) return GetRealZoneText() == name end
    env.warlockpet = function(family) return UnitExists("pet") and UnitCreatureFamily("pet") == family end
    env._G = getfenv(0)
    for name, fn in pairs(QUEST_CONDITION_FUNCS) do
        env[name] = fn
    end
    return env
end

-- A bare "Race Class" combo (juxtaposition = AND, no explicit "and") is still valid guide
-- syntax inside a general expression too ("not Orc Warlock" should mean "not (Orc and
-- Warlock)"), but juxtaposition isn't a Lua operator, so it has to be rewritten into
-- explicit "(Race and Class)" form before loadstring ever sees it. This can't be a plain
-- global gsub over "(%a+)%s+(%a+)" pairs: gsub's non-overlapping left-to-right scan would
-- consume "not Orc" as one (non-matching, left unchanged) pair first, which then leaves
-- "Warlock" stranded with nothing before it to pair with. Walking word-by-word instead and
-- only advancing past a single word when its pair doesn't match avoids that.
local function ExpandRaceClassPairs(text)
    local result = {}
    local pos = 1
    while true do
        local s1, e1, w1 = string.find(text, "(%a+)", pos)
        if not s1 then
            tinsert(result, string.sub(text, pos))
            break
        end
        tinsert(result, string.sub(text, pos, s1 - 1))

        local s2, e2, w2 = string.find(text, "^%s+(%a+)", e1 + 1)
        if s2 and RACE_CLASS_WORDS[string.lower(w1)] and RACE_CLASS_WORDS[string.lower(w2)] then
            tinsert(result, "("..w1.." and "..w2..")")
            pos = e2 + 1
        else
            tinsert(result, w1)
            pos = e1 + 1
        end
    end
    return table.concat(result)
end

-- Compiled chunks are cached by source text (loadstring isn't cheap, and the same
-- condition text is re-evaluated on every visibility check); the environment is rebound
-- fresh via setfenv on every call instead, since level/quest/item state changes live.
local compiledExpressions = {}
local function CompileExpression(text)
    local compiled = compiledExpressions[text]
    if compiled == nil then
        local chunk = loadstring("return ("..ExpandRaceClassPairs(text)..")")
        compiled = chunk or false
        compiledExpressions[text] = compiled
    end
    return compiled or nil
end

-- Runs a compiled condition in a fresh environment. indoors, when given, is what the
-- environment's _G.IsIndoors() answers. Returns ok, result.
local function RunExpression(chunk, indoors)
    local env = BuildConditionEnv()
    if indoors ~= nil then
        env._G = setmetatable({ IsIndoors = function() return indoors end }, { __index = env._G })
    end
    setfenv(chunk, env)
    local ok, result = pcall(chunk)
    return ok, result and true or false
end

local warnedConditions = {}
local function ReportUnknownCondition(text)
    if not warnedConditions[text] then
        warnedConditions[text] = true
        ZGV:Print("Guide condition not implemented: "..text)
    end
end

-- text is everything after "only"/"if"/"complete" (the leading "if " is stripped if present).
-- fallback is returned for a condition that cannot be evaluated; it defaults to true.
local function EvaluateCondition(text, fallback)
    if fallback == nil then fallback = true end
    text = string.gsub(text, "^if%s+", "")
    text = string.gsub(text, "^%s*(.-)%s*$", "%1")
    local lower = string.lower(text)

    -- "level<op><number>"
    local op, num = string.match(lower, "^level%s*([<>=~]+)%s*(%d+)$")
    if op then
        num = tonumber(num)
        local level = ZGV:GetPlayerPreciseLevel()
        if op == ">=" then return level >= num
        elseif op == "<=" then return level <= num
        elseif op == ">" then return level > num
        elseif op == "<" then return level < num
        elseif op == "==" or op == "=" then return level == num
        elseif op == "~=" or op == "!=" then return level ~= num
        end
        ReportUnknownCondition(text)
        return fallback
    end

    -- "funcname(arg[,arg...])" -- quest-condition functions
    local funcName, funcArgs = string.match(lower, "^(%a+)%s*%((.-)%)$")
    if funcName and QUEST_CONDITION_FUNCS[funcName] then
        local fn = QUEST_CONDITION_FUNCS[funcName]
        local any = false
        for arg in string.gmatch(funcArgs, "[^,]+") do
            local id = tonumber((string.gsub(arg, "^%s*(.-)%s*$", "%1")))
            if id and fn(id) then any = true end
        end
        return any
    end

    -- Race/class word or comma list (OR'd), each entry optionally a two-word "Race Class"
    -- combo (AND'd).
    local anyKnown, anyMatch = false, false
    for word in string.gmatch(text, "[^,]+") do
        word = string.gsub(word, "^%s*(.-)%s*$", "%1")

        local w1, w2 = string.match(word, "^(%a+)%s+(%a+)$")
        if w1 and w2 then
            w1, w2 = string.lower(w1), string.lower(w2)
            if RACE_CLASS_WORDS[w1] and RACE_CLASS_WORDS[w2] then
                anyKnown = true
                if PlayerMatchesWord(w1) and PlayerMatchesWord(w2) then anyMatch = true end
            end
        else
            local single = string.lower(word)
            if RACE_CLASS_WORDS[single] then
                anyKnown = true
                if PlayerMatchesWord(single) then anyMatch = true end
            end
        end
    end

    if anyKnown then return anyMatch end

    -- Not a bare race/class list either -- try it as a general boolean expression
    -- (and/or/not/parens/comparisons/itemcount/haveq/completedq/readyq/level).
    local chunk = CompileExpression(text)
    if chunk and not IsIndoors and string.find(text, "IsIndoors", 1, true) then
        -- Neither client has IsIndoors, which the guides call as _G.IsIndoors() (e.g.
        -- 'subzone("Echo Ridge Mine") and _G.IsIndoors()'). The condition is evaluated as if
        -- indoors and as if outdoors: when both agree, that is the answer; otherwise it is
        -- unknown and the fallback applies, without a warning.
        local okIn, resultIn = RunExpression(chunk, true)
        local okOut, resultOut = RunExpression(chunk, false)
        if okIn and okOut then
            if resultIn == resultOut then return resultIn end
            return fallback
        end
    elseif chunk then
        local ok, result = RunExpression(chunk)
        if ok then return result end
    end

    ReportUnknownCondition(text)
    return fallback
end
Parser.EvaluateCondition = EvaluateCondition

function Parser:ParseEntry(guide)
    local text = guide.rawdata
    if not text then return nil, "No text!" end

    guide.steps = {}

    local step
    local prevlevel = 0
    local prevmap, prevmapname
    local linecount = 0

    local open_stickies = {}
    local open_stickies_ord = {}
    local used_stickies = {}

    local autolabels = 0
    local autolabel
    local function get_next_autolabel()
        autolabels = autolabels + 1
        autolabel = string.format("label%03d", autolabels)
        return autolabel
    end
    local function use_autolabel()
        local a = autolabel
        autolabel = nil
        return a
    end

    local function close_sticky(label)
        open_stickies[label] = nil
        for i = table.getn(open_stickies_ord), 1, -1 do
            if open_stickies_ord[i] == label then
                tremove(open_stickies_ord, i)
            end
        end
    end

    local function open_sticky(label)
        open_stickies[label] = true
        used_stickies[label] = true
        tinsert(open_stickies_ord, label)
    end

    local function assign_label_from(params)
        local label = string.gsub(params, "^\"(.-)\"$", "%1")
        if label == "" then return end
        step.label = label
        autolabel = label
        if open_stickies[label] then close_sticky(label) end
        step.is_sticky = used_stickies[label]
    end

    -- Pure modifiers (|tip, |n, |c, |opt, ...) often land on their own line, with no
    -- action of their own on that same line (real guide data: "talk NPC##id" on one line,
    -- "|tip some note." on the next) -- goal is nil for that line, so the modifier has to
    -- apply to the *previous* line's goal (the last one already committed to step.goals)
    -- instead. Without this, such modifiers would silently do nothing.
    local function ModifierTarget(goal)
        if goal then return goal end
        if step and step.goals then return step.goals[table.getn(step.goals)] end
    end

    text = text .. "\n"
    local index = 1

    while index < string.len(text) do
        local st, en, line = string.find(text, "%s*(.-)%s*\n", index)
        if not en then break end
        index = en + 1
        linecount = linecount + 1

        line = string.gsub(line, "%s*%-%-.*", "", 1)
        line = string.gsub(line, "%s*//.*", "", 1)

        if line ~= "" then
            local goal

            line = line .. "|"
            for chunk in string.gmatch(line, "%s*(.-)%s*|+") do
                if string.len(chunk) > 0 then
                    -- A leading "'" is a command of its own: "'text" is the goal text "text", and a
                    -- bare "'" gives a goal with empty text, which is not displayed.
                    chunk = string.gsub(chunk, "^'%s*", "' ")
                    local cmd, params = string.match(chunk, "^([^%s]*)%s*(.-)$")
                    params = params or ""

                    if cmd == "step" then
                        step = {
                            goals = {},
                            level = prevlevel,
                            num = table.getn(guide.steps) + 1,
                            parentGuide = guide,
                        }
                        setmetatable(step, ZGV.StepProto_mt)
                        tinsert(guide.steps, step)

                        assign_label_from(params)

                        if next(open_stickies) then
                            step.sticky_labels = {}
                            for i, stickylabel in ipairs(open_stickies_ord) do
                                if stickylabel ~= step.label then
                                    tinsert(step.sticky_labels, stickylabel)
                                end
                            end
                        end

                    elseif step then
                        if cmd == "label" then
                            assign_label_from(params)

                        elseif cmd == "title" then
                            step.title = params

                        elseif cmd == "travelfor" then
                            step.travelfor = tonumber(params)

                        elseif cmd == "template" then
                            step.template = params

                        elseif cmd == "path" then
                            -- A patrol route the arrow follows point by point (ZGV:FollowPath in
                            -- Pointer.lua). A line holds options ("follow smart; loop; dist 40",
                            -- "loop off") or coordinates separated by tabs, semicolons or double
                            -- spaces, and a step may have several of both. Defaults, options and
                            -- per-point dist follow ZygorGuidesViewerClassic's parser.
                            local waypath = step.waypath
                            if not waypath then
                                waypath = { follow = "loose", loop = true, coords = {} }
                                step.waypath = waypath
                            end
                            local list = string.gsub(params, "^%+%s*", "")
                            list = string.gsub(list, "%s*[\t;]+%s*", ";")
                            list = string.gsub(list, "  +", ";") .. ";"
                            for token in string.gmatch(list, "(.-);") do
                                if token ~= "" then
                                    local mapid, x, y, mapname, dist = ParseZoneXY(token, prevmap, prevmapname)
                                    if mapid then
                                        tinsert(waypath.coords, { map = mapid, mapname = mapname, x = x, y = y,
                                            dist = dist or waypath.dist })
                                        prevmap, prevmapname = mapid, mapname
                                    else
                                        local var, val = string.match(token, "^(%S+)%s+(.+)$")
                                        if not val then var, val = token, 1 end
                                        if val == "off" then val = false end
                                        waypath[var] = tonumber(val) or val
                                        if waypath.radius then waypath.dist = waypath.radius end
                                    end
                                end
                            end

                        elseif cmd == "map" then
                            local mapid = ZGV.ZoneIDs[params]
                            if mapid then
                                step.map = mapid
                                prevmap, prevmapname = mapid, params
                            end

                        elseif cmd == "goto" or cmd == "at" then
                            if not goal then goal = {} end
                            goal.action = goal.action or cmd
                            local mapid, x, y, mapname, dist = ParseZoneXY(params, prevmap, prevmapname)
                            if mapid then
                                goal.map, goal.x, goal.y, goal.mapname, goal.dist = mapid, x, y, mapname, dist
                                prevmap, prevmapname = mapid, mapname
                            end

                        elseif cmd == "stickystart" then
                            local label = string.gsub(params, "^%s*\"(.-)\"%s*$", "%1")
                            if label == "" then label = get_next_autolabel() end
                            autolabel = label
                            open_sticky(label)

                        elseif cmd == "stickystop" then
                            local label = string.gsub(params, "^%s*\"(.-)\"%s*$", "%1")
                            if label == "" then label = use_autolabel() end
                            autolabel = nil
                            if not label then
                                return nil, "stickystop without a label, and none given implicitly (need a stickystart before)", linecount, line
                            end
                            if not open_stickies[label] then
                                return nil, "stickystop with no matching stickystart", linecount, line
                            end
                            close_sticky(label)

                        elseif cmd == "sticky" and not (goal and goal.action) then
                            if not step.label and autolabel then step.label = use_autolabel() end
                            if not step.label then step.label = get_next_autolabel() end
                            autolabel = step.label

                            if not step.is_sticky then
                                step.is_sticky = true
                                if open_stickies[step.label] then
                                    close_sticky(step.label)
                                else
                                    open_sticky(step.label)
                                end
                            end

                            if params == "only" then step.is_sticky_only = true end

                        elseif cmd == "sticky" then
                            -- Goal-level |sticky (force_sticky): parsed, but nothing acts
                            -- on it.
                            local target = ModifierTarget(goal)
                            if target then target.force_sticky = true end

                        elseif cmd == "notinsticky" then
                            local target = ModifierTarget(goal)
                            if target then target.notinsticky = true end

                        elseif cmd == "stickyif" then
                            -- The sticky step shows only while the condition holds (see
                            -- Step:CanBeSticky).
                            step.condition_sticky_raw = params
                            step.condition_sticky = function() return EvaluateCondition(params) end

                        elseif cmd == "ZGV.DevStart()" or cmd == "ZGV.DevEnd()" then
                            -- Development-section markers of the guide data, not goals.

                        elseif cmd == "only" or cmd == "if" then
                            local cond = (cmd == "if") and params or string.match(params, "^if%s+(.*)$")

                            if cond then
                                -- "|only if <condition>" / "|if <condition>": stored as a
                                -- live-evaluated function (matching the reference's
                                -- condition_visible), re-checked every time visibility is
                                -- checked -- not baked in once at parse time, since quest
                                -- state and level change during a session.
                                --
                                -- Unlike |tip/|n/|c/etc., this does NOT fall back to the
                                -- last-committed goal (ModifierTarget) when it's on its own
                                -- line -- a standalone |only if/|if gates the WHOLE STEP
                                -- (real guide data uses this for e.g. a class-specific
                                -- optional step), matching the bare-list form's step.hidden
                                -- fallback right below. Only when it's chunk-attached to a
                                -- goal on the SAME line (goal already set from an earlier
                                -- chunk this line) does it gate just that one goal.
                                if goal then
                                    goal.condition_visible_raw = cond
                                    goal.condition_visible = function() return EvaluateCondition(cond) end
                                else
                                    step.condition_visible_raw = cond
                                    step.condition_visible = function() return EvaluateCondition(cond) end
                                end
                            else
                                -- "|only <race/class list>" (no "if"): race/class doesn't
                                -- change mid-session, so -- matching the reference -- this
                                -- is evaluated immediately, and a mismatch drops the goal
                                -- entirely (not just hides it). Only applies to a goal
                                -- being built on *this* line; with no goal at all yet, it
                                -- gates the whole step instead.
                                if not EvaluateCondition(params) then
                                    if goal then
                                        goal = nil
                                        break
                                    else
                                        step.hidden = true
                                    end
                                end
                            end

                        elseif cmd == "complete" or cmd == "condition" then
                            -- "|complete <expression>": the goal completes while the
                            -- expression is true (see Goal:IsComplete), as in the reference.
                            if not goal then goal = {} end
                            goal.action = goal.action or "complete"
                            goal.condition_complete_raw = params
                            goal.condition_complete = function() return EvaluateCondition(params, false) end

                        elseif cmd == "n" then
                            local target = ModifierTarget(goal)
                            if target then target.force_nocomplete = true end

                        elseif cmd == "noway" then
                            -- The goal's coordinates never become a waypoint, and its row
                            -- is not clickable.
                            local target = ModifierTarget(goal)
                            if target then target.force_noway = true end

                        elseif cmd == "notravel" then
                            -- The arrow points straight at the goal, without a travel route.
                            local target = ModifierTarget(goal)
                            if target then target.waypoint_notravel = true end

                        elseif cmd == "count" then
                            -- "kill 12 Fen Creeper##1040 |q 275/1 |count 6": the objective count
                            -- at which this goal is complete (see GOALTYPES['q']).
                            local target = ModifierTarget(goal)
                            if target and tonumber(params) then target.count = tonumber(params) end

                        elseif cmd == "c" then
                            local target = ModifierTarget(goal)
                            if target then target.force_complete = true end

                        elseif cmd == "opt" then
                            local target = ModifierTarget(goal)
                            if target then target.optional = true end

                        elseif cmd == "future" then
                            local target = ModifierTarget(goal)
                            if target then target.future = true end

                        elseif cmd == "tip" then
                            -- A goal can have several |tip lines in a row (real guide data
                            -- does this a lot) -- append, don't overwrite, so only the last
                            -- one wasn't lost.
                            local target = ModifierTarget(goal)
                            if target then
                                local tip = HighlightText(params)
                                target.tip = target.tip and (target.tip.."\n"..tip) or tip
                            end

                        elseif cmd == "walk" or cmd == "zombiewalk" then
                            -- Travel-mode hints (no mount/flight, or "only while dead") --
                            -- stored, not acted on (no travel/movement simulation here).
                            local target = ModifierTarget(goal)
                            if target then target[cmd] = true end

                        elseif cmd == "next" then
                            -- A jump target once this goal is done: a label, a step number,
                            -- "+N"/"-N", or "Guide\\Title::label" (see Step:GetJumpDestination).
                            local target = ModifierTarget(goal)
                            if target then
                                local jump = string.gsub(params, "^\"(.-)\"$", "%1")
                                if jump == "" then jump = "+1" end
                                target.next = jump
                            end

                        elseif cmd == "or" then
                            -- OR-logic goal group, evaluated by Step:IsComplete.
                            local target = ModifierTarget(goal)
                            if target then target.orlogic = tonumber(params) or 1 end

                        elseif cmd == "instant" then
                            local target = ModifierTarget(goal)
                            if target then target.usetitle = true end

                        elseif cmd == "repeatable" then
                            local target = ModifierTarget(goal)
                            if target then target.repeatablequest = true end

                        elseif cmd == "noautoaccept" then
                            -- Escort/event quests the player must start by hand: quest
                            -- automation leaves this accept goal alone.
                            local target = ModifierTarget(goal)
                            if target then target.noautoaccept = true end

                        elseif GOALTYPES[cmd] and GOALTYPES[cmd].parse then
                            if not goal then goal = {} end
                            goal.action = goal.action or cmd
                            local err = GOALTYPES[cmd].parse(goal, params, step)
                            if type(err) == "string" then
                                return nil, err, linecount, line
                            end

                        else
                            -- Free-form goal text, as in ZygorGuidesViewerClassic. Every
                            -- "[x,y]" / "[ZoneName x,y]" in it stays in the text as highlighted
                            -- coordinates ("[-x,y]" is dropped from the text) and becomes one of
                            -- the goal's locations: the first one is the goal's own map/x/y, the
                            -- others only map markers (goal.ways). A line that is nothing but
                            -- "[x,y]" is such a goal too, showing just the coordinates.
                            if not goal then goal = {} end
                            local text = (cmd == "'") and params or chunk
                            local ways = {}
                            local waymap, waymapname = prevmap, prevmapname
                            if goal.map then waymap, waymapname = goal.map, goal.mapname end
                            text = string.gsub(text, "%[(.-)%]", function(s)
                                local inner = s
                                local hide = string.sub(inner, 1, 1) == "-"
                                if hide then inner = string.sub(inner, 2) end
                                local mapid, x, y, mapname, dist = ParseZoneXY(inner, waymap, waymapname)
                                if not mapid then return "["..s.."]" end
                                tinsert(ways, { map = mapid, mapname = mapname, x = x, y = y, dist = dist })
                                waymap, waymapname = mapid, mapname
                                if hide then return "" end
                                return COORDS_COLOR..math.floor(x * 100)..","..math.floor(y * 100).."|r"
                            end)
                            if ways[1] then
                                goal.map, goal.mapname = ways[1].map, ways[1].mapname
                                goal.x, goal.y, goal.dist = ways[1].x, ways[1].y, ways[1].dist
                                goal.ways = ways
                                goal.force_nocomplete = true
                            end
                            text = HighlightText(text)
                            if text == "_" then text = " " end
                            if goal.text then
                                goal.text = goal.text .. "\n" .. text
                            else
                                goal.text = text
                            end
                        end
                    end
                end
            end

            if goal and next(goal) then
                if not step then
                    return nil, "Goal data before the first 'step' line", linecount, line
                end

                setmetatable(goal, ZGV.GoalProto_mt)
                goal.parentStep = step
                goal.num = table.getn(step.goals) + 1
                tinsert(step.goals, goal)

                if not goal.action and goal.text then
                    goal.action = "text"
                end
            end
        end
    end

    guide.parsed = true
    guide.fully_parsed = true

    return true
end
