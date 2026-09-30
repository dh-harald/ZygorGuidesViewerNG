-- General helpers.

-- Referenced by Guide.lua's DoCond (startlevel/endlevel checks) and Parser.lua's level
-- condition, but never actually defined until now -- a pre-existing gap, not new scope.
-- "Precise" = integer level + current XP-bar fraction, for smooth progress display.
function ZGV:GetPlayerPreciseLevel()
    local level = UnitLevel("player")
    if not level or level >= (ZGV.maxlevel or 60) then return level end
    local xp, xpmax = UnitXP("player"), UnitXPMax("player")
    if not xpmax or xpmax == 0 then return level end
    return level + (xp / xpmax)
end

function ZGV.FormatLevel(level)
    return tostring(math.floor(level))
end

-- The retail/Wrath GetItemCount API doesn't exist on 1.12.1 -- bags have to be scanned by
-- hand via GetContainerNumSlots/GetContainerItemLink/GetContainerItemInfo (all plain
-- vanilla API). Bags 0-4 only (backpack + the 4 external bag slots vanilla has); doesn't
-- count the bank, matching the "am I currently carrying N of these" intent of collect/
-- trash goals and the itemcount() condition function.
function ZGV:GetItemCount(itemID)
    itemID = tonumber(itemID)
    if not itemID then return 0 end

    local total = 0
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, (slots or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local linkID = tonumber(string.match(link, "item:(%d+)"))
                if linkID == itemID then
                    local _, count = GetContainerItemInfo(bag, slot)
                    total = total + (count or 1)
                end
            end
        end
    end
    return total
end
