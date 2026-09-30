-- The quest reward pick for QuestAutoAccept.lua, scored like the Gear Advisor.

local ItemScore = ZGV.ItemScore
local ItemIDFromLink = ItemScore.ItemIDFromLink
local QuestItem = {}
ItemScore.QuestItem = QuestItem

-- Vendor sell price in copper, for the reward auto-pick below to fall back to
-- "grab the most expensive one" when no reward choice is a real stat upgrade. Vanilla's
-- GetItemInfo has no sell-price field, so there the price comes from LibItemPrice-1.1's
-- offline vendor database. The non-vanilla branch assumes Wrath's 11-field signature and
-- is unverified.
function ZGV:GetItemSellPrice(itemlink)
    local itemid = ItemIDFromLink(itemlink)
    if not itemid then return 0 end

    if not ZGV.IsVanilla then
        local _, _, _, _, _, _, _, _, _, _, sellprice = GetItemInfo(itemid)
        if sellprice then return sellprice end
    end

    local LIP = LibStub("ItemPrice-1.1", true)
    return LIP and LIP:GetPriceById(itemid) or 0
end

-- Picks the reward index to hand to GetQuestReward when there's a real choice (2+ options).
-- Reuses Item-ItemScore.lua's scoring wholesale -- same stat weights, same tooltip scan -- so
-- reward picks are consistent with what the Gear Advisor would itself suggest equipping.
--
-- Only usable items (per the tooltip red-text check the Gear Advisor scan does) compete for
-- the stat-upgrade pick -- an unusable item (wrong class/type) can still score above zero
-- purely because the stat weight table doesn't know it's unwearable, so it must be excluded
-- rather than just outscored. If nothing usable is a real upgrade (every candidate scores
-- 0, or nothing scanned as usable at all), fall back to whichever choice sells for the most
-- (ZGV:GetItemSellPrice above) instead of blindly keeping index 1 -- picking
-- *something* of value beats picking nothing at random.
local function PickBestRewardIndex(numChoices)
    local _, class = UnitClass("player")
    local bestIndex, bestScore = 1, 0
    local bestPriceIndex, bestPrice = 1, -1

    for i = 1, numChoices do
        local link = GetQuestItemLink("choice", i)
        local scan = link and ZGV:ScanQuestChoice(i)

        if scan and scan.usable then
            local score = ZGV:GetItemScore(scan.stats, class)
            if score > bestScore then
                bestIndex, bestScore = i, score
            end
        end

        local price = link and ZGV:GetItemSellPrice(link) or 0
        if price > bestPrice then
            bestPriceIndex, bestPrice = i, price
        end
    end

    if bestScore > 0 then
        return bestIndex
    end
    return bestPriceIndex
end

-- Small "this one" marker for the reward-choice screen, shown only while reward auto-pick
-- is in "manual" mode (autoCompleteRewardChoice) -- lets the algorithm's pick be checked by
-- eye against a real reward screen without it silently auto-clicking anything, which is
-- the whole point while its scoring is still being verified in-game.
--
-- QuestRewardItem1..6 are the real vanilla FrameXML button names for the reward panel's
-- item slots (confirmed against pfUI's own skin code, skins/blizzard/gossipquest.lua, which
-- reads button.type=="choice" on this exact button family against a real 1.12 client) --
-- both choosable and guaranteed reward items share this one button family, with choosable
-- ("choice") items filling the first slots. Not independently re-verified in-game from this
-- project; if the marker lands on the wrong item, that slot-ordering assumption is the first
-- thing to check.
local rewardHighlight

local function GetRewardHighlight()
    if not rewardHighlight then
        rewardHighlight = CreateFrame("Frame", nil, UIParent)
        rewardHighlight:SetWidth(16)
        rewardHighlight:SetHeight(16)
        local tex = rewardHighlight:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(rewardHighlight)
        tex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        rewardHighlight:Hide()
    end
    return rewardHighlight
end

local function ShowRewardHighlight(choiceIndex)
    local button = _G["QuestRewardItem" .. choiceIndex]
    if not button then return end
    local highlight = GetRewardHighlight()
    highlight:SetParent(button)
    highlight:SetFrameLevel(button:GetFrameLevel() + 5)
    highlight:ClearAllPoints()
    highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, 2)
    highlight:Show()
end

local function ClearRewardHighlight()
    if rewardHighlight then rewardHighlight:Hide() end
end

QuestItem.PickBestRewardIndex = PickBestRewardIndex
QuestItem.ShowRewardHighlight = ShowRewardHighlight
QuestItem.ClearRewardHighlight = ClearRewardHighlight
