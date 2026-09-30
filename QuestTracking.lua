-- Vanilla has no IsQuestFlaggedCompleted equivalent: GetQuestLogTitle only tells you
-- what's currently in the log, and a quest simply vanishes from it once turned in.
-- So "was this quest ever completed" has to be inferred by watching the log ourselves
-- and persisting what we saw, per character -- the same approach pfQuest takes on this
-- client.
--
-- The log itself is index-based and exposes no quest ID. GetQuestLink(index) would give
-- one on later clients (a chat-link string with the ID embedded, |Hquest:ID:level|h),
-- but that's confirmed absent on 1.12.1 (tested in-game: GetQuestLink is nil), so we
-- fall back to Data/QuestNames.lua/Data/QuestPrereqs.lua -- a small quest-ID -> title/objective/
-- prerequisite lookup extracted from pfQuest's own vanilla quest database (credit:
-- pfQuest by Shagu, https://github.com/shagu/pfQuest) -- to resolve a log title back to
-- a real quest ID ourselves. Titles alone aren't unique (~11% of quests share one with
-- another quest), so when a title matches more than one quest ID, candidates restricted
-- to another race or class are dropped, then the objective text (read live via
-- GetQuestLogQuestText, same as pfQuest's own disambiguation) is used as a tiebreaker.
-- Candidates that still cannot be told apart are all tracked. If nothing matches, the
-- title itself is used as the key -- rare, but not impossible.

function ZGV:MarkQuestCompleted(questKey)
    if not ZGV.db then return end
    ZGV.db.char.quests[questKey] = {
        time = time(),
        level = UnitLevel("player"),
    }
end

local titleToIDs = {}
if ZGV.QuestNames then
    for id, data in pairs(ZGV.QuestNames) do
        local list = titleToIDs[data.T]
        if not list then
            list = {}
            titleToIDs[data.T] = list
        end
        tinsert(list, id)
    end
end

local function GetObjectiveTextFromLog(index)
    local oldSelection = GetQuestLogSelection()
    SelectQuestLogEntry(index)
    local _, objective = GetQuestLogQuestText()
    SelectQuestLogEntry(oldSelection)
    return objective
end

-- pfQuest's stored objective text is the raw server-side template, which for ~5.6% of all
-- vanilla quests (confirmed by grepping Data/QuestNames.lua) still has unresolved "$"-codes in it
-- ("$b" = line break, "$n"/"$c"/"$r" = player name/class/race, "$g male:female;" = gendered
-- phrasing) -- the live client only ever hands back already-resolved text via
-- GetQuestLogQuestText, so a straight == comparison against the stored template silently
-- fails disambiguation for every quest using one of these, always falling through to the
-- title-string fallback below (confirmed via user testing: quest 753, sharing its title
-- "A Humble Task" with quest 752, never resolved to a numeric ID because of exactly this,
-- via its "$b$b"-containing objective text). Ported from pfQuest's own
-- pfDatabase:FormatQuestText (database.lua) -- it faces this identical problem resolving
-- its own quest database against the live log -- rather than just stripping "$b" and hoping
-- nothing else matters, since 1) that's exactly the kind of thing that bites later once a
-- guide's quest happens to use "$n"/"$c"/"$r"/"$g", and 2) pfQuest has already solved it
-- properly. Whitespace is still collapsed afterward as a small extra safety margin against
-- any other incidental formatting differences.
local function FormatQuestText(text)
    if not text then return text end
    text = string.gsub(text, "%$[Nn]", UnitName("player"))
    text = string.gsub(text, "%$[Cc]", string.lower((UnitClass("player"))))
    text = string.gsub(text, "%$[Rr]", string.lower((UnitRace("player"))))
    text = string.gsub(text, "%$[Bb]", "")
    -- "%G" here refers to whichever capture group index matches UnitSex()'s 2 (male) or 3
    -- (female) -- group 1 is the "$g" marker itself, group 2 the male phrase, group 3 the
    -- female phrase -- same technique pfQuest's own FormatQuestText uses.
    text = string.gsub(text, "(%$[Gg])([^:]+):([^;]+);", "%"..UnitSex("player"))
    text = string.gsub(text, "%s+", "")
    return text
end

-- Race/class bits as used by the R/C masks in Data/QuestNames.lua (pfQuest's bitraces/bitclasses).
local RACE_BITS = {
    Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Tauren = 32, Gnome = 64, Troll = 128,
}
local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128,
    WARLOCK = 256, DRUID = 1024,
}

-- Arithmetic bit test: no bit library is assumed on any client.
local function HasBit(mask, flag)
    return math.floor(mask / flag) - 2 * math.floor(mask / (2 * flag)) == 1
end

-- Faction and race variants of a quest often share title and objective text (the druid
-- "Great Bear Spirit" is 5929 for Night Elves and 5930 for Tauren), so candidates the
-- player could never have taken are dropped first. An unknown race token falls back to
-- the faction's races, an unknown class token skips the class check.
local function IsQuestForPlayer(data)
    if data.R then
        local _, race = UnitRace("player")
        local racebit = RACE_BITS[race or ""]
        if racebit then
            if not HasBit(data.R, racebit) then return false end
        else
            local factionmask = UnitFactionGroup("player") == "Alliance" and 77 or 178
            local shared = false
            for _, racebit in pairs(RACE_BITS) do
                if HasBit(data.R, racebit) and HasBit(factionmask, racebit) then shared = true end
            end
            if not shared then return false end
        end
    end
    if data.C then
        local _, class = UnitClass("player")
        local classbit = CLASS_BITS[class or ""]
        if classbit and not HasBit(data.C, classbit) then return false end
    end
    return true
end

-- Returns every quest key the log entry resolves to. Candidates that stay indistinguishable
-- after the race/class and objective checks are all returned, like pfQuest's GetQuestIDs:
-- they are variants of the same quest ("Heeding the Call" 5926/5927/5928 differ only in who
-- hands it out), so tracking all of them lets a guide step find the one it names.
local function GetQuestIDsFromLog(index, title)
    -- opportunistic: works on later clients, always nil on 1.12.1
    local link = GetQuestLink and GetQuestLink(index)
    local linkID = link and tonumber(string.match(link, "|Hquest:(%d+):"))
    if linkID then return { linkID } end

    local candidates = titleToIDs[title]
    if not candidates then return { title } end

    local eligible = {}
    for _, id in ipairs(candidates) do
        if IsQuestForPlayer(ZGV.QuestNames[id]) then tinsert(eligible, id) end
    end
    if table.getn(eligible) == 0 then eligible = candidates end
    if table.getn(eligible) == 1 then return { eligible[1] } end

    local objective = FormatQuestText(GetObjectiveTextFromLog(index))
    local matches = {}
    for _, id in ipairs(eligible) do
        if FormatQuestText(ZGV.QuestNames[id].O) == objective then
            tinsert(matches, id)
        end
    end
    if table.getn(matches) > 0 then return matches end

    return { title }
end

-- AbandonQuest is the one global the default UI (and any addon) ultimately calls to
-- drop a quest, regardless of which button triggered it. Hooking it here is how we
-- tell "abandoned" apart from "turned in" below, since both just remove the quest
-- from the log.
local pendingAbandonTitle
local OriginalAbandonQuest = AbandonQuest
AbandonQuest = function()
    pendingAbandonTitle = GetAbandonQuestName()
    OriginalAbandonQuest()
end

local questlog_snapshot = {}

-- Live per-objective progress for quests currently in the log (e.g. "3/10 Kobold Vermin
-- slain"), rebuilt on every scan -- this is NOT persisted, unlike ZGV.db.char.quests.
-- Mirrors the retail source's GOALTYPES['q'].iscomplete, which checks quest.goals[objnum]
-- from its own live quest cache; ours is built the same way pfQuest builds its equivalent,
-- via GetNumQuestLeaderBoards/GetQuestLogLeaderBoard (both plain vanilla API, no compat
-- concerns). The vanilla API only gives a "finished" boolean plus free-form text per
-- objective (no separate done/needed counts like retail's GetQuestObjectiveInfo), so the
-- numeric progress is an opportunistic "N/M" parse out of that text -- fine for a progress
-- display, but only "done" should be relied on for actual completion logic.
ZGV.ActiveQuests = {}

local function CaptureQuestObjectives(index)
    local objectives = GetNumQuestLeaderBoards(index)
    if not objectives or objectives == 0 then return nil end

    local goals = {}
    for objnum = 1, objectives do
        local text, _, done = GetQuestLogLeaderBoard(objnum, index)
        local num, needed
        if text then
            num, needed = string.match(text, "(%d+)%s*/%s*(%d+)")
        end
        goals[objnum] = { text = text, done = done, num = tonumber(num), needed = tonumber(needed) }
    end
    return goals
end

function ZGV:ScanQuestLog()
    if not ZGV.db then return end
    if ((ZGV.throttling.QUEST_LOG_UPDATE.tries >= ZGV.throttling.QUEST_LOG_UPDATE.retry) and (ZGV.throttling.QUEST_LOG_UPDATE.tick > GetTime())) then
        -- ZGV.throttling.QUEST_LOG_UPDATE.tries == ZGV.throttling.QUEST_LOG_UPDATE.tries + 1
        return
    else
        ZGV.throttling.QUEST_LOG_UPDATE.tick = GetTime() + ZGV.throttling.QUEST_LOG_UPDATE.delay
        ZGV.throttling.QUEST_LOG_UPDATE.tries = 0
    end

    -- Keyed by resolved quest key (not title): multi-part chains where the next part
    -- reuses the exact same title (e.g. "A Humble Task" I/II, quest 752 then 753) would
    -- otherwise mask each other here. With a title-keyed snapshot, turning in 752 while
    -- immediately being handed same-titled 753 makes current["A Humble Task"] exist again
    -- (now meaning 753), so "not current[title]" for 752's old snapshot entry is false and
    -- MarkQuestCompleted(752) never runs -- confirmed via user testing: 752 turned in, 753
    -- auto-accepted, but 753's own accept-goal never showed complete because nothing ever
    -- recorded 752 as done and ZGV.ActiveQuests/db.char.quests bookkeeping went stale from
    -- there. Keying by the resolved key instead makes 752 and 753 distinct entries even
    -- though they share a title, since disambiguation (see GetQuestIDsFromLog) resolves them
    -- to different numeric IDs.
    local current = {}
    local activeQuests = {}

    for index = 1, 40 do
        local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(index)
        if title and title ~= "" and not isHeader then
            local goals = CaptureQuestObjectives(index)
            for _, questKey in ipairs(GetQuestIDsFromLog(index, title)) do
                current[questKey] = title

                if type(questKey) == "number" then
                    activeQuests[questKey] = {
                        index = index,
                        level = level,
                        goals = goals,
                        -- 1 on 1.12.1, possibly true on Unreal Azeroth; -1 means failed.
                        complete = (isComplete == 1 or isComplete == true),
                    }
                end
            end
        end
    end

    ZGV.ActiveQuests = activeQuests

    -- One log entry can resolve to several keys, so the abandon marker is only cleared
    -- once every key of the abandoned entry has been skipped.
    local abandoned = false
    for questKey, title in pairs(questlog_snapshot) do
        if not current[questKey] then
            if title == pendingAbandonTitle then
                abandoned = true
            else
                ZGV:MarkQuestCompleted(questKey)
            end
        end
    end
    if abandoned then pendingAbandonTitle = nil end

    questlog_snapshot = current

    -- Quest state (accepted/completed/objective progress) just changed -- re-render so the
    -- viewer reflects it immediately (e.g. right after accepting the quest a step asked
    -- for) instead of only updating on the next manual step change. UpdateFrame no-ops
    -- safely if there's no guide loaded.
    if ZGV.UpdateFrame then ZGV:UpdateFrame() end
end

-- Goal-completion checks for a quest-bound goal (self.questid[, self.objnum]) should use
-- this. Returns inLog[, done, num, needed]; "done" is only meaningful when inLog is true.
-- Whether the quest was completed in the past is a separate question -- check
-- ZGV.db.char.quests[questid] for that (see ZGV:MarkQuestCompleted above).
function ZGV:GetQuestObjectiveProgress(questid, objnum)
    local quest = ZGV.ActiveQuests[questid]
    if not quest then return false end

    if not objnum then return true end

    local goal = quest.goals and quest.goals[objnum]
    -- A quest that is ready to turn in has every objective done, including one the client
    -- leaves out of the leaderboard: Unreal Azeroth lists no escort or event objective at all
    -- and only flags the whole quest complete.
    if quest.complete then
        if goal then return true, true, goal.num, goal.needed end
        return true, true
    end
    if not goal then return true, false end

    return true, goal.done, goal.num, goal.needed
end

-- A positive prerequisite ID must have been completed, a negative one must be in the quest log.
local function IsPrereqSatisfied(prereqid)
    if prereqid < 0 then return ZGV.ActiveQuests[-prereqid] ~= nil end
    return ZGV.db.char.quests[prereqid] ~= nil
end

-- Any one alternative satisfies the prerequisite (see the Data/QuestPrereqs.lua header); an
-- alternative that is a table needs all of its quests. No entry means nothing gates this quest.
function ZGV:IsQuestPrereqMet(questid)
    local prereqs = ZGV.QuestPrereqs[questid]
    if not prereqs then return true end
    for _, alt in ipairs(prereqs) do
        if type(alt) == "table" then
            local all = true
            for _, prereqid in ipairs(alt) do
                if not IsPrereqSatisfied(prereqid) then
                    all = false
                    break
                end
            end
            if all then return true end
        elseif IsPrereqSatisfied(alt) then
            return true
        end
    end
    return false
end

-- Optional, server-core-specific: some private server emulators backport a bulk
-- "give me everything this character has ever completed" sync that stock vanilla
-- doesn't have. Reached through "/zygor qqc"; on a server without it this just
-- reports back and does nothing.
function ZGV:QueryCompletedQuests()
    if not QueryQuestsCompleted then
        ZGV:Print("QueryQuestsCompleted is not available on this server.")
        return
    end

    ZGV:RegisterEvent("QUEST_QUERY_COMPLETE", "OnQuestQueryComplete")
    ZGV:Print("Requesting completed quests from server...")
    QueryQuestsCompleted()
end

function ZGV:OnQuestQueryComplete()
    ZGV:UnregisterEvent("QUEST_QUERY_COMPLETE")

    local completed = GetQuestsCompleted()
    if type(completed) ~= "table" then
        ZGV:Print("GetQuestsCompleted() did not return usable data.")
        return
    end

    local count = 0
    for questID in pairs(completed) do
        ZGV:MarkQuestCompleted(questID)
        count = count + 1
    end
    ZGV:Print(string.format("QueryCompletedQuests: recorded %d completed quests.", count))
end

ZGV:RegisterEvent("QUEST_LOG_UPDATE", "ScanQuestLog")
