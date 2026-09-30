local Guide = {}
local GuideFuncs = {}

ZGV.GuideProto = Guide
ZGV.GuideFuncs = GuideFuncs

local GuideProto_mt = {__index=Guide}

Guide.Types = {
    LEVELING = 1,
    LOREMASTER = 2,
    DAILIES = 3,
    EVENTS = 4,
    DUNGEONS = 5,
    GEAR = 5,
    PROFESSIONS = 6,
    ACHIEVEMENTS = 7,
    GOLD = 8,
    PETSMOUNTS = 9,
    TITLES = 10,
    REPUTATIONS = 11,
    MACROS = 12,
    TEST = 13,
    MISC = 14,
}

Guide.SubTypes = {
    TRI = 0,
    CAT = 1,
    MOP = 2,
    WOD = 3,
    LEG = 4,
    BFA = 5,
    SHA = 6,
    DRA = 7,

    CLA = 1,
    BCC = 2,
    WLK = 3,
}

Guide.Sides = {
    A = 1,
    H = 2,
}

function Guide:New(title, header, data)
    local path, tit = string.match(title, "^(.*)\\+(.-)$")
    if not path then
        path = title
    end
    local guidetype = string.match(path, "^(.-)\\") or path

    if not data then
        header, data = {}, header
    end

    if type(header.hideif) == "boolean" and header.hideif then
        return nil
    end
    -- header.hideif as a function needs ZGV.Parser.ConditionEnv, which isn't ported yet.

    ZGV.registeredguides_count = ZGV.registeredguides_count + 1

    local guide = {
        title=title,
        title_short=tit or title,
        rawdata=data,
        headerdata=header,
        num = ZGV.registeredguides_count,
        parsed=nil,
        fully_parsed=nil,
        type=guidetype,
        subtype=ZGV.GuideMenuTier,
        guidepath=path,
        -- condition_suggested_raw is what GetStatus's suggested-guide gate actually checks
        -- (see DoCond below) -- deliberately not copying header.class/startlevel/endlevel/
        -- sugGroup here, since no guide in the shipped data ever sets them (confirmed by
        -- grepping both guide files), unlike condition_suggested/next which are used
        -- throughout.
        condition_suggested = header.condition_suggested,
        condition_suggested_raw = header.condition_suggested ~= nil,
        condition_visible = header.condition_visible,
        next = header.next,
    }

    ZGV.RegisteredGuidesTitles[title]=true
    setmetatable(guide,GuideProto_mt)

    return guide
end

function Guide:Load(step)
        ZGV:SetGuide(self,step)
end

function Guide:Unload()
        self.steps=nil
        self.fully_parsed=nil
        self.rawdata_full=nil
        collectgarbage("step",100)
end

function Guide:Parse()
        if self.fully_parsed then return true end
        if self.parse_failed then return nil end

        local ok, err, linenum, linedata = ZGV.Parser:ParseEntry(self)
        if not ok then
                ZGV:Print("ERROR parsing guide '"..self.title.."': "..(err or "?").." (line "..(linenum or "?")..": "..(linedata or "")..")")
                self.parse_failed = true
                return nil
        end

        self.steplabels = {}
        for si, step in ipairs(self.steps) do
                local label = step.label
                if label then
                        if not self.steplabels[label] then self.steplabels[label] = {} end
                        tinsert(self.steplabels[label], si)
                end
        end

        -- render sticky_labels (raw label strings from parsing) into step.stickies
        -- (actual step object references), now that every step/label exists.
        for si, step in ipairs(self.steps) do
                if step.sticky_labels then
                        step.stickies = {}
                        for i, stickylabel in ipairs(step.sticky_labels) do
                                if stickylabel ~= step.label then
                                        local stickynums = self.steplabels[stickylabel]
                                        local stickystep = stickynums and self.steps[stickynums[1]]
                                        if stickystep then
                                                tinsert(step.stickies, stickystep)
                                        end
                                end
                        end
                end
        end

        return true
end

function Guide:GetStep(num_or_label)
        if not self.steps or not self.steplabels then return end
        num_or_label = self.steplabels[num_or_label] or tonumber(num_or_label)
        if type(num_or_label) == "table" then num_or_label = num_or_label[1] end
        return self.steps[num_or_label]
end

-- Minimal, deliberately narrow condition environment for guide-header condition_suggested/
-- condition_suggested_race closures (e.g. "condition_suggested=function() return
-- raceclass('Human') and level <= 12 end") -- NOT a general port of the reference source's
-- ZGV.Parser.ConditionEnv (that's a much bigger, still-unported DSL condition evaluator, see
-- Parser.lua's header comment). raceclass/completedq/level are exactly and only the three
-- free identifiers actually referenced across every condition_suggested*/condition_suggested
-- closure in the shipped guide data (confirmed by grepping both guide files) -- real globals
-- because that's what the guide data's closures were authored expecting to find.
function raceclass(v)
        local _, race = UnitRace("player")
        if type(v) == "table" then
                for _, name in ipairs(v) do
                        if name == race then return true end
                end
                return false
        end
        return v == race
end

function completedq(questid)
        return ZGV.db.char.quests[questid] and true or false
end

function Guide:DoCond(which, p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10)
        local whichcond = which and self['condition_'..which]
        if which and whichcond then
                -- handle "links": condition_valid="suggested"
                if type(whichcond)=="string" and whichcond~=which and self['condition_'..whichcond] then
                        self['condition_'..which]=self['condition_'..whichcond]
                end
                level = ZGV:GetPlayerPreciseLevel()
                local isOK,ret = pcall(self['condition_'..which],self, p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10)
                if isOK then
                        return ret,ret and "" or self['condition_'..which..'_msg']
                else
                        ZGV:Print("ERROR parsing condition for guide:\n"..self.title.."\n"..(self['condition_'..which.."_raw"] or "(code)").."\nError: "..ret)
                        return false,"ERROR: "..(self['condition_'..which..'_msg'] or "")
                end
        end

        -- no condition to check? improvise from attributes...

        if which=="valid" then
                -- Leveling-only scope: only class gating applies. Vanilla has no talent
                -- specializations, so there's no spec check here (unlike the retail source).
                if self.class then
                        local _, kclass = UnitClass("player")
                        if kclass ~= self.class then
                                return false, "The "..self.class.." class is required."
                        end
                end

                if self.startlevel then
                        return ZGV:GetPlayerPreciseLevel()>=self.startlevel,"Level "..ZGV.FormatLevel(self.startlevel).." or higher is required."
                end
                -- If above is ok
                return true
        elseif which=="suggested" and self.startlevel and self.type=="LEVELING" then
                local level=ZGV:GetPlayerPreciseLevel()
                return level>=self.startlevel and level<(self.endlevel or 999)
        elseif which=="outleveled" and self.endlevel then
                return ZGV:GetPlayerPreciseLevel()>=self.endlevel,"Level "..ZGV.FormatLevel(self.endlevel).." passed."
        elseif which=="end" and self.endlevel then
                return ZGV:GetPlayerPreciseLevel()>=self.endlevel,"Level "..ZGV.FormatLevel(self.endlevel).." reached."
        end
end

function Guide:GetStatus(detailed)
        local pass,msg

        pass, msg = self:DoCond("valid")
        if not pass then return "INVALID", msg end

        -- TODO: once completion tracking (GetCompletion) is ported, re-add:
        -- if detailed and self:GetCompletion()==1 then return "COMPLETE" end

        pass, msg = self:DoCond("outleveled")
        if pass then return "OUTLEVELED", msg end

        pass, msg = self:DoCond("end")
        if pass then return "COMPLETE", msg end

        msg="" -- TODO it's a bug, we ask the end condition and we're reusing its value even if the guide isnt complete

        if self.condition_suggested_raw or self.type=="LEVELING" then
                pass,msg = self:DoCond("suggested")
                if pass then return "SUGGESTED" end
        end

        return "VALID",msg
end

-- A guide whose header condition_visible is not true is left out of the guide list, as in
-- ZygorGuidesViewerClassic's guide menu (the Startup Guide Wizard has one that is always false).
function Guide:IsListed()
        if not self.condition_visible then return true end
        local ok, visible = pcall(self.condition_visible)
        return ok and visible == true
end

function Guide:GetParentFolder()
        local path, guide = string.match(self.title, "^(.+)\\(.-)$")
        local _, parent = string.match(path, "^(.+)\\(.-)$")
        return parent, path
end

function Guide:ToggleFavourite()
        if ZGV.db.char.favourites[self.title] then
                ZGV.db.char.favourites[self.title] = nil
        else
                ZGV.db.char.favourites[self.title] = true
        end
end

function Guide:IsFavourite()
        return ZGV.db.char.favourites[self.title]
end

function Guide:tostring()
        return self.title_short
end