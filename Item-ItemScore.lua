-- Item scanning and scoring for the Gear Advisor (Item-Upgrades.lua) and the quest reward
-- pick (Item-Quest.lua). The reference addon's Item-ItemScore relies on GetItemStats(), which
-- doesn't exist on 1.12.1 -- so stats come from the item's tooltip instead: LibGratuity-2.0
-- loads it, and LibItemBonusLib-1.0's localized patterns turn each line into bonus totals.
-- Stat weights are in Data/Item-Statweights.lua.
--
-- Usability is checked in the same pass: WoW colors a tooltip line red whenever a
-- requirement (class/level/skill) isn't met, so checking each line's color sidesteps
-- needing a hand-maintained armor/weapon-proficiency-by-level table entirely.

local _G = _G or getfenv()

local Gratuity = LibStub("LibGratuity-2.0")
local ItemBonus = LibStub("LibItemBonusLib-1.0")
local Deformat = LibStub("LibDeformat-2.0")

local ItemScore = {}
ZGV.ItemScore = ItemScore

-- Maps GetItemInfo's itemEquipLoc to the inventory slot number to compare against. Raw slot
-- numbers, not the INVSLOT_* globals, which are nil on this client:
-- 1 head, 2 neck, 3 shoulder, 4 shirt, 5 chest, 6 waist, 7 legs, 8 feet, 9 wrist, 10 hands,
-- 11/12 finger1/2, 13/14 trinket1/2, 15 back, 16 mainhand, 17 offhand, 18 ranged, 19 tabard.
--
-- Rings/trinkets map to both of their slots -- CheckItemForUpgrade picks whichever currently
-- scores lower. Ammo/bags/shirts are intentionally absent (not meaningfully "upgradeable").
-- A one-handed weapon is only ever compared against the main hand, never offered for the
-- off hand.
ZGV.EquipLocToSlot = {
    INVTYPE_HEAD = 1,
    INVTYPE_NECK = 2,
    INVTYPE_SHOULDER = 3,
    INVTYPE_CLOAK = 15,
    INVTYPE_CHEST = 5,
    INVTYPE_ROBE = 5,
    INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8,
    INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10,
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = 16,
    INVTYPE_2HWEAPON = 16,
    INVTYPE_WEAPONMAINHAND = 16,
    INVTYPE_WEAPONOFFHAND = 17,
    INVTYPE_SHIELD = 17,
    INVTYPE_HOLDABLE = 17,
    INVTYPE_RANGED = 18,
    INVTYPE_RANGEDRIGHT = 18,
    INVTYPE_THROWN = 18,
}

-- LibGratuity-2.0's scanning tooltip. Its line FontStrings are read directly, since the
-- red-text check needs their colors, not only their text.
local GRATUITY_TOOLTIP = "LibGratuity20Tooltip"

local function ItemIDFromLink(link)
    return tonumber(string.match(link or "", "item:(%d+)"))
end

-- Unreal Azeroth's GetInventoryItemLink returns "item:0:0:0:0" for an empty slot instead of
-- nil; both mean "nothing equipped".
local function EquippedLink(slot)
    local link = GetInventoryItemLink("player", slot)
    local itemid = ItemIDFromLink(link)
    if not itemid or itemid == 0 then return nil end
    return link
end

local function IsTwoHanderEquipped()
    local itemid = ItemIDFromLink(EquippedLink(16))
    if not itemid then return false end
    local _, _, _, _, _, _, _, equiploc = GetItemInfo(itemid)
    return equiploc == "INVTYPE_2HWEAPON"
end

-- "Any red line on the tooltip means unusable" -- checked two ways, since a line can be
-- colored red either via FontString:SetTextColor() on the whole line, or via an inline
-- |cffRRGGBB...|r color code in the text itself. An armor-type mismatch (e.g. Mail for a
-- Shaman without that proficiency yet) is a SetTextColor-red ~(1, 0.125, 0.125) line on the
-- row's RIGHT FontString, so both sides of every row are checked.
local function IsRedText(fs, text)
    local r, g, b = fs:GetTextColor()
    if r and r > 0.8 and g < 0.3 and b < 0.3 then return true end
    local rhex, ghex, bhex = string.match(text, "|c%x%x(%x%x)(%x%x)(%x%x)")
    if rhex then
        local er, eg, eb = tonumber(rhex, 16), tonumber(ghex, 16), tonumber(bhex, 16)
        return er and eg and eb and er > 200 and eg < 80 and eb < 80
    end
    return false
end

-- Base armor, weapon damage and speed are not LibItemBonusLib bonuses; they are matched
-- against the client's own GlobalStrings, so they read correctly in every locale.
local function ReadBaseLine(stats, text, weapon)
    local armor = ARMOR_TEMPLATE and Deformat(text, ARMOR_TEMPLATE)
    if armor then
        stats.ARMOR = (stats.ARMOR or 0) + armor
        return true
    end
    local lo, hi
    if DAMAGE_TEMPLATE then lo, hi = Deformat(text, DAMAGE_TEMPLATE) end
    if lo and hi then
        weapon.mindmg, weapon.maxdmg = lo, hi
        return true
    end
    if SPEED then
        local spd = string.match(text, "^" .. SPEED .. " ([%d%.,]+)$")
        if spd then
            weapon.speed = tonumber((string.gsub(spd, ",", ".")))
            return true
        end
    end
    return false
end

-- Reads whatever LibGratuity-2.0's tooltip currently holds. Its Erase() clears the right
-- side text of every row, so a non-empty right text belongs to the current item. A cleared
-- row can read back as "" rather than nil and keeps its previous color, so empty text is
-- treated as absent -- otherwise a leftover red color marks the item unusable. Line 1 is the
-- item name; stat parsing stops at the item-set header, whose bonus lines only count with
-- enough pieces on.
local function ReadLoadedTooltip(itemid)
    local name, _, _, _, _, _, _, equiploc, texture = GetItemInfo(itemid)
    if not name then return nil end

    local numLines = Gratuity:NumLines()
    if numLines == 0 then return nil end

    local stats = {}
    local weapon = {}
    local usable, reason = true, nil
    local inSet = false

    for i = 1, numLines do
        local leftfs = _G[GRATUITY_TOOLTIP .. "TextLeft" .. i]
        local rightfs = _G[GRATUITY_TOOLTIP .. "TextRight" .. i]
        local text = leftfs and leftfs:GetText()
        local rightText = rightfs and rightfs:GetText()
        if text == "" then text = nil end
        if rightText == "" then rightText = nil end

        if usable then
            if rightText and IsRedText(rightfs, rightText) then
                usable, reason = false, rightText
            elseif text and IsRedText(leftfs, text) then
                usable, reason = false, text
            end
        end

        if text and i > 1 and not inSet then
            if ITEM_SET_NAME and Deformat(text, ITEM_SET_NAME) then
                inSet = true
            elseif not ReadBaseLine(stats, text, weapon) then
                ItemBonus:AddBonusInfo(stats, text)
            end
            -- The weapon speed sits on the right side of the damage row.
            if rightText then ReadBaseLine(stats, rightText, weapon) end
        end
    end

    if weapon.mindmg and weapon.maxdmg and weapon.speed and weapon.speed > 0 then
        stats.DPS = (weapon.mindmg + weapon.maxdmg) / 2 / weapon.speed
    end

    return {
        usable = usable,
        reason = reason,
        stats = stats,
        texture = texture,
        name = name,
        equiploc = equiploc,
    }
end

-- Each scan loads the tooltip straight from the item's location where there is one: Unreal
-- Azeroth's SetHyperlink drops the random-property field of a link, so a "... of the Owl"
-- item would scan as its base item. Every entry point returns nil when the item can't be
-- resolved yet.
function ZGV:ScanBagItem(bag, slot)
    local itemid = ItemIDFromLink(GetContainerItemLink(bag, slot))
    if not itemid then return nil end
    if not pcall(Gratuity.SetBagItem, Gratuity, bag, slot) then return nil end
    return ReadLoadedTooltip(itemid)
end

function ZGV:ScanInventoryItem(slot)
    local itemid = ItemIDFromLink(EquippedLink(slot))
    if not itemid then return nil end
    if not pcall(Gratuity.SetInventoryItem, Gratuity, "player", slot) then return nil end
    return ReadLoadedTooltip(itemid)
end

function ZGV:ScanQuestChoice(index)
    local itemid = ItemIDFromLink(GetQuestItemLink("choice", index))
    if not itemid then return nil end
    if not pcall(Gratuity.SetQuestItem, Gratuity, "choice", index) then return nil end
    return ReadLoadedTooltip(itemid)
end

-- For an item known only by its link. The real link can throw "Unknown link type" on this
-- server, whose links carry only 3 trailing fields ("item:ID:0:0:0"), so that bare form is
-- the fallback -- it loses any random-suffix stats.
function ZGV:ScanItemLink(itemlink)
    local itemid = ItemIDFromLink(itemlink)
    if not itemid then return nil end
    if not pcall(Gratuity.SetHyperlink, Gratuity, itemlink) then
        if not pcall(Gratuity.SetHyperlink, Gratuity, "item:" .. itemid .. ":0:0:0") then
            return nil
        end
    end
    return ReadLoadedTooltip(itemid)
end

-- The spec the Gear Advisor scores for, as in ZygorGuidesViewerClassic: db.char.gear_active_build,
-- set from the options or by choosing a talent build; before either happened, the selected
-- talent build's gearspec. "_" is the class's own table (ZGV.GearWeights), also used for a spec
-- with no weights.
function ZGV:GetGearActiveBuild(class)
    local active = ZGV.db.char.gear_active_build
    if active == nil then active = ZGV.TalentAdvisor and ZGV.TalentAdvisor:GetGearSpec(class) end
    local specs = ZGV.GearWeightsBySpec[class]
    if active and specs and specs[active] then return active end
    return "_"
end

-- Makes a spec active (and the one the options show), and rescans the bags for what is an
-- upgrade under its weights.
function ZGV:SetGearActiveBuild(key)
    ZGV.db.char.gear_active_build = key
    ZGV.db.char.gear_selected_build = key
    if ZGV.RescanAllBagItems then ZGV:RescanAllBagItems() end
end

-- The weights and caps of the active spec; the class's own weights and no caps for "_".
function ZGV:GetGearWeights(class)
    local active = ZGV:GetGearActiveBuild(class)
    if active ~= "_" then
        local caps = ZGV.GearCapsBySpec[class]
        return ZGV.GearWeightsBySpec[class][active], caps and caps[active]
    end
    return ZGV.GearWeights[class]
end

-- Classic's cap rule: a capped stat counts half below the level cap, and at the level cap once
-- the equipped gear already has more of it than the cap.
local function CapFactor(stat, caps)
    local cap = caps and caps[stat]
    if not cap then return 1 end
    if UnitLevel("player") < (ZGV.maxlevel or 60) then return 0.5 end
    local ok, equipped = pcall(ItemBonus.GetBonus, ItemBonus, stat)
    if ok and (tonumber(equipped) or 0) > cap then return 0.5 end
    return 1
end

function ZGV:GetItemScore(stats, class)
    local weights, caps = ZGV:GetGearWeights(class)
    if not weights or not stats then return 0 end

    local score = 0
    for stat, value in pairs(stats) do
        score = score + value * (weights[stat] or 0) * CapFactor(stat, caps)
    end
    return score
end

-- Weapon skill tags of the guides' weaponskill("TAG") condition, as the reference names them,
-- mapped to the English skill line names GetSkillLineInfo returns.
local WEAPON_SKILL_NAMES = {
    AXE = "Axes", TH_AXE = "Two-Handed Axes", BOW = "Bows", GUN = "Guns", MACE = "Maces",
    TH_MACE = "Two-Handed Maces", TH_POLE = "Polearms", SWORD = "Swords",
    TH_SWORD = "Two-Handed Swords", TH_STAFF = "Staves", FIST = "Fist Weapons",
    DAGGER = "Daggers", THROWN = "Thrown", CROSSBOW = "Crossbows", WAND = "Wands",
    DUALWIELD = "Dual Wield",
}

function ZGV:GetWeaponSkill(tag)
    local name = WEAPON_SKILL_NAMES[tag]
    if not name then return 0 end
    return (ZGV:GetSkillRank(name))
end

local function DumpLoadedTooltip()
    for i = 1, Gratuity:NumLines() do
        local leftfs = _G[GRATUITY_TOOLTIP .. "TextLeft" .. i]
        local rightfs = _G[GRATUITY_TOOLTIP .. "TextRight" .. i]
        local parts = {}
        local sides = { { "L", leftfs }, { "R", rightfs } }
        for _, side in ipairs(sides) do
            local fs = side[2]
            local text = fs and fs:GetText()
            if text then
                local r, g, b = fs:GetTextColor()
                tinsert(parts, string.format("%s[%.2f %.2f %.2f]%s \"%s\"", side[1], r or -1, g or -1, b or -1,
                    IsRedText(fs, text) and " RED" or "", text))
            end
        end
        print(string.format("  line %d: %s", i, table.concat(parts, "  ")))
    end
end

ItemScore.ItemIDFromLink = ItemIDFromLink
ItemScore.EquippedLink = EquippedLink
ItemScore.IsTwoHanderEquipped = IsTwoHanderEquipped
ItemScore.DumpLoadedTooltip = DumpLoadedTooltip
