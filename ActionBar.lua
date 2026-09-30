-- The action bar, ZygorGuidesViewerClassic's ActionBar.lua on the 1.12 client: a button for
-- each visible goal of the current step and its stickies that has something to do -- use an
-- item, cast a spell, target the NPC to talk to or the mob to kill. The bar is a child of the
-- viewer, attached above its top edge; it is not moved on its own.
--
-- 1.12 has neither secure action buttons nor a macro API, so a button calls the game
-- functions itself instead of running a generated macro. The same action is reachable from a
-- key binding (Bindings.xml) and from a macro of the player's own: "/script ZGV:GoalAction()"
-- does the first button's action, "/script ZGV:GoalAction(2)" the second one's.

local ActionBar = {}
ZGV.ActionBar = ActionBar

local BUTTON_SIZE = 30
local BUTTON_SPACE = 5
-- As many buttons as fit above the 240 wide viewer at Classic's button size and spacing;
-- further actions are left out.
local MAX_BUTTONS = 6
-- Classic's gap between the viewer's top edge and the bar.
local BAR_GAP = 5

-- Classic's actionbar.tga: 64x64 cells in a 512x64 sheet.
local ICON_SHEET = ZGV.DIR.."\\Skins\\actionbar"
local ICON_CELLS = { talk = 1, kill = 2 }
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

BINDING_HEADER_ZYGORGUIDESVIEWERNG = "ZygorGuidesViewerNG"
for i = 1, 5 do
    setglobal("BINDING_NAME_ZYGORGUIDESVIEWERNG_ACTION"..i, "Action Bar Button "..i)
end

local actions = {}
local buttons = {}
local bar

-- The bag and slot of a carried item, by ID, or by name for a goal without one.
local function FindBagItem(action)
    local itemid = tonumber(action.itemid)
    local namepart = action.name and ("[" .. action.name .. "]")
    for bag = 0, 4 do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                if itemid then
                    if tonumber(string.match(link, "item:(%d+)")) == itemid then return bag, slot end
                elseif string.find(link, namepart, 1, true) then
                    return bag, slot
                end
            end
        end
    end
end

-- The spellbook index of a spell's highest rank, by name.
local function FindSpell(name)
    local found
    for i = 1, 300 do
        local spell = GetSpellName(i, BOOKTYPE_SPELL)
        if not spell then break end
        if spell == name then found = i end
    end
    return found
end

-- Classic's choice of button per goal, in its order: a spell, an item, an NPC to talk to or
-- click, a mob to kill. The item check has no option of its own in Classic. A goal whose
-- button is already on the bar adds none, as the viewer shows a repeated kill goal once.
local function AddGoal(goal, itemactions, npcactions, seen)
    if goal.status == "hidden" then return end
    local profile = ZGV.db.profile
    local action
    if goal.castspell and goal.castspellid and profile.actionbar_quest then
        action = { kind = "spell", name = goal.castspell, key = "spell:"..goal.castspell }
        action.list = itemactions
    elseif goal.item or goal.itemid then
        action = { kind = "item", itemid = goal.itemid, name = goal.item,
                   key = "item:"..tostring(goal.itemid or goal.item) }
        action.list = itemactions
    elseif (goal.action == "talk" or goal.action == "clicknpc") and goal.npcid and goal.npc
        and profile.actionbar_talk then
        action = { kind = "talk", name = goal.npc, key = "talk:"..goal.npc }
        action.list = npcactions
    elseif goal.action == "kill" and goal.targetid and goal.target and profile.actionbar_kill then
        action = { kind = "kill", name = goal.target, key = "kill:"..goal.target }
        action.list = npcactions
    end
    if not action or seen[action.key] then return end
    seen[action.key] = true
    action.goal = goal
    tinsert(action.list, action)
    action.list = nil
end

local function ItemTexture(action)
    local bag, slot = FindBagItem(action)
    if bag then return (GetContainerItemInfo(bag, slot)) end
    if action.itemid then
        local _, _, _, _, _, _, _, _, texture = GetItemInfo(action.itemid)
        return texture
    end
end

local function SpellTexture(action)
    local index = FindSpell(action.name)
    return index and GetSpellTexture(index, BOOKTYPE_SPELL)
end

local function SetIcon(texture, action)
    local cell = ICON_CELLS[action.kind]
    if cell then
        texture:SetTexture(ICON_SHEET)
        texture:SetTexCoord((cell - 1) / 8, cell / 8, 0, 1)
        return
    end
    texture:SetTexCoord(0, 1, 0, 1)
    local icon
    if action.kind == "item" then icon = ItemTexture(action) else icon = SpellTexture(action) end
    texture:SetTexture(icon or FALLBACK_ICON)
end

local function CreateBar()
    bar = CreateFrame("Frame", "ZygorGuidesViewerNGActionBar", ZygorGuidesViewerNGFrame)
    bar:SetPoint("BOTTOMLEFT", ZygorGuidesViewerNGFrame, "TOPLEFT", 0, BAR_GAP)
    bar:SetHeight(BUTTON_SIZE + 2 * BUTTON_SPACE)
    bar:EnableMouse(true)
    -- The viewer's own background colour (ZygorGuidesViewerNGFrame.xml).
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(0.1, 0.1, 0.1, 0.9)
    bar:Hide()
end

local function GetButton(i)
    if buttons[i] then return buttons[i] end
    local button = CreateFrame("Button", "ZygorGuidesViewerNGActionButton"..i, bar)
    button:SetWidth(BUTTON_SIZE)
    button:SetHeight(BUTTON_SIZE)
    button:SetPoint("TOPLEFT", bar, "TOPLEFT", BUTTON_SPACE + (i - 1) * (BUTTON_SIZE + BUTTON_SPACE), -BUTTON_SPACE)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    button:GetHighlightTexture():SetBlendMode("ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function() ActionBar:Click(i) end)
    button:SetScript("OnEnter", function() ActionBar:ShowTooltip(i, button) end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function() ActionBar:Pickup(i) end)
    buttons[i] = button
    return button
end

-- Rebuilds the actions from the goal statuses ZGV:UpdateFrame has just computed, and shows
-- them. The actions are kept while the bar is switched off, for the key bindings and macros.
function ActionBar:Update()
    actions = {}
    local profile = ZGV.db.profile
    if profile.enable_actionbuttons and ZGV.CurrentGuide and ZGV.CurrentStep then
        local itemactions, npcactions, seen = {}, {}, {}
        for _, goal in ipairs(ZGV.CurrentStep.goals) do
            AddGoal(goal, itemactions, npcactions, seen)
        end
        for _, stickystep in ipairs(ZGV.CurrentStickies or {}) do
            for _, goal in ipairs(stickystep.goals) do
                AddGoal(goal, itemactions, npcactions, seen)
            end
        end
        for _, list in ipairs({ itemactions, npcactions }) do
            for _, action in ipairs(list) do
                if table.getn(actions) < MAX_BUTTONS then tinsert(actions, action) end
            end
        end
    end

    if not bar then CreateBar() end
    local count = profile.enable_actionbar and table.getn(actions) or 0
    for i = 1, MAX_BUTTONS do
        if i <= count then
            local button = GetButton(i)
            SetIcon(button.icon, actions[i])
            button:Show()
        elseif buttons[i] then
            buttons[i]:Hide()
        end
    end
    if count > 0 then
        bar:SetWidth(BUTTON_SPACE + count * (BUTTON_SIZE + BUTTON_SPACE))
        bar:Show()
    else
        bar:Hide()
    end
end

-- Does the n-th action (the first without n). Targeting clears the target first and drops a
-- dead mob afterwards, as Classic's generated macros do (/cleartarget, /target,
-- /cleartarget [dead]). An item that is not in the bags or a spell not in the spellbook does
-- nothing.
function ActionBar:Click(n)
    local action = actions[n or 1]
    if not action then return end
    if action.kind == "item" then
        local bag, slot = FindBagItem(action)
        if bag then UseContainerItem(bag, slot) end
    elseif action.kind == "spell" then
        local index = FindSpell(action.name)
        if index then CastSpell(index, BOOKTYPE_SPELL) end
    else
        ClearTarget()
        TargetByName(action.name, true)
        if action.kind == "kill" and UnitIsDead("target") then ClearTarget() end
    end
end

function ZGV:GoalAction(n)
    ActionBar:Click(n)
end

-- An item shows its own tooltip; anything else the part of its goal the button acts on.
-- An item the client has not cached is not linked, so the tooltip never asks the server
-- for it. Placed under the button, as Classic's ANCHOR_BOTTOM places it; that anchor puts
-- the tooltip in the middle of the screen on this client, so the point is set by hand.
function ActionBar:ShowTooltip(n, button)
    local action = actions[n]
    if not action then return end
    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOP", button, "BOTTOM", 0, 0)
    local bag, slot
    if action.kind == "item" then bag, slot = FindBagItem(action) end
    local loaded
    if bag then
        GameTooltip:SetBagItem(bag, slot)
        loaded = true
    elseif action.kind == "item" and action.itemid and GetItemInfo(action.itemid) then
        loaded = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:"..action.itemid..":0:0:0")
    end
    if not loaded then
        GameTooltip:SetText(action.goal:GetActionText(), 1, 1, 1)
    end
    GameTooltip:Show()
end

-- Dragging an item or spell button puts it on the cursor, for the player's own action bars.
function ActionBar:Pickup(n)
    local action = actions[n]
    if not action then return end
    if action.kind == "item" then
        local bag, slot = FindBagItem(action)
        if bag then PickupContainerItem(bag, slot) end
    elseif action.kind == "spell" then
        local index = FindSpell(action.name)
        if index then PickupSpell(index, BOOKTYPE_SPELL) end
    end
end
