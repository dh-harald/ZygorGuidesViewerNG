-- Drives the gossip/quest dialog once the player has already opened it manually (no
-- simulated targeting/movement -- there's no vanilla API for that anyway) for whichever
-- quest(s) the CURRENT guide step is asking to accept or turn in. Deliberately scoped to
-- the current step only: a chatty NPC's other, unrelated quests are left alone.
--
-- goal.quest (the literal DSL title string, always set alongside goal.questid for accept/
-- turnin -- see Goal.lua's ParseID) is compared directly against whatever title the gossip/
-- greeting/quest-frame API hands back. Both sides are the same representation, so unlike
-- QuestTracking.lua's log-scanning (which has to resolve a title back to an ID with no ID
-- given), no lookup/disambiguation is needed here -- we already know exactly which title
-- we're looking for from the guide itself.

local QuestItem = ZGV.ItemScore.QuestItem

local function FindStepGoal(action, title)
    if not ZGV.CurrentStep or not title then return nil end
    for _, goal in ipairs(ZGV.CurrentStep.goals) do
        if goal.action == action and goal.quest == title then return goal end
    end
    return nil
end

local function TryAutoAccept(title, selectFunc, index)
    if not ZGV.db.profile.autoAcceptQuests then return end
    local goal = FindStepGoal("accept", title)
    if not goal or goal.noautoaccept then return end
    selectFunc(index)
end

local function TryAutoTurnin(title, selectFunc, index)
    if not ZGV.db.profile.autoCompleteQuests then return end
    if not FindStepGoal("turnin", title) then return end
    selectFunc(index)
end

-- Registered via AceEvent (already embedded in ZGV) rather than a raw CreateFrame+
-- RegisterEvent+OnEvent frame: on the 1.12.1 client, OnEvent handlers don't receive the
-- event name as a real function parameter -- "event"/"arg1".."arg9" are globals the engine
-- sets right before the call (confirmed against pfQuest's own OnEvent handlers, which read
-- those globals directly, not function parameters). A shared `function(self, event) ... end`
-- callback branching on an `event` parameter -- the modern/retail convention -- would
-- silently never match anything on this client (this is exactly what broke in testing: every
-- branch compared against a parameter that was always nil). One dedicated method per event
-- name sidesteps the question entirely: AceEvent's own internal dispatch frame deals with
-- the vanilla-vs-modern argument quirk once, and it's unambiguous which event fired since
-- each is bound to its own method -- no branching, no global reads needed here.

function ZGV:OnQuestAutoGossipShow()
    if not ZGV.db then return end

    local available = { GetGossipAvailableQuests() }
    -- Vanilla returns a flat list, title first per entry.
    for i = 1, table.getn(available), 2 do
        TryAutoAccept(available[i], SelectGossipAvailableQuest, math.ceil(i / 2))
    end

    local active = { GetGossipActiveQuests() }
    for i = 1, table.getn(active), 2 do
        TryAutoTurnin(active[i], SelectGossipActiveQuest, math.ceil(i / 2))
    end
end

function ZGV:OnQuestAutoGreeting()
    if not ZGV.db then return end

    for i = 1, (GetNumAvailableQuests() or 0) do
        TryAutoAccept(GetAvailableTitle(i), SelectAvailableQuest, i)
    end
    for i = 1, (GetNumActiveQuests() or 0) do
        TryAutoTurnin(GetActiveTitle(i), SelectActiveQuest, i)
    end
end

-- Reachable directly (bypassing GOSSIP_SHOW/QUEST_GREETING) for NPCs offering only a
-- single quest.
function ZGV:OnQuestAutoDetail()
    if not ZGV.db then return end
    if not ZGV.db.profile.autoAcceptQuests then return end
    local goal = FindStepGoal("accept", GetTitleText())
    if goal and not goal.noautoaccept then
        AcceptQuest()
    end
end

function ZGV:OnQuestAutoProgress()
    if not ZGV.db then return end
    if ZGV.db.profile.autoCompleteQuests and FindStepGoal("turnin", GetTitleText()) and IsQuestCompletable() then
        CompleteQuest()
    end
end

function ZGV:OnQuestAutoComplete()
    if not ZGV.db then return end
    QuestItem.ClearRewardHighlight()

    local numChoices = GetNumQuestChoices() or 0

    if numChoices > 1 and ZGV.db.profile.autoCompleteRewardChoice ~= "best" then
        QuestItem.ShowRewardHighlight(QuestItem.PickBestRewardIndex(numChoices))
    end

    if not ZGV.db.profile.autoCompleteQuests then return end
    if not FindStepGoal("turnin", GetTitleText()) then return end

    if numChoices <= 1 then
        GetQuestReward(numChoices)
    elseif ZGV.db.profile.autoCompleteRewardChoice == "best" then
        GetQuestReward(QuestItem.PickBestRewardIndex(numChoices))
    end
    -- "manual" mode: leave the reward screen open, do nothing (highlight above already shown).
end

ZGV:RegisterEvent("GOSSIP_SHOW", "OnQuestAutoGossipShow")
ZGV:RegisterEvent("QUEST_GREETING", "OnQuestAutoGreeting")
ZGV:RegisterEvent("QUEST_DETAIL", "OnQuestAutoDetail")
ZGV:RegisterEvent("QUEST_PROGRESS", "OnQuestAutoProgress")
ZGV:RegisterEvent("QUEST_COMPLETE", "OnQuestAutoComplete")
