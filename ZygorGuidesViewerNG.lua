local addon_name = "ZygorGuidesViewerNG"

ZGV = LibStub("AceAddon-3.0"):NewAddon(addon_name, "AceEvent-3.0", "AceConsole-3.0", "AceHook-3.0", "AceTimer-3.0")
ZygorGuidesViewer = ZGV

local DIR = "Interface\\AddOns\\" .. addon_name
ZGV.DIR = DIR
ZGV.IMAGESDIR = ZGV.DIR .. "\\Guides\\Images\\"

-- The reference viewer's typeface, Open Sans (Skins/opensans.ttf, bold Skins/opensansb.ttf),
-- instead of the default GameFontNormal/GameFontNormalSmall. SetFont(path, size) is a plain,
-- long-standing FontString API with no 1.12 version risk, which is simpler than a virtual
-- <Font> template for a handful of labels.
ZGV.Font = ZGV.DIR .. "\\Skins\\opensans.ttf"
ZGV.FontBold = ZGV.DIR .. "\\Skins\\opensansb.ttf"

ZGV.RegisteredGuidesTitles = {}

ZGV.registeredguides = {}
ZGV.registeredguides_count = 0

ZGV.icon = LibStub("LibDBIcon-1.0")
ZGV.icon.tooltip = GameTooltip

local _, _, _, client = GetBuildInfo()
client = client or 11200
ZGV.client = client

ZGV.IsVanilla = false
-- ZGV.isTBC = false -- not supported atm
ZGV.IsWOTLK = false
ZGV.IsTurtle = false
ZGV.IsUA = false -- Unreal Azeroth

if client == 5875 or GetUECvar then
    ZGV.IsVanilla = true
    ZGV.IsUA = true
end

if client >= 10000 and client <= 11300 then -- 1.12.x (no classic support)
    ZGV.IsVanilla = true
    ZGV.maxlevel = 60
end

-- ZGV.throttling: supporting variables for protecting some events/functions to call too frequently
ZGV.throttling = {
    ["QUEST_LOG_UPDATE"] = {
        ["delay"] = 0.2,
        ["tries"] = 0,
        ["retry"] = 2, -- disable throttling for 2 tries
        ["tick"] = -1  -- starts with 0 on /reload
    }
}

ZGV.LDB = LibStub("LibDataBroker-1.1"):NewDataObject("ZGVLDB", {
    type = "launcher",
    icon = "Interface\\Addons\\" .. addon_name .. "\\Skins\\icon",
    tocname = "ZygorGuidesViewerNG",
    label = "ZygorGuidesViewerNG",
    OnTooltipShow = function(tooltip)
        tooltip:AddDoubleLine(addon_name, ZGV.version)
        tooltip:AddDoubleLine("Left-Click", "Toggle Guide Frame", 1, 1, 1, 1, 1, 1)
        tooltip:AddDoubleLine("Right-Click", "Open Settings", 1, 1, 1, 1, 1, 1)
    end,
    OnClick = function(self, button)
        if button == "LeftButton" then
            ZGV:ViewerFrameToggle()
        elseif button == "RightButton" then
            ZGV:OpenOptions()
        end
    end
})

function ZGV:OnInitialize()
    ZGV:Print("Initialized")
    local defaults = {
        profile = {
            -- Travel system, ZygorGuidesViewerClassic's defaults (see Pointer.lua).
            -- ZygorGuidesViewerClassic's default (see Step:IsSkippable).
            skipimpossible = true,
            pathfinding = true,
            travelusehs = true,
            traveluseitems = true,
            travelusespells = true,
            pathfinding_comfort = 0,
            -- ZygorGuidesViewerClassic's default (see the map lines in Pointer.lua).
            maplines_enabled = true,
            -- Action bar, ZygorGuidesViewerClassic's defaults (see ActionBar.lua).
            enable_actionbuttons = true,
            enable_actionbar = true,
            actionbar_quest = true,
            actionbar_talk = true,
            actionbar_kill = true,
            -- Talent Advisor, ZygorGuidesViewerClassic's defaults (see TalentAdvisor.lua).
            zta_enabled = true,
            zta_hints = true,
            zta_preview = true,
            zta_popup = 1,
            zta_windowdocked = true,
            zta_forcebuild = false,
        },
        char = {
            viewer = {
                shown = true,
                locked = false
            },
            quests = {
            },
            favourites = {
            },
            geardeclined = {
            },
            -- Per-character, not per-profile: whether the Gear Advisor is worth having on
            -- depends on where THIS character actually is (still leveling vs. already at
            -- max level), not a setting that should follow the whole account/profile.
            gearAdvisorEnabled = true,
            -- The Talent Advisor's selected build, "CLASS Title" (see RegisterTalentBuild), "_" for none.
            zta_currentBuildKey = "_",
            -- LibTaxi-1.0's saved table: the flight points this character knows, keyed by
            -- English name and by position tag (see Pointer.lua and GOALTYPES['fpath']).
            taxis = {
            },
        }
    }

    ZGV.db = LibStub("AceDB-3.0"):New("ZygorGuidesViewerSettings", defaults, true)
    ZGV.db.global.sv_version = ZGV.db.global.sv_version or ZGV.version
    ZGV.db.profile.minimap = ZGV.db.profile.minimap or {}
    ZGV.db.profile.minimap.hide = ZGV.db.profile.minimap.hide or false
    -- "or true" would be wrong here: it'd stomp a stored "false" back to true on every
    -- login, since "false or true" is always true. Nil-check instead.
    if ZGV.db.profile.autoAcceptQuests == nil then ZGV.db.profile.autoAcceptQuests = true end
    if ZGV.db.profile.autoCompleteQuests == nil then ZGV.db.profile.autoCompleteQuests = true end
    ZGV.db.profile.autoCompleteRewardChoice = ZGV.db.profile.autoCompleteRewardChoice or "best"

    -- Restore the viewer position if one is stored (see ZGV:ContainerGetPosition). The XML
    -- default CENTER anchor has to be cleared first, or the frame would keep both points.
    if ZGV.db.char.viewer and ZGV.db.char.viewer.point and ZGV.db.char.viewer.relativePoint and ZGV.db.char.viewer.xOfs and ZGV.db.char.viewer.yOfs
    then
        ZygorGuidesViewerNGFrame:ClearAllPoints()
        ZygorGuidesViewerNGFrame:SetPoint(ZGV.db.char.viewer.point, UIParent, ZGV.db.char.viewer.relativePoint, ZGV.db.char.viewer.xOfs, ZGV.db.char.viewer.yOfs)
    end

    if ZGV.db.char.viewer.shown then
        ZygorGuidesViewerNGFrame:Show()
    end

    ZGV.icon:Register("ZGV", ZGV.LDB, ZGV.db.profile.minimap)

    if ZGV.IsVanilla == true
    then
        local LC = LibStub("LibConfig-1.0")
        LC:RegisterOptionsTable("ZygorGuidesViewerNG", "ZygorGuidesViewerNG", ZGV.ConfigTable)
        ZGV.OptionsFrame = LC:AddToBlizOptions("ZygorGuidesViewerNG", "ZygorGuidesViewerNG")
    elseif ZGV.IsWOTLK == true
    then
        local ACD = LibStub("AceConfigDialog-3.0")
        -- "ZygorGuidesViewerNG" is the /zygor command table's name in AceConfigRegistry-3.0;
        -- the category keeps "ZygorGuidesViewerNG" as its displayed name.
        LibStub("AceConfig-3.0").RegisterOptionsTable(ZygorGuidesViewer, "ZygorGuidesViewerNG-Options", ZGV.ConfigTable)
        ZGV.OptionsFrame = ACD:AddToBlizOptions("ZygorGuidesViewerNG-Options", "ZygorGuidesViewerNG")
    end

    LibStub("AceConfig-3.0").RegisterOptionsTable(ZGV, ZGV.CommandTableName, ZGV.CommandTable, "zygor")
end

function ZGV:OnEnable()
    ZGV:Print("PLAYER_LOGIN")
    ZGV:Print("Loaded "..ZGV.registeredguides_count.." guides.")

    if ZGV.db.char.selectedGuide then
        ZGV:SetGuide(ZGV.db.char.selectedGuide)
    else
        -- No guide chosen yet on this character -- pick whatever's currently flagged
        -- SUGGESTED (see Guide:GetStatus/condition_suggested) instead of leaving the
        -- viewer empty. For a fresh character this resolves to exactly one of the three
        -- race-gated starter guides; for an existing character logging in for the first
        -- time it may instead land on some other currently-relevant suggested guide --
        -- still a reasonable default, just not guaranteed to be a "starter" guide
        -- specifically.
        local suggested = ZGV:FindSuggestedGuides()
        for _, guides in pairs(suggested) do
            if guides[1] then
                ZGV:SetGuide(guides[1])
                break
            end
        end
    end
    ZGV:ScanQuestLog()
    ZGV.TalentAdvisor:Initialize()
    ZGV:StartVisitCheck()

    -- Last, so a travel library failing to start never costs the guide itself.
    ZGV:StartTravel()
end

function ZGV:AlignFrame()
        self.Frame:AlignFrame()
        -- ZGV.F.SaveFrameAnchor(self.Frame:GetParent(),"frame_anchor")
end

function ZGV:LoadInitialGuide(fastload)
    self.frameNeedsResizing = 1
    self:AlignFrame()
    -- self:UpdateFrame(true)
end

function ZGV:Startup_LoadGuides()
    self:LoadInitialGuide("fastload")
end

function ZGV:StartUp()
    ZGV:Print("StartUp")
    self:Startup_LoadGuides()
end

function ZGV:DoMutex(m)
    return false
end

function ZGV:SanitizeGuideTitle(title)
    title = string.gsub(title, "\\", "/")
    title = string.gsub(title, "^Zygor's ", "")
    title = string.gsub(title, "^Alliance ", "")
    title = string.gsub(title, "^Horde ", "")
    return title
end

function ZGV:RegisterGuide(title, header, data)
    title = ZGV:SanitizeGuideTitle(title)
    self.Print(title)
    local guide = ZGV.GuideProto:New(title,header,data)
    tinsert(self.registeredguides,guide)
end

-- The title is sanitized like the registered ones, as ZygorGuidesViewerClassic does: a guide
-- header's next= is written the way RegisterGuide receives titles ("Leveling Guides\\...").
function ZGV:GetGuideByTitle(title)
    if not title then return end
    title = ZGV:SanitizeGuideTitle(title)
    for i, guide in ipairs(self.registeredguides) do
        if guide.title == title then
            return guide
        end
    end
end

--- Makes `guide` (a title string or a guide object) the active guide, parsing it first
-- if needed, and refreshes the viewer frame. Called both on login (if a guide was already
-- selected last session) and whenever the settings dropdown picks a new one.
function ZGV:SetGuide(guide, stepnum)
    if type(guide) == "string" then
        guide = ZGV:GetGuideByTitle(guide)
    end
    if not guide then return end

    if not guide.fully_parsed then
        local ok = guide:Parse()
        if not ok then
            ZGV:Print("Could not load guide: "..guide.title)
            return
        end
    end

    ZGV.CurrentGuide = guide

    -- Resume where we left off (survives /reload), but only for the guide we were
    -- already on -- switching to a different guide always starts at step 1.
    if type(stepnum) == "string" then
        local step = guide:GetStep(stepnum)
        stepnum = step and step.num or 1
    end
    if stepnum then
        ZGV.CurrentStepNum = stepnum
    elseif ZGV.db.char.selectedGuide == guide.title and ZGV.db.char.currentStepNum then
        ZGV.CurrentStepNum = ZGV.db.char.currentStepNum
    else
        ZGV.CurrentStepNum = 1
    end

    ZGV.CurrentStep = guide:GetStep(ZGV.CurrentStepNum)
    ZGV.db.char.currentStepNum = ZGV.CurrentStepNum
    ZGV.db.char.selectedGuide = guide.title

    ZGV:Print("Selected guide: "..guide.title)

    ZGV:UpdateFrame()
end

--- Advance/retreat within the current guide; ZGV:UpdateFrame below renders the result.
--
-- mode:
--   nil     -- the Next button's left click: exactly one step, even onto an already completed
--              one (e.g. paging forward again after browsing back through old steps).
--   "auto"  -- UpdateFrame found the current step complete: move on, and keep moving past every
--              step that is already complete or impossible (Step:IsSkippable), so progress
--              never stops on a finished step.
--   "fast"  -- the Next button's right click: the same run, as ZygorGuidesViewerClassic's
--              SkipStep(fast) does.
-- Manual navigation (a left click, StepBack) sets ZGV.pause, as in ZygorGuidesViewerClassic:
-- UpdateFrame does not advance past the landing step, even a completed one, until a step is
-- seen incomplete again. The automatic and right-click runs clear it.
--
-- A step that's fully hidden (Step:IsFullyHidden -- e.g. a whole step gated off by |only/|if
-- for a class/race that isn't this character's) is different from "already complete": there's
-- nothing there to ever show this character, in either direction, so both StepForward and
-- StepBack always skip straight past those -- unlike an already-completed step, which is still
-- worth being able to browse back to.
function ZGV:StepForward(mode)
    if not ZGV.CurrentGuide then return end
    local guide = ZGV.CurrentGuide
    local from = ZGV.CurrentStep or guide:GetStep(ZGV.CurrentStepNum or 1)
    local landed, landednum, ranoff
    -- A step is left through its jump (Step:GetNext): "+1" unless a goal's |next applies. A
    -- jump to a label that does not exist goes on to the following step instead. A run never
    -- passes the same step twice, so jumps cannot loop.
    local seen = {}
    while from and not seen[from] do
        seen[from] = true
        local step
        repeat
            local num, jumpguide = from:GetJumpDestination()
            if jumpguide and ZGV:GetGuideByTitle(jumpguide) then
                ZGV:SetGuide(jumpguide, num)
                return
            elseif jumpguide then
                num = nil
            end
            step = guide:GetStep(num or from.num + 1)
            from = step
        until not step or not step:IsFullyHidden()
        if not step then
            ranoff = true
            break
        end

        landed, landednum = step, step.num
        if not mode or not step:IsSkippable() then break end
    end

    -- Ran off the end of this guide's steps with nothing incomplete left -- if the guide author
    -- flagged a follow-up (header's next="<title>", see Guide.lua's Guide:New), continue straight
    -- into it instead of stopping. SetGuide already handles everything else (parsing, resetting
    -- to step 1, persisting the selection).
    if ranoff and ZGV.CurrentGuide.next then
        local nextguide = ZGV:GetGuideByTitle(ZGV.CurrentGuide.next)
        if nextguide then
            ZGV:SetGuide(nextguide)
            return
        end
    end

    -- The end of the guide, with no next guide to load (none named, or the named one is not
    -- among the loaded guides): stay on the last step, as ZygorGuidesViewerClassic does, and
    -- let a left click on Next open the options window (guide selection: Guide Viewer page). UpdateFrame returns right after an
    -- automatic StepForward, so the frame is redrawn here. A run that passed completed steps
    -- before the end lands on the last of them below.
    if not landed then
        if not mode then ZGV:OpenOptions() end
        ZGV:UpdateFrame(true)
        return
    end

    ZGV.pause = not mode
    ZGV.CurrentStepNum = landednum
    ZGV.CurrentStep = landed
    ZGV.db.char.currentStepNum = ZGV.CurrentStepNum
    ZGV.ManualWaypoint = nil
    ZGV:UpdateFrame(true)
end

function ZGV:StepBack()
    if not ZGV.CurrentGuide then return end
    local num = ZGV.CurrentStepNum or 1
    while num > 1 do
        num = num - 1
        local step = ZGV.CurrentGuide:GetStep(num)
        if not (step and step:IsFullyHidden()) then break end
    end
    ZGV.pause = true
    ZGV.CurrentStepNum = num
    ZGV.CurrentStep = ZGV.CurrentGuide:GetStep(ZGV.CurrentStepNum)
    ZGV.db.char.currentStepNum = ZGV.CurrentStepNum
    ZGV.ManualWaypoint = nil
    ZGV:UpdateFrame(true)
end

-- Ported from the reference ZGV:GetStickiesAt. step.stickies (real step references) is
-- resolved once by Guide:Parse from step.sticky_labels -- this just filters that list down
-- to the ones actually worth showing right now (still sticky-able, not already done), so
-- ZGV.CurrentStickies (see Step:IsCurrentlySticky/Goal:IsVisible's notinsticky check, and
-- the render loop in ZGV:UpdateFrame) reflects the current step correctly.
function ZGV:GetStickiesAt(stepnum)
    -- Always returns a table, never nil: ZGV:UpdateFrame assigns this
    -- return value straight into ZGV.CurrentStickies, and Step:IsCurrentlySticky ipairs()s
    -- that global unconditionally -- an early-return nil here (the common case, since most
    -- steps have no stickies at all) would clobber it and crash the next IsCurrentlySticky
    -- call with "table expected, got nil".
    if not ZGV.CurrentGuide then return {} end
    local step = ZGV.CurrentGuide.steps[stepnum or ZGV.CurrentStepNum]
    if not step or not step.stickies then return {} end

    local result = {}
    for _, stickystep in ipairs(step.stickies) do
        if stickystep:CanBeSticky() and not stickystep:IsComplete() then
            tinsert(result, stickystep)
        end
    end
    return result
end

function ZGV:FindSuggestedGuides()
    local suggested={}
    local suggroups={}
    for i,guide in ipairs(self.registeredguides) do
            local status=guide:GetStatus()
            if status=="SUGGESTED" then
                    if not suggested[guide.type] then suggested[guide.type]={} end
                    tinsert(suggested[guide.type],guide)
            end
            if guide.sugGroup and (status=="VALID" or status=="SUGGESTED") then
                    if not suggroups[guide.sugGroup] then suggroups[guide.sugGroup]={} end
                    tinsert(suggroups[guide.sugGroup],guide)
            end
    end
    return suggested, suggroups
end

-- Rendering for the guide-name bar / nav bar / content rows / progress bar defined in
-- ZygorGuidesViewerNGFrame.xml. Uses the frames' full global names (e.g.
-- ZygorGuidesViewerNGFrameContent) rather than the parent.ChildName shorthand -- both work
-- on 1.12, but the explicit form has zero version-compatibility risk to double-check.
--
-- Row icons are placeholders (built-in WoW textures) until real Zygor-style art assets are
-- available -- see ROW_ICONS below. Row background colors follow the goal's status (see
-- ROW_COLOR_* below), never its action type.

local FONT_REGULAR = ZGV.Font

-- The reference viewer's default sizes (Starlight style): goal text at fontsize (11) plus the
-- style's StepFontSizeMod (1), tips and other secondary lines at fontsecsize (10).
local TEXT_FONT_SIZE = 12
local TIP_FONT_SIZE = 10

local ROW_HEIGHT = 20
local TIP_HEIGHT = 14     -- one rendered line of FONT_REGULAR @ TIP_FONT_SIZE

-- Fixed vertical geometry for the main text + tip. The tip anchors to the row at a fixed
-- offset, not to the main text's BOTTOMLEFT corner: that would depend on the FontString's
-- auto-computed height, which this client's partial FontString implementation doesn't report
-- reliably, and the tip could land on top of the text. Sizing the row from the same constants
-- removes the dependency entirely. No word wrap is involved (SetWordWrap is nil here).
local TEXT_LEFT = 22      -- main text left x (icon spans 4..18, +4 gap)
local TEXT_TOP = 3        -- main text top inset (icon anchored TOPLEFT (4,-3))
local TEXT_HEIGHT = 17    -- one rendered line of FONT_REGULAR @ TEXT_FONT_SIZE
local TIP_GAP = 2         -- vertical gap between main text and tip
local TEXT_WIDTH = 214    -- text region width: row (240) - TEXT_LEFT (22) - right pad (4)

-- Manual word wrap. SetWordWrap is nil on this client, so lines are broken here using
-- GetStringWidth -- the one measurement API confirmed working (GetStringHeight is nil).
-- Measurement happens on the SAME FontString the text renders on (fs is passed in), so the
-- widths always match the actually-rendered font even if SetFont fell back to a default
-- (the addon's bundled font may not load on every client).

-- The "|cAARRGGBB" colour still open at the end of line (nil if none or closed by "|r"),
-- given the colour open at its start.
local function OpenColorAfter(line, open)
    local pos = 1
    while true do
        local s, e, kind = string.find(line, "|([cr])", pos)
        if not s then
            return open
        end
        if kind == "c" then
            open = string.sub(line, s, s + 9)
            pos = s + 10
        else
            open = nil
            pos = e + 1
        end
    end
end

-- Wrap one paragraph (no newlines) at word boundaries so no line exceeds maxWidth.
-- A colour span broken across lines is closed at the end of each line and reopened at the
-- start of the next, so every line stands on its own.
-- Returns the wrapped text and its line count.
local function WrapParagraph(fs, text, maxWidth)
    local words = {}
    for word in string.gmatch(text, "%S+") do
        table.insert(words, word)
    end
    local nwords = table.getn(words)
    if nwords == 0 then
        return text, 1
    end
    local lines = {}
    local current = words[1]
    for i = 2, nwords do
        local candidate = current .. " " .. words[i]
        fs:SetText(candidate)
        if fs:GetStringWidth() <= maxWidth then
            current = candidate
        else
            table.insert(lines, current)
            current = words[i]
        end
    end
    table.insert(lines, current)
    local nlines = table.getn(lines)
    local open
    for i = 1, nlines do
        local line = lines[i]
        if open then
            line = open .. line
        end
        open = OpenColorAfter(line, nil)
        if open and i < nlines then
            line = line .. "|r"
        end
        lines[i] = line
    end
    return table.concat(lines, "\n"), nlines
end

-- Wrap text that may already contain newlines (several |tip lines are joined with "\n").
-- Each existing line is wrapped independently and re-joined, preserving the hard breaks.
local function WrapText(fs, text, maxWidth)
    if not text or text == "" then
        return text or "", 1
    end
    local segments = {}
    local start = 1
    while true do
        local pos = string.find(text, "\n", start)
        if not pos then
            table.insert(segments, string.sub(text, start))
            break
        end
        table.insert(segments, string.sub(text, start, pos - 1))
        start = pos + 1
    end
    local out = {}
    local total = 0
    for i = 1, table.getn(segments) do
        local wrapped, n = WrapParagraph(fs, segments[i], maxWidth)
        table.insert(out, wrapped)
        total = total + n
    end
    return table.concat(out, "\n"), total
end

-- Goal:GetStatus -> row background {r, g, b, a}, using the reference viewer's default colours
-- (goalbackincomplete/goalbackcomplete/goalbackimpossible): "incomplete" red (still to do),
-- "complete" green, "impossible"/"pending" gray (not doable right now, e.g. its quest is not
-- in the log), "passive" transparent (nothing to complete: talk, goto, plain text). An
-- incomplete counted goal shifts from red towards green with its progress (see ProgressColor),
-- as the reference does with its goalbackprogress option on -- the 3.3.5 viewer's default.
local ROW_COLOR_INCOMPLETE = { 0.65, 0.08, 0.10, 0.7 }
local ROW_COLOR_PROGRESSING = { 0.6, 0.7, 0.0, 0.7 }
local ROW_COLOR_COMPLETE = { 0.2, 0.7, 0.0, 0.7 }
local ROW_COLOR_UNAVAILABLE = { 0.3, 0.3, 0.3, 0.7 }
local ROW_COLOR_PASSIVE = { 0, 0, 0, 0 }
-- The whole row (text and icon too) is dimmed while unavailable, as in the reference.
local ROW_ALPHA_UNAVAILABLE = 0.4

-- The reference's ZGV.gradient3 as its viewer calls it: red -> yellow-green -> green, with the
-- midpoint colour at half of the scaled range, and progress scaled by 0.7 so an incomplete goal
-- never reaches the full "complete" green.
local function ProgressColor(ratio)
    local perc = math.max(0, math.min(1, ratio or 0)) * 0.7
    local from, to = ROW_COLOR_INCOMPLETE, ROW_COLOR_PROGRESSING
    if perc <= 0.5 then
        perc = perc / 0.5
    else
        from, to = ROW_COLOR_PROGRESSING, ROW_COLOR_COMPLETE
        perc = (perc - 0.5) / 0.5
    end
    return
        from[1] + (to[1] - from[1]) * perc,
        from[2] + (to[2] - from[2]) * perc,
        from[3] + (to[3] - from[3]) * perc
end

local ROW_ICONS = {
    talk = "Interface\\GossipFrame\\GossipGossipIcon",
    accept = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}

local rows = {}

local function GetRow(content, index)
    local row = rows[index]
    if not row then
        row = CreateFrame("Frame", nil, content)
        -- Rows are created on demand, long after the viewer tree was lifted to its frame
        -- level (ZygorGuidesViewerNGFrame.lua), so each one is placed right above its
        -- parent explicitly instead of trusting the client's default for a new child.
        row:SetFrameLevel(content:GetFrameLevel() + 1)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", content, "LEFT", 0, 0)
        row:SetPoint("RIGHT", content, "RIGHT", 0, 0)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(true)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(14)
        row.icon:SetHeight(14)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)

        row.text = row:CreateFontString(nil, "ARTWORK")
        row.text:SetFont(FONT_REGULAR, TEXT_FONT_SIZE)
        row.text:SetJustifyH("LEFT")
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)

        -- |tip text (goal.tip): smaller, directly below the main text, in the reference
        -- viewer's tip colour (|cffeeeecc).
        row.tip = row:CreateFontString(nil, "ARTWORK")
        row.tip:SetFont(FONT_REGULAR, TIP_FONT_SIZE)
        row.tip:SetJustifyH("LEFT")
        row.tip:SetTextColor(0.93, 0.93, 0.8)
        row.tip:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, -(TEXT_TOP + TEXT_HEIGHT + TIP_GAP))
        row.tip:SetPoint("RIGHT", row, "RIGHT", -4, 0)

        -- "Click Here to Continue |confirm"-style goals make the whole row clickable (see
        -- RenderGoal below, which turns this on/off per row since rows are pooled/reused
        -- across different goals). A plain Frame can still take mouse clicks once
        -- EnableMouse is on -- doesn't need to be a real Button frametype.
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints(true)
        row.highlight:SetTexture(1, 1, 1, 0.15)
        row.highlight:Hide()
        row:EnableMouse(false)

        rows[index] = row
    end
    return row
end

--- Renders ZGV.CurrentGuide/CurrentStep into the viewer frame: guide name, step number,
-- one row per visible goal (colored/icon'd by action type and completion status), the
-- progress bar (current step's goal-completion ratio -- whole-guide completion would need
-- Guide:GetCompletion, which isn't ported), and resizes the frame to fit the row count.
-- skipAutoAdvance: set by ZGV:StepForward/StepBack for the frame drawn right after moving, so
-- the landing step stays put for that render; later renders are held back by ZGV.pause
-- (see ZGV:StepForward) instead.
function ZGV:UpdateFrame(skipAutoAdvance)
    local content = ZygorGuidesViewerNGFrameContent

    if not ZGV.CurrentGuide or not ZGV.CurrentStep then
        ZygorGuidesViewerNGFrameGuideNameBarText:SetText("")
        ZygorGuidesViewerNGFrameNavBarStepText:SetText("")
        ZygorGuidesViewerNGFrameNavBarPrevButton:Disable()
        ZygorGuidesViewerNGFrameNavBarNextButton:Disable()
        for i, row in ipairs(rows) do row:Hide() end
        ZygorGuidesViewerNGFrameProgressBar:SetValue(0)
        ZGV:ShowMarkers({})
        ZGV.ActionBar:Update()
        return
    end

    -- Always refresh every goal's status (Step:IsComplete calls goal:UpdateStatus on all of
    -- them) so the render below is never stale -- skipAutoAdvance only controls whether we
    -- act on the result (see ZGV:StepForward/StepBack), not whether it gets computed. It must
    -- not be short-circuited on skipAutoAdvance, or manual navigation never refreshes statuses.
    local stepDone = ZGV.CurrentStep:IsComplete()
    if not stepDone then ZGV.pause = nil end
    if not skipAutoAdvance and not ZGV.pause and stepDone then
        ZGV:StepForward("auto")
        return
    end

    ZygorGuidesViewerNGFrameGuideNameBarText:SetText(ZGV.CurrentGuide.title_short)
    ZygorGuidesViewerNGFrameNavBarStepText:SetText(tostring(ZGV.CurrentStepNum))
    -- Next stays enabled on the last step: StepForward continues into the guide's next= guide,
    -- or opens the guide selection when there is none.
    if ZGV.CurrentStepNum > 1 then
        ZygorGuidesViewerNGFrameNavBarPrevButton:Enable()
    else
        ZygorGuidesViewerNGFrameNavBarPrevButton:Disable()
    end
    ZygorGuidesViewerNGFrameNavBarNextButton:Enable()

    -- Sticky reminders (stickystart/stickystop/step-level sticky -- see Parser.lua/
    -- Guide:Parse) attached to the current step, rendered as extra rows appended after its
    -- own goals. Their completion is independent of the current step's own (they're
    -- reminders carried over from OTHER steps), so they're excluded from the
    -- total/complete/waypoint bookkeeping below (see RenderGoal's isMainStep param).
    ZGV.CurrentStickies = ZGV:GetStickiesAt(ZGV.CurrentStepNum)

    local y = 0
    local rowIndex = 0
    local waypointGoal
    -- A step whose goals are all done (navigated back to) still points at its first goal with
    -- coordinates, as ZygorGuidesViewerClassic's CycleWaypoint skips only impossible goals.
    local doneWaypointGoal

    -- Multiple active stickies often each carry their own "kill <mob>" goal pointing at the
    -- exact same mob (e.g. two separate collection stickies that both need the same trash
    -- mob dead first) -- rendering that twice back to back is just noise, so the first one
    -- wins and later duplicates are skipped, leaving their own (distinct) collect-progress
    -- rows underneath. Scoped to "kill" specifically -- this is the confirmed real-world
    -- case, not a general goal-text dedup.
    local seenKillGoals = {}

    -- Every location of the current step, shown as map markers (ZGV:ShowMarkers).
    local markerPoints = {}

    -- Renders one goal as a row; a goal with coordinates gets a hover tooltip and
    -- click-to-retarget the TomTom arrow. isMainStep gates whether this goal can drive the
    -- auto-waypoint pick and the map markers -- sticky goals are for-your-information only,
    -- never the primary navigation target.
    local function RenderGoal(goal, isMainStep)
        local status = goal.status
        if status == "hidden" then return end

        -- The waypoint pick and the map markers do not depend on the goal having a row of
        -- its own.
        if isMainStep and goal.mapname and goal.x and goal.y and not goal.force_noway then
            if status ~= "complete" then
                waypointGoal = waypointGoal or goal
            else
                doneWaypointGoal = doneWaypointGoal or goal
            end
            local title = goal:GetText()
            tinsert(markerPoints, { mapname = goal.mapname, x = goal.x, y = goal.y, title = title })
            if goal.ways then
                for i = 2, table.getn(goal.ways) do
                    local way = goal.ways[i]
                    tinsert(markerPoints, { mapname = way.mapname, x = way.x, y = way.y, title = title })
                end
            end
        end

        local goalText = goal:GetText()

        -- A goal with empty text (a bare "'" in the guide) still counts for completion, but
        -- gets no row unless it has a tip to show.
        if goalText == "" and not goal.tip then return end

        if goal.action == "kill" then
            if seenKillGoals[goalText] then return end
            seenKillGoals[goalText] = true
        end

        rowIndex = rowIndex + 1
        local row = GetRow(content, rowIndex)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

        local color = ROW_COLOR_INCOMPLETE
        if status == "complete" then
            color = ROW_COLOR_COMPLETE
        elseif status == "pending" or status == "impossible" then
            -- Still rendered (unlike "hidden"): the player should see the goal waiting,
            -- it is just not actionable right now.
            color = ROW_COLOR_UNAVAILABLE
        elseif status == "passive" then
            color = ROW_COLOR_PASSIVE
        end
        if color == ROW_COLOR_INCOMPLETE and goal.numneeded and goal.numneeded > 1 then
            local r, g, b = ProgressColor((goal.numdone or 0) / goal.numneeded)
            row.bg:SetTexture(r, g, b, color[4])
        else
            row.bg:SetTexture(color[1], color[2], color[3], color[4])
        end
        if color == ROW_COLOR_UNAVAILABLE then
            row:SetAlpha(ROW_ALPHA_UNAVAILABLE)
        else
            row:SetAlpha(1)
        end

        local icon = ROW_ICONS[goal.action]
        if icon then
            row.icon:SetTexture(icon)
            row.icon:Show()
        else
            row.icon:Hide()
        end

        -- Manual word wrap (see WrapText above): wrap the main text and the tip ourselves,
        -- then size the row from the resulting line counts. TEXT_HEIGHT/TIP_HEIGHT are the
        -- per-line pixel heights -- hardcoded because GetStringHeight is nil here.
        local text, textLines = WrapText(row.text, goalText, TEXT_WIDTH)
        row.text:SetText(text)

        local textBottom = TEXT_TOP + textLines * TEXT_HEIGHT
        local rowHeight = math.max(ROW_HEIGHT, textBottom + 2)
        if goal.tip then
            local tip, tipLines = WrapText(row.tip, goal.tip, TEXT_WIDTH)
            row.tip:SetText(tip)
            -- The text can now be several lines, so re-anchor the tip below its actual
            -- bottom rather than the fixed single-line offset GetRow set.
            row.tip:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, -(textBottom + TIP_GAP))
            row.tip:Show()
            rowHeight = textBottom + TIP_GAP + tipLines * TIP_HEIGHT + 2
        else
            row.tip:Hide()
        end
        row:SetHeight(rowHeight)

        -- "Click Here to Continue |confirm": clicking the row itself flips
        -- manually_confirmed, which GOALTYPES['confirm'].iscomplete then reports as done.
        --
        -- Any other goal with coordinates is clickable, as in ZygorGuidesViewerClassic: a
        -- click points the arrow at it (ZGV.ManualWaypoint, below) and the hover tooltip says
        -- where it is. The step's other locations stay on the map as markers.
        local hasCoords = status ~= "complete" and goal.mapname and goal.x and goal.y
            and not goal.force_noway

        if goal.action == "confirm" and status ~= "complete" then
            row:EnableMouse(true)
            row.highlight:Show()
            row:SetScript("OnMouseUp", function()
                goal.manually_confirmed = true
                -- A choice with a |next jumps right away, as in ZygorGuidesViewerClassic, even
                -- on a step reached by browsing back.
                if goal.next then ZGV.pause = nil end
                ZGV:UpdateFrame()
            end)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
        elseif hasCoords then
            row:EnableMouse(true)
            row.highlight:Show()
            row:SetScript("OnMouseUp", function()
                ZGV.ManualWaypoint = { goal = goal }
                ZGV:SetWaypoint(goal.mapname, goal.x, goal.y, goal:GetText(), goal.dist, goal.waypoint_notravel)
            end)
            row:SetScript("OnEnter", function()
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                GameTooltip:AddLine(goal:GetText())
                GameTooltip:AddLine(string.format("%s %.1f, %.1f", goal.mapname, goal.x * 100, goal.y * 100), 1, 1, 1)
                GameTooltip:AddLine("Click to point the arrow here", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            row:EnableMouse(false)
            row.highlight:Hide()
            row:SetScript("OnMouseUp", nil)
            row:SetScript("OnEnter", nil)
            row:SetScript("OnLeave", nil)
        end

        row:Show()
        y = y + rowHeight
    end

    -- The current step's own goals render first, then the stickies attached to it, as
    -- ZygorGuidesViewerClassic orders them.
    for i, goal in ipairs(ZGV.CurrentStep.goals) do
        RenderGoal(goal, true)
    end

    -- Stickies from one area often repeat the same plain text line ("You can find more around
    -- [x,y]") after each of their goals. Such a line is shown once, at its last occurrence
    -- among the stickies, and not at all when the current step already shows it. The text
    -- includes the rendered coordinates, so lines pointing at different spots all stay.
    if ZGV.CurrentStickies and table.getn(ZGV.CurrentStickies) > 0 then
        local shownText = {}
        for _, goal in ipairs(ZGV.CurrentStep.goals) do
            if goal.action == "text" and goal.status ~= "hidden" then
                shownText[goal:GetText()] = true
            end
        end
        local lastStickyText = {}
        for _, stickystep in ipairs(ZGV.CurrentStickies) do
            for _, goal in ipairs(stickystep.goals) do
                if goal.action == "text" and goal.status ~= "hidden" then
                    lastStickyText[goal:GetText()] = goal
                end
            end
        end

        if rowIndex > 0 then y = y + 4 end
        for _, stickystep in ipairs(ZGV.CurrentStickies) do
            for _, goal in ipairs(stickystep.goals) do
                if goal.action ~= "text" or goal.status == "hidden" then
                    RenderGoal(goal, false)
                else
                    local text = goal:GetText()
                    if not shownText[text] and lastStickyText[text] == goal then
                        RenderGoal(goal, false)
                    end
                end
            end
        end
    end

    for i = rowIndex + 1, table.getn(rows) do rows[i]:Hide() end

    -- Whole-guide progress (steps done / total steps), not just the current step's goals --
    -- re-walks every step on each render, which could get slow on a very long guide; revisit
    -- with caching if that's noticeable.
    local guideSteps = ZGV.CurrentGuide.steps
    local guideTotal = table.getn(guideSteps)
    local guideComplete = 0
    for i, s in ipairs(guideSteps) do
        if s:IsComplete() then guideComplete = guideComplete + 1 end
    end
    ZygorGuidesViewerNGFrameProgressBar:SetValue(guideTotal > 0 and (guideComplete / guideTotal) or 0)

    -- A goal clicked in the viewer (see RenderGoal's clickable rows above) wins over the
    -- automatic pick, but only while it still points at a goal that's
    -- actually still visible right now (either the current step's own, or a currently-
    -- relevant sticky's -- NOT just the current step: a sticky goal's parentStep is some
    -- OTHER step by definition, so checking only against ZGV.CurrentStep rejected every
    -- sticky-row click the moment anything else triggered a re-render, which could happen
    -- almost immediately -- confirmed by the user as "clicking doesn't work" specifically on
    -- sticky rows) and isn't complete yet, unless no goal with coordinates is left to do (a
    -- finished step navigated back to) -- otherwise (new step, or the goal got completed) fall
    -- back to the automatic pick.
    local function IsGoalCurrentlyVisible(goal)
        if goal.parentStep == ZGV.CurrentStep then return true end
        if ZGV.CurrentStickies then
            for _, stickystep in ipairs(ZGV.CurrentStickies) do
                if goal.parentStep == stickystep then return true end
            end
        end
        return false
    end

    local manual = ZGV.ManualWaypoint
    if manual and manual.goal and IsGoalCurrentlyVisible(manual.goal)
        and (manual.goal.status ~= "complete" or not waypointGoal) then
        local goal = manual.goal
        ZGV:SetWaypoint(goal.mapname, goal.x, goal.y, goal:GetText(), goal.dist, goal.waypoint_notravel)
    elseif waypointGoal or doneWaypointGoal then
        ZGV.ManualWaypoint = nil
        local goal = waypointGoal or doneWaypointGoal
        ZGV:SetWaypoint(goal.mapname, goal.x, goal.y, goal:GetText(), goal.dist, goal.waypoint_notravel)
    elseif ZGV.CurrentStep.waypath then
        -- A step whose goals carry no coordinates can still have a patrol path to walk.
        ZGV.ManualWaypoint = nil
        ZGV:FollowPath(ZGV.CurrentStep.waypath)
    else
        ZGV.ManualWaypoint = nil
        ZGV:ClearWaypoint()
    end
    ZGV:ShowMarkers(markerPoints)
    ZGV.ActionBar:Update()

    local contentHeight = math.max(y, ROW_HEIGHT)
    local chromeHeight = ZygorGuidesViewerNGFrameTitleBar:GetHeight()
        + ZygorGuidesViewerNGFrameGuideNameBar:GetHeight()
        + ZygorGuidesViewerNGFrameNavBar:GetHeight()
        -- 4: the progress bar's 2px inset from the frame's bottom edge, plus the same gap
        -- between it and the last goal row (both set in the .xml).
        + ZygorGuidesViewerNGFrameProgressBar:GetHeight() + 4
    ZygorGuidesViewerNGFrame:SetHeight(chromeHeight + contentHeight)
end

-- GOALTYPES['ding']/['level']'s progress (UnitXP("player") vs the goal's target) only
-- changes on XP gain, which none of UpdateFrame's other triggers (QUEST_LOG_UPDATE in
-- QuestTracking.lua, BAG_UPDATE in Item-Upgrades.lua, GOSSIP_CLOSED, navigation) cover.
-- PLAYER_LEVEL_UP is not registered here: Item-Upgrades.lua already registers it on ZGV, and
-- AceEvent-3.0 keeps one handler per (object, event) pair, so a second RegisterEvent would
-- replace that one. PLAYER_XP_UPDATE also fires around a level-up.
function ZGV:OnPlayerXPChanged()
    ZGV:UpdateFrame()
end
ZGV:RegisterEvent("PLAYER_XP_UPDATE", "OnPlayerXPChanged")

-- subzone()/zone() conditions change with the player's position, warlockpet() with the pet,
-- learnspell/learnpetspell goals with the player's and the pet's spellbook.
function ZGV:OnZoneChanged()
    ZGV:UpdateFrame()
end
ZGV:RegisterEvent("ZONE_CHANGED", "OnZoneChanged")
ZGV:RegisterEvent("ZONE_CHANGED_INDOORS", "OnZoneChanged")
ZGV:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")

function ZGV:OnPlayerPetChanged()
    ZGV:UpdateFrame()
end
ZGV:RegisterEvent("UNIT_PET", "OnPlayerPetChanged")
ZGV:RegisterEvent("PET_BAR_UPDATE", "OnPlayerPetChanged")
ZGV:RegisterEvent("SPELLS_CHANGED", "OnPlayerPetChanged")
