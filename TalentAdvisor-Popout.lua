-- Talent Advisor: the advice window. Shows the selected build, its status and the suggested
-- talents, with a Learn button for a single suggested point. While docked it hangs on the
-- talent frame's right edge and opens and closes with it; dragging it away undocks it,
-- dragging it back next to the frame docks it again. A button on the talent frame toggles it.
--
-- Built in Lua on plain frames: the 1.12 XML has no parentKey, and AceGUI doesn't work on
-- Unreal Azeroth. Unreal Azeroth also breaks RegisterForDrag (the frame stays stuck to the
-- mouse) and draws a button's pushed and highlight textures all the time, so dragging runs
-- from OnMouseDown/OnMouseUp and the toggle button swaps its own texture.

local ZTA = ZGV.TalentAdvisor
local popout, button

local WIDTH = 250
local STATUS_COLORS = {
    GREEN = { 0, 1, 0 },
    YELLOW = { 1, 1, 0 },
    ORANGE = { 1, 0.6, 0 },
    RED = { 1, 0, 0 },
    BLACK = { 0.5, 0.5, 0.5 },
}

local function ShowStatusTooltip()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText("Build status:")
    GameTooltip:AddLine(ZTA:GetStatusMessage(), 1, 1, 1, 1)
    GameTooltip:Show()
end

local function ShowButtonTooltip(title, text)
    GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
    GameTooltip:SetText(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, 1) end
    GameTooltip:Show()
end

local function CreateText(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("TOP")
    return fs
end

local function InDockingRange()
    local frame = ZTA.GetTalentFrame()
    if not frame or not frame:IsShown() or not popout:GetLeft() or not frame:GetRight() then return false end
    return math.abs(popout:GetLeft() - frame:GetRight() + 36) < 20
        and popout:GetTop() - frame:GetTop() < 20
        and popout:GetTop() - frame:GetTop() > -200
end

local function CreatePopout()
    popout = CreateFrame("Frame", "ZygorTalentAdvisorPopout", UIParent)
    popout:Hide()
    popout:SetWidth(WIDTH)
    popout:SetHeight(200)
    popout:SetFrameStrata("MEDIUM")
    popout:SetToplevel(true)
    popout:SetMovable(true)
    popout:SetClampedToScreen(true)
    popout:EnableMouse(true)
    popout:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    popout:SetBackdropColor(0, 0, 0, 0.85)
    popout:SetPoint("CENTER", UIParent, "CENTER", 0, 200)

    popout.title = CreateText(popout, "GameFontNormal")
    popout.title:SetPoint("TOPLEFT", popout, "TOPLEFT", 12, -10)
    popout.title:SetText("Zygor Talent Advisor")

    popout.close = CreateFrame("Button", "ZygorTalentAdvisorPopoutCloseButton", popout, "UIPanelCloseButton")
    popout.close:SetPoint("TOPRIGHT", popout, "TOPRIGHT", 0, 0)

    -- the title strip is the drag handle
    local drag = CreateFrame("Button", nil, popout)
    drag:SetPoint("TOPLEFT", popout, "TOPLEFT", 0, 0)
    drag:SetPoint("BOTTOMRIGHT", popout, "TOPRIGHT", -30, -24)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then ZTA.Popout_OnDragStart() end
    end)
    drag:SetScript("OnMouseUp", function()
        if popout.moving then ZTA.Popout_OnDragStop() end
    end)

    popout.buildLabel = CreateText(popout, "GameFontNormalSmall")
    popout.buildLabel:SetPoint("TOPLEFT", popout, "TOPLEFT", 12, -30)
    popout.buildLabel:SetText("Build:")
    popout.build = CreateText(popout, "GameFontHighlight")
    popout.build:SetPoint("TOPLEFT", popout.buildLabel, "TOPRIGHT", 5, 1)
    popout.build:SetWidth(WIDTH - 70)

    local warning = CreateFrame("Frame", nil, popout)
    warning:SetWidth(12)
    warning:SetHeight(12)
    warning:SetPoint("TOPRIGHT", popout, "TOPRIGHT", -12, -30)
    warning:EnableMouse(true)
    warning.texture = warning:CreateTexture(nil, "ARTWORK")
    warning.texture:SetAllPoints(warning)
    warning.texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    warning:SetScript("OnEnter", ShowStatusTooltip)
    warning:SetScript("OnLeave", function() GameTooltip:Hide() end)
    popout.warning = warning

    popout.suggestionLabel = CreateText(popout, "GameFontNormalSmall")
    popout.suggestionLabel:SetPoint("TOPLEFT", popout, "TOPLEFT", 12, -50)
    popout.suggestionLabel:SetWidth(WIDTH - 24)

    -- one tree name and talent list per tree
    popout.groups, popout.talents = {}, {}
    for i = 1, 3 do
        popout.groups[i] = CreateText(popout, "GameFontHighlightLarge")
        popout.groups[i]:SetWidth(WIDTH - 30)
        popout.talents[i] = CreateText(popout, "GameFontNormal")
        popout.talents[i]:SetWidth(WIDTH - 30)
    end

    popout.accept = CreateFrame("Button", "ZygorTalentAdvisorPopoutAcceptButton", popout, "UIPanelButtonTemplate")
    popout.accept:SetWidth(80)
    popout.accept:SetHeight(22)
    popout.accept:SetPoint("BOTTOMRIGHT", popout, "BOTTOMRIGHT", -10, 40)
    popout.accept:SetText("Learn")
    popout.accept:SetScript("OnClick", function() ZTA:LearnSuggestedTalents() end)
    popout.accept:SetScript("OnEnter", function() ShowButtonTooltip("Learn the suggested talent.") end)
    popout.accept:SetScript("OnLeave", function() GameTooltip:Hide() end)

    popout.configure = CreateFrame("Button", "ZygorTalentAdvisorPopoutConfigureButton", popout, "UIPanelButtonTemplate")
    popout.configure:SetWidth(120)
    popout.configure:SetHeight(22)
    popout.configure:SetPoint("BOTTOM", popout, "BOTTOM", 0, 12)
    popout.configure:SetText("Configure")
    popout.configure:SetScript("OnClick", function() ZGV:OpenOptions() end)
    popout.configure:SetScript("OnEnter", function() ShowButtonTooltip("Click to set up a target build or configure the Advisor.") end)
    popout.configure:SetScript("OnLeave", function() GameTooltip:Hide() end)

    popout:SetScript("OnShow", function() ZTA.Popout_OnShow() end)
    popout:SetScript("OnHide", function() ZTA.Popout_OnHide() end)
    popout:SetScript("OnUpdate", function() ZTA.Popout_OnUpdate() end)
    table.insert(UISpecialFrames, "ZygorTalentAdvisorPopout")
end

-- The toggle button on the talent frame's right edge.
local function CreateButton()
    button = CreateFrame("Button", "ZygorTalentAdvisorPopoutButton", UIParent)
    button:Hide()
    button:SetWidth(24)
    button:SetHeight(44)
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetAllPoints(button)
    button:SetScript("OnClick", function()
        if popout:IsShown() then popout:Hide() else ZTA.Popout_Popout() end
    end)
    button:SetScript("OnEnter", function()
        this.hover = true
        ZTA.Popout_UpdateButton()
        ShowButtonTooltip("Talent Advisor", "Select a target build and have the Advisor suggest talents for you to pick anytime you have talent points to spend.")
    end)
    button:SetScript("OnLeave", function()
        this.hover = nil
        ZTA.Popout_UpdateButton()
        GameTooltip:Hide()
    end)
    ZTA.advisorbutton = button
end

-- The toggle button's look: pressed while the window is open, lit while hovered.
function ZTA.Popout_UpdateButton()
    if not button then return end
    local name = "popout-button-2"
    if popout and popout:IsShown() then
        name = "popout-button-2-down"
    elseif button.hover then
        name = "popout-button-2-hi"
    end
    button.texture:SetTexture(ZGV.DIR .. "\\Skins\\" .. name)
end

local function Ensure()
    if not popout then CreatePopout() end
    if not button then
        CreateButton()
        ZTA.Popout_UpdateButton()
    end
end

-- Puts the toggle button on the talent frame, once the frame exists.
function ZTA.Popout_AttachButton()
    Ensure()
    local frame = ZTA.GetTalentFrame()
    if not frame then return end
    if button:GetParent() ~= frame and button:GetParent() ~= popout then
        ZTA.Popout_UpdateDocking()
    end
    if ZGV.db.profile.zta_enabled then button:Show() else button:Hide() end
end

function ZTA.Popout_Popout()
    Ensure()
    if ZGV.db.profile.zta_windowdocked then ZTA.ShowTalentFrame() end
    popout:Show()
end

function ZTA.Popout_Hide()
    if popout then popout:Hide() end
end

function ZTA.Popout_OnShow()
    if ZGV.db.profile.zta_windowdocked then ZTA.ShowTalentFrame() end
    ZTA.Popout_Reparent()
    ZTA.Popout_UpdateDocking()
    ZTA.Popout_Update()
    ZTA.Popout_UpdateButton()
end

function ZTA.Popout_OnHide()
    ZTA.Popout_UpdateDocking()
    ZTA.Popout_UpdateButton()
end

function ZTA.Popout_OnUpdate()
    if popout.moving then
        ZGV.db.profile.zta_windowdocked = InDockingRange()
        ZTA.Popout_UpdateDocking()
    end
end

-- Closing the talent frame mid-drag leaves the window undocked where it is.
function ZTA.Popout_OnTalentFrameHide()
    if not popout then return end
    if popout.moving and popout:GetParent() == ZTA.GetTalentFrame() then
        ZGV.db.profile.zta_windowdocked = false
        ZTA.Popout_Reparent()
        ZTA.Popout_UpdateDocking()
        popout.moving = nil
        popout:StopMovingOrSizing()
        popout:Show()
    end
end

function ZTA.Popout_OnDragStart()
    ZGV.db.profile.zta_windowdocked = false
    ZTA.Popout_UpdateDocking()
    popout:StartMoving()
    popout.moving = true
end

function ZTA.Popout_OnDragStop()
    popout:StopMovingOrSizing()
    popout.moving = nil
    ZGV.db.profile.zta_windowdocked = InDockingRange()
    ZTA.Popout_Reparent()
    ZTA.Popout_UpdateDocking()
end

function ZTA.Popout_Reparent()
    local frame = ZTA.GetTalentFrame()
    if ZGV.db.profile.zta_windowdocked and frame then
        popout:SetParent(frame)
        -- above anything a UI skin adds to the talent frame at the frame's own level
        popout:SetFrameLevel(frame:GetFrameLevel() + 5)
        popout:ClearAllPoints()
        popout:SetPoint("TOPLEFT", frame, "TOPRIGHT", -36, -130)
    else
        local left, top = popout:GetLeft(), popout:GetTop()
        popout:SetParent(UIParent)
        if left and top then
            popout:ClearAllPoints()
            popout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end
end

-- The toggle button sits on the window's edge while it is docked and shown, on the talent
-- frame's edge otherwise; the close button only shows while undocked.
function ZTA.Popout_UpdateDocking()
    Ensure()
    local frame = ZTA.GetTalentFrame()
    if frame then
        button:ClearAllPoints()
        if ZGV.db.profile.zta_windowdocked and popout:IsShown() then
            button:SetParent(popout)
            button:SetPoint("TOPLEFT", popout, "TOPRIGHT", -5, -10)
        else
            button:SetParent(frame)
            button:SetPoint("TOPLEFT", frame, "TOPRIGHT", -35, -140)
        end
        button:SetFrameLevel(button:GetParent():GetFrameLevel() + 6)
    end
    if ZGV.db.profile.zta_windowdocked then popout.close:Hide() else popout.close:Show() end
end

-- "Name (2,3)" or "Name (2-4)" for a talent's suggested ranks, just "Name" for a one-rank talent.
local function FormatTalent(levels)
    local s = levels.name
    if levels[1] == 0 then return s end
    s = s .. " |cff997700("
    local n = table.getn(levels)
    if n < 3 then s = s .. table.concat(levels, ",") else s = s .. levels[1] .. "-" .. levels[n] end
    return s .. ")|r"
end

function ZTA.Popout_Update()
    if not popout or not popout:IsShown() then return end

    local status = ZTA.status or {}
    local color = STATUS_COLORS[status.code]
    if color then
        popout.warning.texture:SetVertexColor(color[1], color[2], color[3])
        popout.warning:Show()
    else
        popout.warning:Hide()
    end

    local groups = 0
    local accept = false
    if not ZTA.currentBuildTitle then
        popout.build:SetText("none")
        popout.suggestionLabel:SetText("Click the Configure button below to set up a target build.")
    else
        popout.build:SetText(ZTA.currentBuildTitle)
        local suggestion = ZTA.suggestion
        if not ZTA.currentBuild or status.code == "BLACK" or status.code == "?" then
            popout.suggestionLabel:SetText(status.msg or "")
        elseif ZTA:GetUnusedTalentPoints() == 0 then
            popout.suggestionLabel:SetText("You have no talent points available.")
        elseif not suggestion or table.getn(suggestion) == 0 then
            popout.suggestionLabel:SetText("No suggestions can be made.")
        else
            popout.suggestionLabel:SetText("Currently suggested talents:")
            for tabname, talents in pairs(ZTA:GetSuggestionFormatted()) do
                if groups == 3 then break end
                groups = groups + 1
                local lines = {}
                for _, levels in ipairs(talents) do table.insert(lines, FormatTalent(levels)) end
                popout.groups[groups]:SetText(tabname)
                popout.talents[groups]:SetText(table.concat(lines, "\n"))
            end
            accept = table.getn(suggestion) == 1
        end
    end

    -- lay the tree groups out under the label and size the window to fit
    local anchor = popout.suggestionLabel
    local height = 50 + popout.suggestionLabel:GetHeight()
    for i = 1, 3 do
        popout.groups[i]:ClearAllPoints()
        popout.talents[i]:ClearAllPoints()
        if i <= groups then
            popout.groups[i]:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
            popout.talents[i]:SetPoint("TOPLEFT", popout.groups[i], "BOTTOMLEFT", 0, -2)
            popout.groups[i]:Show()
            popout.talents[i]:Show()
            height = height + 8 + popout.groups[i]:GetHeight() + popout.talents[i]:GetHeight()
            anchor = popout.talents[i]
        else
            popout.groups[i]:Hide()
            popout.talents[i]:Hide()
        end
    end

    if accept then popout.accept:Show() else popout.accept:Hide() end
    popout:SetHeight(height + 80)
end
