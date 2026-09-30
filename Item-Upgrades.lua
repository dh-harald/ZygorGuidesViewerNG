-- Suggests equipping a newly-acquired bag item when it's both usable and a stat upgrade
-- over whatever's currently in that slot, scanned and scored by Item-ItemScore.lua.

local Gratuity = LibStub("LibGratuity-2.0")
local ItemBonus = LibStub("LibItemBonusLib-1.0")

local ItemScore = ZGV.ItemScore
local ItemIDFromLink = ItemScore.ItemIDFromLink
local EquippedLink = ItemScore.EquippedLink
local IsTwoHanderEquipped = ItemScore.IsTwoHanderEquipped
local DumpLoadedTooltip = ItemScore.DumpLoadedTooltip

-- Presence-tracked (not slot-tracked), so moving/stacking existing items around the bags
-- never re-triggers a check -- only a link that wasn't anywhere in the bags last scan does.
-- Keyed by the full link, so different random-suffix rolls of the same base item are
-- distinct. Declared up here so CheckItemForUpgrade can evict a link that never resolved.
local bagSnapshot = {}

function ZGV:DeclineGearUpgrade(slot, itemlink, equippedlink)
    ZGV.db.char.geardeclined[slot] = ZGV.db.char.geardeclined[slot] or {}
    ZGV.db.char.geardeclined[slot][itemlink] = equippedlink or false
end

function ZGV:EquipGearAdvisorItem(bagnum, bagslot)
    UseContainerItem(bagnum, bagslot)
end

local function StatName(key)
    if key == "DPS" then return "DPS" end
    if key == "ARMOR" then return ARMOR or "Armor" end
    return ItemBonus:GetBonusFriendlyName(key)
end

local function BuildDiffText(newstats, oldstats)
    local keys, seen = {}, {}
    for k in pairs(newstats or {}) do
        if not seen[k] then seen[k] = true; tinsert(keys, k) end
    end
    for k in pairs(oldstats or {}) do
        if not seen[k] then seen[k] = true; tinsert(keys, k) end
    end
    table.sort(keys)

    local lines = {}
    for _, k in ipairs(keys) do
        local delta = (newstats[k] or 0) - (oldstats and oldstats[k] or 0)
        -- Whole-number stats without a decimal; DPS (and any fractional delta) with one.
        local fmt = (k ~= "DPS" and delta == math.floor(delta)) and "%+d" or "%+.1f"
        local value = string.format(fmt, delta)
        if delta > 0 then
            tinsert(lines, "|cff00ff00" .. value .. " " .. StatName(k) .. "|r")
        elseif delta < 0 then
            tinsert(lines, "|cffff0000" .. value .. " " .. StatName(k) .. "|r")
        end
    end

    if table.getn(lines) == 0 then return "No stat change" end
    return table.concat(lines, "\n")
end

-- "[Name]" in the link's own quality color; a plain name when the link carries no color.
local function ColoredName(link, name)
    local color = string.match(link or "", "^(|c%x%x%x%x%x%x%x%x)")
    if color then return color .. "[" .. name .. "]|r" end
    return "[" .. name .. "]"
end

-- The popup is a Blizzard StaticPopup, which UI replacements (ElvUI, pfUI) skin on their own.
-- A suggestion arriving while one is up is queued rather than replacing it -- right after
-- login every item in the bags looks new, and several can qualify in the same pass.
-- Visibility is tracked in popupVisible, set at our own show/hide points.
local pendingSuggestions = {}
local popupVisible = false
local ShowNextSuggestion

-- Shows the real item tooltip for an icon: from the item's bag or inventory slot when that
-- slot still holds the same link, from the link otherwise.
local function ShowIconTooltip(icon)
    local s = icon.suggestion
    if not s then return end
    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
    local ok
    if icon.isNew and GetContainerItemLink(s.bagnum, s.bagslot) == s.newlink then
        ok = pcall(GameTooltip.SetBagItem, GameTooltip, s.bagnum, s.bagslot)
    elseif not icon.isNew and EquippedLink(s.slot) == s.equippedlink then
        ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", s.slot)
    end
    if not ok then
        local link = icon.isNew and s.newlink or s.equippedlink
        local itemid = ItemIDFromLink(link)
        if not itemid then return end
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            and not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. itemid .. ":0:0:0") then
            return
        end
    end
    GameTooltip:Show()
end

local function CreateIcon(name)
    local icon = CreateFrame("Button", name, UIParent)
    icon:SetWidth(32)
    icon:SetHeight(32)
    icon:Hide()
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    icon:SetScript("OnEnter", function() ShowIconTooltip(this) end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return icon
end

local oldIcon, newIcon

-- The text starts with blank lines that reserve the space the two icons sit in.
local function AttachIcons(dialog, s)
    if not oldIcon then
        oldIcon = CreateIcon("ZGVGearAdvisorOldIcon")
        newIcon = CreateIcon("ZGVGearAdvisorNewIcon")
        newIcon.isNew = true
    end
    local icons = { oldIcon, newIcon }
    local textures = { s.equippedscan and s.equippedscan.texture, s.newscan.texture }
    local offsets = { -28, 28 }
    for i = 1, 2 do
        local icon = icons[i]
        icon.suggestion = s
        icon:SetParent(dialog)
        icon:SetFrameStrata(dialog:GetFrameStrata())
        icon:SetFrameLevel(dialog:GetFrameLevel() + 2)
        icon:ClearAllPoints()
        icon:SetPoint("TOP", dialog, "TOP", offsets[i], -16)
        icon.texture:SetTexture(textures[i] or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        icon:Show()
    end
end

local function DetachIcons()
    if not oldIcon then return end
    oldIcon:Hide()
    newIcon:Hide()
    oldIcon.suggestion, newIcon.suggestion = nil, nil
end

local function SuggestionText(s)
    local oldName = s.equippedscan and ColoredName(s.equippedlink, s.equippedscan.name) or "(empty)"
    local newName = ColoredName(s.newlink, s.newscan.name)
    return "\n\n\n|cffffd100Gear Advisor|r\n" .. oldName .. "  >  " .. newName .. "\n\n"
        .. BuildDiffText(s.newscan.stats, s.equippedscan and s.equippedscan.stats)
end

-- No hideOnEscape: the escape path calls OnCancel just like the Ignore button, and closing
-- the popup must not count as declining. OnCancel's "override"/"timeout" reasons are not
-- a player's choice either.
StaticPopupDialogs["ZGV_GEAR_UPGRADE"] = {
    text = "%s",
    button1 = "Equip",
    button2 = "Ignore",
    timeout = 0,
    whileDead = 1,
    OnAccept = function(s)
        if s then ZGV:EquipGearAdvisorItem(s.bagnum, s.bagslot) end
    end,
    OnCancel = function(s, reason)
        if s and reason == "clicked" then ZGV:DeclineGearUpgrade(s.slot, s.newlink, s.equippedlink) end
    end,
    OnHide = function()
        DetachIcons()
        popupVisible = false
        -- Deferred so the next StaticPopup_Show doesn't run inside this dialog's own OnHide.
        if table.getn(pendingSuggestions) > 0 then
            ZGV:ScheduleTimer(function() ShowNextSuggestion() end, 0.1)
        end
    end,
}

ShowNextSuggestion = function()
    if popupVisible then return end
    local s = table.remove(pendingSuggestions, 1)
    if not s then return end

    local dialog = StaticPopup_Show("ZGV_GEAR_UPGRADE", SuggestionText(s))
    if not dialog then
        -- All four StaticPopup frames are taken; retry once one frees up.
        table.insert(pendingSuggestions, 1, s)
        ZGV:ScheduleTimer(function() ShowNextSuggestion() end, 2)
        return
    end
    dialog.data = s
    AttachIcons(dialog, s)
    popupVisible = true
end

function ZGV:ShowGearAdvisorPopup(newscan, equippedscan, slot, newlink, equippedlink, bagnum, bagslot)
    table.insert(pendingSuggestions, {
        newscan = newscan, equippedscan = equippedscan, slot = slot,
        newlink = newlink, equippedlink = equippedlink, bagnum = bagnum, bagslot = bagslot,
    })
    ShowNextSuggestion()
end

-- Main decision point: is this item worth suggesting a swap for. Silently does nothing for
-- non-equipment, unusable items (see the tooltip-color check above), non-upgrades, or
-- upgrades already declined for the currently-equipped item in that slot.
function ZGV:CheckItemForUpgrade(itemlink, bagnum, bagslot, retriesLeft)
    if not ZGV.db or not itemlink then return end
    if not ZGV.db.char.gearAdvisorEnabled then return end
    -- The item moved or left the bags before a retry came round.
    if GetContainerItemLink(bagnum, bagslot) ~= itemlink then return end

    local scan = ZGV:ScanBagItem(bagnum, bagslot)
    if not scan then
        -- A brand new item the client has never seen can take a moment to resolve.
        retriesLeft = retriesLeft or 3
        if retriesLeft > 0 then
            ZGV:ScheduleTimer(function()
                ZGV:CheckItemForUpgrade(itemlink, bagnum, bagslot, retriesLeft - 1)
            end, 0.5)
        else
            -- ScanBagsForNewItems already marked this link as known; evict it so the next
            -- bag scan gives it another chance instead of it being skipped for good.
            bagSnapshot[itemlink] = nil
        end
        return
    end
    if not scan.equiploc or scan.equiploc == "" then return end
    if not scan.usable then return end

    local slotdata = ZGV.EquipLocToSlot[scan.equiploc]
    if not slotdata then return end
    -- An off-hand item alone never replaces a two-hander.
    if slotdata == 17 and IsTwoHanderEquipped() then return end

    local _, class = UnitClass("player")
    local weights = ZGV:GetGearWeights(class)
    if not weights then return end

    local newscore = ZGV:GetItemScore(scan.stats, class)

    local slot, equippedlink, equippedscan, equippedscore
    if type(slotdata) == "table" then
        local link1 = EquippedLink(slotdata[1])
        local link2 = EquippedLink(slotdata[2])
        local scan1 = link1 and ZGV:ScanInventoryItem(slotdata[1])
        local scan2 = link2 and ZGV:ScanInventoryItem(slotdata[2])
        local score1 = scan1 and ZGV:GetItemScore(scan1.stats, class) or -1
        local score2 = scan2 and ZGV:GetItemScore(scan2.stats, class) or -1
        if score1 <= score2 then
            slot, equippedlink, equippedscan, equippedscore = slotdata[1], link1, scan1, score1
        else
            slot, equippedlink, equippedscan, equippedscore = slotdata[2], link2, scan2, score2
        end
    else
        slot = slotdata
        equippedlink = EquippedLink(slot)
        equippedscan = equippedlink and ZGV:ScanInventoryItem(slot)
        equippedscore = equippedscan and ZGV:GetItemScore(equippedscan.stats, class) or -1
        -- A two-hander replaces both hands, so it has to beat the main hand and off hand
        -- together; the popup's stat diff is against both of them as well.
        if scan.equiploc == "INVTYPE_2HWEAPON" then
            local offlink = EquippedLink(17)
            local offscan = offlink and ZGV:ScanInventoryItem(17)
            if offscan then
                local offscore = ZGV:GetItemScore(offscan.stats, class)
                equippedscore = (equippedscore > 0 and equippedscore or 0) + offscore
                local combined = {}
                for k, v in pairs(offscan.stats) do combined[k] = v end
                if equippedscan then
                    for k, v in pairs(equippedscan.stats) do combined[k] = (combined[k] or 0) + v end
                    equippedscan = {
                        usable = equippedscan.usable, reason = equippedscan.reason, stats = combined,
                        texture = equippedscan.texture, name = equippedscan.name,
                        equiploc = equippedscan.equiploc,
                    }
                else
                    equippedscan = {
                        usable = offscan.usable, reason = offscan.reason, stats = combined,
                        texture = offscan.texture, name = offscan.name, equiploc = offscan.equiploc,
                    }
                    equippedlink = offlink
                end
            end
        end
    end

    if newscore <= equippedscore then return end

    local declined = ZGV.db.char.geardeclined[slot]
    if declined and declined[itemlink] == (equippedlink or false) then return end

    ZGV:ShowGearAdvisorPopup(scan, equippedscan, slot, itemlink, equippedlink, bagnum, bagslot)
end

-- A level-up or newly trained weapon skill can make an already-owned, previously-red-text
-- bag item usable, so unlike BAG_UPDATE's new-item diff below, this re-checks everything
-- currently carried.
function ZGV:RescanAllBagItems()
    for bag = 0, 4 do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                ZGV:CheckItemForUpgrade(link, bag, slot)
            end
        end
    end
end

local function ScanBagsForNewItems()
    local current = {}
    for bag = 0, 4 do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                current[link] = true
                if not bagSnapshot[link] then
                    ZGV:CheckItemForUpgrade(link, bag, slot)
                end
            end
        end
    end
    bagSnapshot = current
end

-- BAG_UPDATE fires once per affected bag, so a single loot/purchase can trigger it several
-- times in a row -- debounced rather than reacting to every single fire.
local pendingBagScan
local function QueueBagScan()
    if pendingBagScan then ZGV:CancelTimer(pendingBagScan) end
    pendingBagScan = ZGV:ScheduleTimer(function()
        pendingBagScan = nil
        ScanBagsForNewItems()
    end, 0.5)
end

local pendingRescan
local function QueueRescan()
    if pendingRescan then ZGV:CancelTimer(pendingRescan) end
    pendingRescan = ZGV:ScheduleTimer(function()
        pendingRescan = nil
        ZGV:RescanAllBagItems()
    end, 0.5)
end

-- Item-count goals (get/collect/trash) depend on bag contents. Looting an item that is not a
-- quest objective (e.g. a quest-starter item) fires no QUEST_LOG_UPDATE, so the viewer is
-- re-rendered from here, debounced like the gear scan.
local pendingFrameUpdate
local function QueueFrameUpdate()
    if pendingFrameUpdate then ZGV:CancelTimer(pendingFrameUpdate) end
    pendingFrameUpdate = ZGV:ScheduleTimer(function()
        pendingFrameUpdate = nil
        ZGV:UpdateFrame()
    end, 0.5)
end

-- One AceEvent method per event: raw OnEvent handlers get no arguments on 1.12. This is the
-- only BAG_UPDATE handler on ZGV, so it serves both the gear scan and the viewer refresh.
function ZGV:OnGearBagUpdate()
    if not ZGV.db then return end
    QueueBagScan()
    QueueFrameUpdate()
end

-- Also the only PLAYER_LEVEL_UP/SKILL_LINES_CHANGED handler on ZGV: a newly trained weapon
-- skill completes a weaponskill() goal, so the viewer is re-rendered too.
function ZGV:OnGearRescanTrigger()
    if not ZGV.db then return end
    QueueRescan()
    QueueFrameUpdate()
end

ZGV:RegisterEvent("BAG_UPDATE", "OnGearBagUpdate")
ZGV:RegisterEvent("PLAYER_LEVEL_UP", "OnGearRescanTrigger")
ZGV:RegisterEvent("SKILL_LINES_CHANGED", "OnGearRescanTrigger")

-- Manual debug helper: /run ZGV:DebugGearCheck("Nordic Belt") -- finds the item by a
-- substring of its name (in bags or already equipped), dumps its scanned tooltip with every
-- line's color, and walks through every decision CheckItemForUpgrade would make.
function ZGV:DebugGearCheck(namefragment)
    local link, where, scan
    for i = 1, 19 do
        local l = EquippedLink(i)
        if l and string.find(l, namefragment, 1, true) then
            link, where = l, "equipped slot " .. i
            scan = ZGV:ScanInventoryItem(i)
            break
        end
    end
    if not link then
        for b = 0, 4 do
            for s = 1, (GetContainerNumSlots(b) or 0) do
                local l = GetContainerItemLink(b, s)
                if l and string.find(l, namefragment, 1, true) then
                    link, where = l, "bag " .. b .. " slot " .. s
                    scan = ZGV:ScanBagItem(b, s)
                    break
                end
            end
            if link then break end
        end
    end

    if not link then
        print("ZGV debug: no item matching '" .. namefragment .. "' found in bags or equipped.")
        return
    end
    print("ZGV debug: found " .. link .. " at " .. where)

    if not ZGV.db.char.gearAdvisorEnabled then
        print("ZGV debug: gearAdvisorEnabled is FALSE -- nothing will ever trigger until it's re-enabled.")
    end

    print("ZGV debug: tooltip has " .. Gratuity:NumLines() .. " lines")
    DumpLoadedTooltip()

    if not scan then
        print("ZGV debug: scan returned nil -- GetItemInfo(itemid) did not resolve, or the tooltip stayed empty. Try again in a few seconds in case it's first-sight caching delay.")
        return
    end
    print(string.format("ZGV debug: name=%s usable=%s equiploc=%s reason=%s",
        tostring(scan.name), tostring(scan.usable), tostring(scan.equiploc), tostring(scan.reason)))
    for k, v in pairs(scan.stats) do
        print("  stat " .. k .. "=" .. v)
    end

    local slotdata = ZGV.EquipLocToSlot[scan.equiploc]
    if not slotdata then
        print("ZGV debug: equiploc '" .. tostring(scan.equiploc) .. "' has no EquipLocToSlot entry -- not treated as upgradeable gear at all.")
        return
    end
    if slotdata == 17 and IsTwoHanderEquipped() then
        print("ZGV debug: a two-hander is equipped -- off-hand items are never suggested alongside it.")
        return
    end

    local _, class = UnitClass("player")
    local newscore = ZGV:GetItemScore(scan.stats, class)
    print("ZGV debug: class=" .. class .. " newscore=" .. newscore)
    print(string.format("ZGV debug: popupVisible=%s pendingSuggestions=%d",
        tostring(popupVisible), table.getn(pendingSuggestions)))
    if not scan.usable then
        print("ZGV debug: usable is FALSE (red line: " .. tostring(scan.reason) .. ") -- CheckItemForUpgrade stops here.")
    end

    local function reportSlot(slot)
        local equippedlink = EquippedLink(slot)
        local equippedscan = equippedlink and ZGV:ScanInventoryItem(slot)
        local equippedscore = equippedscan and ZGV:GetItemScore(equippedscan.stats, class) or -1
        print(string.format("ZGV debug: slot=%s equipped=%s equippedscore=%s",
            tostring(slot), tostring(equippedlink), tostring(equippedscore)))

        local declined = ZGV.db.char.geardeclined[slot]
        if declined and declined[link] ~= nil then
            print("  declined entry for this exact item:", tostring(declined[link]),
                "(suppresses the popup only if this equals the CURRENT equipped link, or false for an empty slot)")
        end

        if newscore > equippedscore and scan.usable then
            print("  => upgrade for slot " .. tostring(slot) .. ", should have prompted (check gearAdvisorEnabled/decline entry above if it didn't)")
        else
            print("  => NOT an upgrade for slot " .. tostring(slot) .. " (newscore " .. newscore .. ", equippedscore " .. equippedscore .. ", usable " .. tostring(scan.usable) .. ")")
        end
    end

    if type(slotdata) == "table" then
        reportSlot(slotdata[1])
        reportSlot(slotdata[2])
    else
        reportSlot(slotdata)
    end
end
