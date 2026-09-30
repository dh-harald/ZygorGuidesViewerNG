-- Talent Advisor: follows the selected build (see TalentAdvisor-Registering.lua) and suggests
-- which talents to spend the unspent points on.
--
-- The build is checked against the talents already learned:
--   GREEN   the learned talents are exactly the start of the build
--   YELLOW  they are all in the build but out of order, and the unspent points can catch up
--   ORANGE  as YELLOW, but the unspent points are not enough to catch up yet
--   RED     some learned talent is not in the build (or over its rank there)
--   BLACK   the build can't be used: broken, too short, or already complete
-- Suggestions are the first build entries not learned yet, one per unspent point.
--
-- Shown on the Blizzard talent frame as "rank/build rank" in each talent's rank box and as
-- "+n" / X balloons, in the talent tooltip, and in the advice window
-- (TalentAdvisor-Popout.lua), which opens with the talent frame while docked and the build
-- fits. Clicking a talent that is not suggested asks for confirmation.

local ZTA = ZGV.TalentAdvisor

local L = {
    status_green = "This build fits your character |cff88ff88correctly|r.",
    status_yellow = "Your current talents match the selected build, but they were chosen |cffeeff44out of suggested order|r. Luckily, you still have enough talent points available to complete the build now.",
    status_orange = "|cffffbb00Warning:|r Your current talents match the selected build, but they were chosen |cffffee44out of order|r and right now you |cffffee44don't|r have enough talent points available to return to the optimal build path. You will need to gain %d more talent point(s) to again develop optimally.",
    status_red = "|cffff0000Error:|r This build |cffff5555doesn't match|r your current talents. If you want to use this build, please reset your talents, or check the 'Allow this build' option to override safety measures.",
    status_red_forced = "|cffff0000Warning:|r This build |cffff5555doesn't match|r your current talents, but we'll try to make the best out of it anyway.",
    status_black_brokenbuild = "|cffff0000Error:|r |cffffaaaaThis build contains unrecognized talents. It is broken and unusable.|r\n%s",
    status_black_builderror = "|cffff0000Error:|r |cffffaaaaThis build requires %d points in the talent '%s', while only %d are possible! It is broken and unusable|r.",
    status_black_smallbuild = "|cffff0000Error:|r This build has only %d talents in it, while you have already spent %d. This build is either incomplete, or is a 'starting' build and not applicable anymore.",
    status_black_complete = "This build is now complete.\nGo forth and be awesome.",
    status_black_next = "This build is now complete.\nReset your talents and switch to the |cff5588ff%s|r build to continue.",
    status_black_different = "This is a different build, but your character's build is complete.\nYou'll have to reset your talents to use this build.",
    status_nodata = "Talent data is not available yet.",
    warning_learn1_orange = "|cffffbb00Notice:|r\nFor the selected build, |cff5588ff%s|r, it is advised that you learn the |cff55ffaa%s|r talent:\n|cffffff55%s|r\n\nThe talent you selected is present in this build, but it is recommended to take it later. Learning talents out of order may result in less than optimal progress.\n\nAre you sure you wish to learn\n|cffff5555%s|r\nat this point?",
    warning_learn1_red0 = "|cffff0000Warning!|r\nFor the selected build, |cff5588ff%s|r, you should |cffff7777not|r learn this talent!\n\nAre you absolutely sure you wish to learn it?",
    warning_learn1_red = "|cffff0000Warning!|r\nFor the selected build, |cff5588ff%s|r, you should |cffff7777not|r exceed rank %s of |cffffff55%s|r.\n\nAre you absolutely sure you wish to learn it?",
    talenttooltip_build = "Talent Advisor: |cff5588ff%s|r",
    talenttooltip = "Suggested rank: %s%d|r",
    talenttooltip_overshot = "|cffff8800You have %d rank(s) too many for this build!",
    talenttooltip_undershot = "You'll need to put %d rank(s) more in this talent.",
    talenttooltip_ok = "|cff88ff88This talent is at the suggested rank for this build.",
    talenttooltip_none = "|cffffaaaaThis talent is not recommended in this build.",
}
ZTA.L = L

local PLAYER_TALENTS_PER_TIER = 5
local MAX_TALENT_BUTTONS = 40

-- The Blizzard_TalentUI frame, whichever name the client gives it; its talent buttons are
-- <name>Talent<index>. nil until the load-on-demand addon is loaded.
local function GetTalentFrame()
    return PlayerTalentFrame or TalentFrame
end
ZTA.GetTalentFrame = GetTalentFrame

local function TalentButtonPrefix(frame, talent)
    return frame:GetName() .. "Talent" .. talent
end

-- Loads Blizzard_TalentUI. LoadAddOn is documented as protected on Unreal Azeroth, so the
-- FrameXML loaders go first.
local function LoadTalentUI()
    if GetTalentFrame() then return end
    if TalentFrame_LoadUI then
        pcall(TalentFrame_LoadUI)
    elseif UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_TalentUI")
    else
        pcall(LoadAddOn, "Blizzard_TalentUI")
    end
    ZTA:HookTalentFrame()
end

local function ShowTalentFrame()
    LoadTalentUI()
    local frame = GetTalentFrame()
    if frame and not frame:IsShown() then ShowUIPanel(frame) end
end
ZTA.ShowTalentFrame = ShowTalentFrame

-- Runs handler after a frame's script. Not AceHook's HookScript: Unreal Azeroth reports
-- HasScript false for some frames, returns nil from GetScript for some native XML buttons,
-- and doesn't restore `this` after a nested handler, so `this` is saved around the original.
local function PostHookScript(frame, script, handler)
    local orig = frame:GetScript(script)
    frame:SetScript(script, function()
        local caller = this
        if orig then orig() end
        this = caller
        handler(caller, orig)
    end)
end

--[[
 ######################################################################################################################
     S E T U P
 ######################################################################################################################
--]]

-- Called from ZGV:OnEnable.
function ZTA:Initialize()
    if self.initialised then return end
    self.initialised = true
    self.status = { code = "?" }
    self.lastUnspent = UnitCharacterPoints("player")

    StaticPopupDialogs["ZYGORTALENTADVISOR_WARNING"] = {
        text = "%s",
        button1 = YES,
        button2 = NO,
        OnAccept = function(data)
            if data then ZTA.Old_LearnTalent(data.tab, data.talent) end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
    }

    self:SetHooks()
    self:HookTalentFrame()
    self:LoadBuilds()
end

-- Replaces LearnTalent (clicks on talents that are not suggested ask first), or restores it
-- while disabled.
function ZTA:SetHooks()
    self.Old_LearnTalent = self.Old_LearnTalent or LearnTalent

    if ZGV.db.profile.zta_enabled then
        LearnTalent = ZTA.LearnTalentChecked
    else
        LearnTalent = self.Old_LearnTalent
    end
    if self.advisorbutton then
        if ZGV.db.profile.zta_enabled then self.advisorbutton:Show() else self.advisorbutton:Hide() end
    end
end

-- Blizzard_TalentUI is load-on-demand: hooked here once it is loaded, from Initialize, from
-- ADDON_LOADED or after loading it ourselves. TalentFrame_Update is wrapped, the frame's
-- OnShow/OnHide and every talent button's OnEnter post-hooked; the tooltip is extended from
-- OnEnter because a replaced GameTooltip.SetTalent doesn't stick on Unreal Azeroth.
function ZTA:HookTalentFrame()
    if self.hooked then return end
    local frame = GetTalentFrame()
    if not frame or type(TalentFrame_Update) ~= "function" then return end
    self.hooked = true

    local origUpdate = TalentFrame_Update
    TalentFrame_Update = function(a1, a2, a3)
        origUpdate(a1, a2, a3)
        ZTA:PlayTalented()
    end

    PostHookScript(frame, "OnShow", function() ZTA:OnTalentFrameShow() end)
    PostHookScript(frame, "OnHide", function() ZTA:OnTalentFrameHide() end)

    for talent = 1, MAX_TALENT_BUTTONS do
        local button = getglobal(TalentButtonPrefix(frame, talent))
        if button then
            PostHookScript(button, "OnEnter", function(caller, orig)
                local tab = PanelTemplates_GetSelectedTab(frame)
                if not tab then return end
                if not orig then
                    GameTooltip:SetOwner(caller, "ANCHOR_RIGHT")
                    GameTooltip:SetTalent(tab, caller:GetID())
                end
                ZTA:AddTooltipLines(GameTooltip, tab, caller:GetID())
            end)
        end
    end
end

function ZTA:SetEnabled(enabled)
    ZGV.db.profile.zta_enabled = enabled
    self:SetHooks()
    if enabled then
        self:LoadBuilds()
        self:PlayTalented()
    else
        self:CleanupTalentFrame()
        ZTA.Popout_Hide()
    end
end

function ZTA:LoadBuilds()
    local key = ZGV.db.char.zta_currentBuildKey
    if key and key ~= "_" then self:SetCurrentBuild(key, "startup") end
end

-- The build could not be resolved while the client had no talent data yet: try again once
-- it has.
function ZTA:EnsureLoaded()
    if self.status and self.status.code == "?" and self.currentBuildKey and self:GetTalentMap() then
        self:LoadBuilds()
    end
end

--[[
 ######################################################################################################################
     E V E N T S
 ######################################################################################################################
--]]

-- The event's point delta is not read: whether new points arrived is decided by comparing
-- the unspent points with the last known count.
function ZGV:OnTalentPointsChanged()
    local unspent = UnitCharacterPoints("player")
    local gained = ZTA.lastUnspent and unspent > ZTA.lastUnspent
    ZTA.lastUnspent = unspent
    if not ZGV.db.profile.zta_enabled then return end
    ZTA:EnsureLoaded()
    if gained then ZTA:OnNewTalents() end
    ZTA:UpdateSuggestions()
    ZTA:PlayTalented()
    ZTA.Popout_Update()
end

function ZGV:OnTalentAdvisorEnteringWorld()
    ZTA.lastUnspent = UnitCharacterPoints("player")
    if ZGV.db.profile.zta_enabled then ZTA:EnsureLoaded() end
end

function ZGV:OnTalentAdvisorAddonLoaded()
    ZTA:HookTalentFrame()
end

ZGV:RegisterEvent("CHARACTER_POINTS_CHANGED", "OnTalentPointsChanged")
ZGV:RegisterEvent("PLAYER_ENTERING_WORLD", "OnTalentAdvisorEnteringWorld")
ZGV:RegisterEvent("ADDON_LOADED", "OnTalentAdvisorAddonLoaded")

-- zta_popup: 0 nothing, 1 open the talent frame, 2 open the advice window.
function ZTA:OnNewTalents()
    if not self.currentBuild then return end
    local popup = ZGV.db.profile.zta_popup or 0
    if popup == 1 then
        ShowTalentFrame()
    elseif popup == 2 then
        ZTA.Popout_Popout()
    end
end

-- Opening the talent frame also opens the docked advice window while the build fits.
function ZTA:OnTalentFrameShow()
    if not ZGV.db.profile.zta_enabled or not ZGV.db.profile.zta_windowdocked then return end
    self:EnsureLoaded()
    if not self.currentBuild then return end
    self:UpdateSuggestions()
    local code = self.status and self.status.code
    if code == "GREEN" or code == "YELLOW" or code == "ORANGE"
        or (code == "RED" and ZGV.db.profile.zta_forcebuild) then
        ZTA.Popout_Popout()
    end
end

function ZTA:OnTalentFrameHide()
    ZTA.Popout_OnTalentFrameHide()
end

--[[
 ######################################################################################################################
     B U I L D S
 ######################################################################################################################
--]]

-- Selects a build by its "CLASS Title" key, "_" for none.
function ZTA:SetCurrentBuild(key, startup)
    local build = self.registeredBuilds[key]
    self.currentBuildKey = key
    self.currentBuild = nil
    self.currentBuildTitle = nil
    self.currentBuildInfo = nil
    self.suggestion = nil

    if build then
        local _, myclass = UnitClass("player")
        local map = self:GetTalentMap()
        local data, msg
        if build.class ~= myclass then
            self.status = { code = "BLACK", msg = "This build is for another class." }
        elseif not map then
            self.status = { code = "?", msg = L["status_nodata"] }
        else
            self.status = { code = "?" }
            data, msg = self:ResolveBuild(build, map)
            if not data then
                self.status = { code = "BLACK", msg = string.format(L["status_black_brokenbuild"], msg) }
            else
                local _, maxcounts = self:CountBuildTalents(nil, data)
                for tab, talents in pairs(maxcounts) do
                    for talent, count in pairs(talents) do
                        local name, _, _, _, _, maxrank = GetTalentInfo(tab, talent)
                        if name and maxrank < count then
                            self.status = { code = "BLACK", msg = string.format(L["status_black_builderror"], count, name, maxrank) }
                        end
                    end
                end
            end
        end
        self.currentBuild = data
        self.currentBuildTitle = build.title
        self.currentBuildInfo = build
    else
        self.status = {}
    end

    ZGV.db.char.zta_currentBuildKey = key

    self:UpdateSuggestions()
    self:PlayTalented()
    ZTA.Popout_Update()

    -- choosing a build also picks the Gear Advisor's spec, as in Classic
    if not startup and build and build.gearspec then ZGV:SetGearActiveBuild(build.gearspec) end
end

-- The stat weight profile of the selected build, for the Gear Advisor; nil without a build
-- or when the build is for another class than the one asked about.
function ZTA:GetGearSpec(class)
    local build = self.currentBuildInfo
    if not build or (class and build.class ~= class) then return nil end
    return build.gearspec
end

-- The builds of the player's class, "CLASS Title" -> title, for the options dropdown.
function ZTA:GetClassBuilds()
    local _, myclass = UnitClass("player")
    local list = {}
    for _, key in ipairs(self.buildKeys) do
        local build = self.registeredBuilds[key]
        if build.class == myclass then list[key] = build.title end
    end
    return list
end

-- Ranks per [tab][talent]: counts in the first num build entries, maxcounts in the whole build.
function ZTA:CountBuildTalents(num, build)
    local counts = {}
    local maxcounts = {}
    local zeroer = { __index = function(tab, key) return 0 end }

    build = build or self.currentBuild
    local size = table.getn(build)
    if num and num > size then num = size end

    if num then
        for i = 1, num do
            local tab, talent = build[i][1], build[i][2]
            if not counts[tab] then counts[tab] = {} setmetatable(counts[tab], zeroer) end
            counts[tab][talent] = counts[tab][talent] + 1
        end
    end
    for i = 1, size do
        local tab, talent = build[i][1], build[i][2]
        if not maxcounts[tab] then maxcounts[tab] = {} setmetatable(maxcounts[tab], zeroer) end
        maxcounts[tab][talent] = maxcounts[tab][talent] + 1
    end

    return counts, maxcounts
end

function ZTA:GetTalentsSpent()
    local spent = 0
    for tab = 1, GetNumTalentTabs() do
        local _, _, pointsSpent = GetTalentTabInfo(tab)
        spent = spent + (pointsSpent or 0)
    end
    return spent
end

function ZTA:GetUnusedTalentPoints()
    return UnitCharacterPoints("player") or 0
end

-- Marks every build entry matched by a learned rank as taken; a learned rank with no entry
-- left to match makes the build fail.
function ZTA:MarkBuildTaken(build)
    local size = table.getn(build)
    for n = 1, size do build[n].taken = nil end
    build.realfail = nil

    for tab = 1, GetNumTalentTabs() do
        for talent = 1, GetNumTalents(tab) do
            local name, _, _, _, rank = GetTalentInfo(tab, talent)
            if name then
                for i = 1, rank do
                    local found
                    for n = 1, size do
                        if build[n][1] == tab and build[n][2] == talent and not build[n].taken then
                            build[n].taken = true
                            found = true
                            break
                        end
                    end
                    if not found then
                        build.realfail = true
                        break
                    end
                end
            end
        end
    end
end

function ZTA:GetBuildStatus(build)
    local status = { code = "?", pointsleft = 0, missed = 0 }

    self:MarkBuildTaken(build)

    local force = ZGV.db.profile.zta_forcebuild

    if build.realfail and not force then
        status.code = "RED"
        return status
    end

    -- the last taken entry of the build
    local last = 0
    for n = 1, table.getn(build) do
        if build[n].taken then last = n end
    end

    if self:GetTalentsSpent() == last then
        status.code = "GREEN"
    else
        local pointsleft = self:GetUnusedTalentPoints()
        local missed = 0
        for n = 1, last do
            if not build[n].taken then missed = missed + 1 end
        end
        status.pointsleft = pointsleft
        status.missed = missed
        if pointsleft >= missed then status.code = "YELLOW" else status.code = "ORANGE" end
    end

    if build.realfail and force then status.code = "RED" end

    return status
end

function ZTA:UpdateSuggestions()
    if not self.currentBuild then return end
    self.suggestion, self.status = self:MakeSuggestion()
end

-- Returns the suggestion and the status. The suggestion is a list of {tab=, talent=}, one per
-- point, and also counts the points per talent under "tab.talent".
function ZTA:MakeSuggestion()
    local suggestion = {}
    local build = self.currentBuild
    if not build then return suggestion, self.status end
    if self.status and self.status.code == "BLACK" and not self.status.dynamic then return suggestion, self.status end

    local size = table.getn(build)
    local spent = self:GetTalentsSpent()

    if size < spent then
        return suggestion, { code = "BLACK", dynamic = true, msg = string.format(L["status_black_smallbuild"], size, spent) }
    end

    local status = self:GetBuildStatus(build)

    if size == spent then
        local alltaken = true
        for i = 1, size do
            if not build[i].taken then alltaken = false break end
        end
        if alltaken then
            local nextbuild = self.currentBuildInfo and self.currentBuildInfo.next
            local msg = nextbuild and string.format(L["status_black_next"], nextbuild) or L["status_black_complete"]
            return suggestion, { code = "BLACK", dynamic = true, complete = true, msg = msg }
        end
        return suggestion, { code = "BLACK", dynamic = true, msg = L["status_black_different"] }
    end

    if status.code ~= "RED" or ZGV.db.profile.zta_forcebuild then
        local points = self:GetUnusedTalentPoints()
        for i = 1, size do
            if points == 0 then break end
            if not build[i].taken then
                points = points - 1
                local tab, talent = build[i][1], build[i][2]
                suggestion[tab .. "." .. talent] = (suggestion[tab .. "." .. talent] or 0) + 1
                table.insert(suggestion, { tab = tab, talent = talent })
            end
        end
    end

    return suggestion, status
end

function ZTA:GetStatusMessage()
    local status = self.status
    if not status or not status.code then return "" end

    if status.code == "BLACK" or status.code == "?" then return status.msg or ""
    elseif status.code == "RED" then
        if ZGV.db.profile.zta_forcebuild then return L["status_red_forced"] end
        return L["status_red"]
    elseif status.code == "GREEN" then return L["status_green"]
    elseif status.code == "YELLOW" then return L["status_yellow"]
    elseif status.code == "ORANGE" then return string.format(L["status_orange"], status.missed - status.pointsleft)
    end
    return ""
end

-- The suggestion grouped by tree: tree name -> list of
-- { tex=, tab=, talent=, name=, [1..n] = the ranks to learn (0 for a single-rank talent) }.
function ZTA:GetSuggestionFormatted()
    local sugformatted = {}
    local suggestion = self.suggestion or {}
    for i = 1, table.getn(suggestion) do
        local tab, talent = suggestion[i].tab, suggestion[i].talent
        local tabname = GetTalentTabInfo(tab)
        local name, tex, _, _, rank, maxrank = GetTalentInfo(tab, talent)
        if not sugformatted[tabname] then sugformatted[tabname] = {} end
        local group = sugformatted[tabname]
        local inserted = false
        for j = 1, table.getn(group) do
            if group[j].name == name then
                if maxrank > 1 then
                    table.insert(group[j], rank + table.getn(group[j]) + 1)
                else
                    table.insert(group[j], 0)
                end
                inserted = true
                break
            end
        end
        if not inserted then
            table.insert(group, { tex = tex, tab = tab, name = name, talent = talent, [1] = (maxrank > 1) and (rank + 1) or 0 })
        end
    end
    return sugformatted
end

-- The advice window's Learn button: learns the suggestion when it is a single talent point.
function ZTA:LearnSuggestedTalents()
    local suggestion = self.suggestion
    if not self.currentBuild or not suggestion or table.getn(suggestion) ~= 1 then return end
    self.Old_LearnTalent(suggestion[1].tab, suggestion[1].talent)
    if not ZGV.db.profile.zta_windowdocked then
        ZTA.Popout_Hide()
    else
        ZTA.Popout_Update()
    end
end

--[[
 ######################################################################################################################
     T A L E N T   F R A M E
 ######################################################################################################################
--]]

function ZTA:CleanupTalentFrame()
    local frame = GetTalentFrame()
    if not frame then return end
    for talent = 1, MAX_TALENT_BUTTONS do
        local prefix = TalentButtonPrefix(frame, talent)
        local bor = getglobal(prefix .. "RankBorder")
        if bor then
            bor:SetWidth(32)
            bor:SetHeight(32)
        end
        local hint = getglobal(prefix .. "Hint")
        if hint then hint:Hide() end
    end

    if frame:IsVisible() and TalentFrame_Update then
        self.cleaning = true
        TalentFrame_Update()
        self.cleaning = false
    end
end

-- Draws the build on the talent frame's current tab: runs after every TalentFrame_Update.
function ZTA:PlayTalented()
    if not ZGV.db.profile.zta_enabled then return end
    if self.cleaning then return end
    local frame = GetTalentFrame()
    if not frame or not frame:IsVisible() then return end

    self:EnsureLoaded()
    ZTA.Popout_AttachButton()

    local build = self.currentBuild
    local force = ZGV.db.profile.zta_forcebuild

    self:UpdateSuggestions()

    if not build or not self.status or self.status.code == "BLACK" or self.status.code == "?"
        or (self.status.code == "RED" and not force) then
        self:CleanupTalentFrame()
        ZTA.Popout_Update()
        return
    end

    local suggestion = self.suggestion
    ZTA.Popout_Update()

    local tab = PanelTemplates_GetSelectedTab(frame)
    if not tab then return end
    local _, _, tabPointsSpent = GetTalentTabInfo(tab)
    local counts, maxcounts = self:CountBuildTalents(self:GetTalentsSpent(), build)
    local unspent = self:GetUnusedTalentPoints()

    for talent = 1, GetNumTalents(tab) do
        local prefix = TalentButtonPrefix(frame, talent)
        local button = getglobal(prefix)
        local txt = getglobal(prefix .. "Rank")
        local bor = getglobal(prefix .. "RankBorder")
        local icon = getglobal(prefix .. "IconTexture")
        if button and txt and bor then
            -- the balloon sits on a frame of its own above the button: on 1.12 a frame created
            -- at runtime in the talent scroll child (such as a UI skin's button border) draws
            -- over the button's own regions
            local hint = getglobal(prefix .. "Hint")
            if not hint then
                local holder = CreateFrame("Frame", nil, button)
                holder:SetAllPoints(button)
                holder:SetFrameLevel(button:GetFrameLevel() + 3)
                hint = holder:CreateTexture(prefix .. "Hint", "OVERLAY")
                hint:SetPoint("LEFT", icon or button, "RIGHT", -14, 5)
                hint:SetWidth(32)
                hint:SetHeight(32)
                hint:SetTexture(ZGV.DIR .. "\\Skins\\zta_hints")
            end

            local name, _, tier, _, rank, _, _, available = GetTalentInfo(tab, talent)
            rank = rank or 0
            local desired = maxcounts[tab] and maxcounts[tab][talent] or 0

            -- the build's rank in the rank box
            if ZGV.db.profile.zta_preview then
                if desired > 0 and rank < desired then
                    if not txt:IsVisible() then
                        txt:SetText("|cffaaaaaa" .. rank .. "/|r|cff00aaff" .. desired .. "|r")
                        txt:Show()
                        bor:Show()
                    else
                        txt:SetText(rank .. "|cffaaaaaa/|r|cff00aaff" .. desired .. "|r")
                    end
                    bor:SetWidth(54)
                    bor:SetHeight(32)
                elseif desired > 0 and rank == desired then
                    txt:SetText(rank .. "/" .. desired)
                    bor:SetWidth(54)
                    bor:SetHeight(32)
                elseif rank > desired then
                    txt:SetText(rank .. "|cffaaaaaa/|r|cffff0000" .. desired .. "|r")
                    bor:SetWidth(54)
                    bor:SetHeight(32)
                end
            else
                bor:SetWidth(32)
                bor:SetHeight(32)
                txt:SetText(rank)
            end

            -- hint balloons: "+n" for suggested points, X for a rank over the build's
            local suggested = suggestion and ZGV.db.profile.zta_hints and suggestion[tab .. "." .. talent]
            if suggested and suggested > 0 then
                hint:SetTexCoord(0.125 * suggested, 0.125 * (suggested + 1), 0, 1)
                hint:Show()
            elseif ZGV.db.profile.zta_hints and rank > desired then
                hint:SetTexCoord(0.875, 1.000, 0, 1)
                hint:Show()
            else
                hint:Hide()
            end
            if hint:IsShown() and SetDesaturation then
                local locked = (tier - 1) * PLAYER_TALENTS_PER_TIER > (tabPointsSpent or 0)
                    or not available or (unspent == 0 and rank == 0)
                SetDesaturation(hint, locked and 1 or nil)
            end
        end
    end
end

-- LearnTalent replacement: a talent that is not in the suggestion asks for confirmation first.
function ZTA.LearnTalentChecked(tab, talent)
    local self = ZTA
    if UnitCharacterPoints("player") == 0 then return end

    local _, _, tabPointsSpent = GetTalentTabInfo(tab)
    local name, _, tier, _, rank = GetTalentInfo(tab, talent)
    if not name then return end

    -- a click on a locked talent learns nothing, so it needs no warning either
    if (tier - 1) * PLAYER_TALENTS_PER_TIER > tabPointsSpent then return end
    local reqtier, reqcolumn, learnable = GetTalentPrereqs(tab, talent)
    if reqtier and not learnable then return end

    local suggestion = self.suggestion
    if self.currentBuild and suggestion and table.getn(suggestion) > 0 then
        local found
        for i = 1, table.getn(suggestion) do
            if suggestion[i].tab == tab and suggestion[i].talent == talent then found = i end
        end
        if not found then
            local _, maxcounts = self:CountBuildTalents(self:GetTalentsSpent(), self.currentBuild)
            local buildTitle = self.currentBuildTitle
            local text
            if not maxcounts[tab] or maxcounts[tab][talent] == 0 then
                -- not in the build at all
                text = string.format(L["warning_learn1_red0"], buildTitle)
            elseif rank + 1 > maxcounts[tab][talent] then
                -- in the build, but not this far
                text = string.format(L["warning_learn1_red"], buildTitle, maxcounts[tab][talent], name)
            else
                -- in the build, but later
                local stab, stalent = suggestion[1].tab, suggestion[1].talent
                text = string.format(L["warning_learn1_orange"], buildTitle, GetTalentTabInfo(stab),
                    GetTalentInfo(stab, stalent), name)
            end
            local dialog = StaticPopup_Show("ZYGORTALENTADVISOR_WARNING", text)
            if dialog then dialog.data = { tab = tab, talent = talent } end
            return
        end
    end

    self.Old_LearnTalent(tab, talent)
end

-- Adds the build's rank of the talent to its tooltip.
function ZTA:AddTooltipLines(tooltip, tab, talent)
    if not ZGV.db.profile.zta_enabled then return end
    local build = ZTA.currentBuild
    local status = ZTA.status
    if not build or not status or status.code == "BLACK" or status.code == "?" then return end

    local _, maxcounts = ZTA:CountBuildTalents(nil)
    local _, _, _, _, cur_rank = GetTalentInfo(tab, talent)
    cur_rank = cur_rank or 0
    local build_rank = maxcounts[tab] and maxcounts[tab][talent] or 0
    local color, secondline
    if cur_rank > build_rank then
        color = "|cffff0000"
        secondline = string.format(L["talenttooltip_overshot"], cur_rank - build_rank)
    elseif cur_rank < build_rank then
        color = "|cffffff00"
        secondline = string.format(L["talenttooltip_undershot"], build_rank - cur_rank)
    elseif build_rank > 0 then
        color = "|cff00ff00"
        secondline = L["talenttooltip_ok"]
    else
        color = "|cffaaaaaa"
        secondline = L["talenttooltip_none"]
    end
    -- the build and its rank on lines of their own: the rank at the end of one long line can
    -- fall past the tooltip's maximum width
    tooltip:AddLine(string.format(L["talenttooltip_build"], ZTA.currentBuildTitle), 1, 1, 1)
    tooltip:AddLine(string.format(L["talenttooltip"], color, build_rank), 1, 1, 1)
    if ZTA:GetUnusedTalentPoints() > 0 then tooltip:AddLine(secondline, 1, 1, 1) end
    tooltip:Show()
end
