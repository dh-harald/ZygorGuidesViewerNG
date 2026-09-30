-- Talent Advisor: build registration and resolving a build against the client's talents.
--
-- A build is a list of talent points in the order they are learned, one {tree, tier, column}
-- entry per point, all 1-based. The tree is counted in the standard 1.12 tab order (TREES
-- below); the client's own tab order is not assumed to match it. Positions are resolved to
-- the client's own tab and talent indexes at runtime, by the
-- tree's background file and GetTalentInfo's tier and column, so a build depends on neither
-- the tab or index order nor the language of the client. Optional fields of the build table:
--   source    where the build comes from (shown in the options)
--   gearspec  the stat weight profile the Gear Advisor should use while the build is active
--   next      title of the build to switch to (after a respec) once this one is complete

local ZTA = {}
ZGV.TalentAdvisor = ZTA

-- "CLASS Title" -> build, and the keys in registration order for the options dropdown.
ZTA.registeredBuilds = {}
ZTA.buildKeys = {}

function ZGV:RegisterTalentBuild(class, title, build)
    if type(class) ~= "string" or type(title) ~= "string" or type(build) ~= "table" then return end
    local key = class .. " " .. title
    if not ZTA.registeredBuilds[key] then table.insert(ZTA.buildKeys, key) end
    ZTA.registeredBuilds[key] = {
        class = class,
        title = title,
        points = build,
        source = build.source,
        gearspec = build.gearspec,
        next = build.next,
    }
end

-- Each class's trees in the standard 1.12 tab order, by the tree's background file name
-- (GetTalentTabInfo's 4th return).
local TREES = {
    WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
    PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
    HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
    ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
    PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
    SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
    MAGE = { "MageArcane", "MageFire", "MageFrost" },
    WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
    DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
}

-- "PaladinCombat" from "Interface\TalentFrame\PaladinCombat-TopLeft.blp", lower-cased.
local function BareBackground(background)
    local bare = string.gsub(background, "^.*[/\\]", "")
    bare = string.gsub(bare, "%.%a+$", "")
    bare = string.gsub(bare, "%-%a+$", "")
    return string.lower(bare)
end

-- The standard tree number of the client's tab; the tab index itself when its background
-- is not one the table knows.
local function StandardTree(class, tab)
    local _, _, _, background = GetTalentTabInfo(tab)
    local trees = TREES[class]
    if trees and type(background) == "string" then
        local bare = BareBackground(background)
        for n, name in ipairs(trees) do
            if string.lower(name) == bare then return n end
        end
    end
    return tab
end

-- "tree,tier,column" (standard tree number) -> { tab, talent index }, from the client. nil
-- while the client has no talent data yet (early in the login), in which case the caller
-- retries later.
function ZTA:GetTalentMap()
    if self.talentMap then return self.talentMap end
    if not GetTalentInfo(1, 1) then return nil end
    local _, class = UnitClass("player")
    local map = {}
    for tab = 1, GetNumTalentTabs() do
        local tree = StandardTree(class, tab)
        for i = 1, GetNumTalents(tab) do
            local name, _, tier, column = GetTalentInfo(tab, i)
            if name and tier and column then
                map[tree .. "," .. tier .. "," .. column] = { tab, i }
            end
        end
    end
    self.talentMap = map
    return map
end

-- Returns the build as a list of {tab, talent index} points, or nil and an error message.
function ZTA:ResolveBuild(build, map)
    local resolved = {}
    local points = build.points
    for n = 1, table.getn(points) do
        local p = points[n]
        local found = type(p) == "table" and p[1] and p[2] and p[3] and map[p[1] .. "," .. p[2] .. "," .. p[3]]
        if not found then
            if type(p) ~= "table" then
                return nil, string.format("Entry %d is not a {tree, tier, column} position.", n)
            end
            return nil, string.format("Entry %d: there is no talent in tree %s, tier %s, column %s.",
                n, tostring(p[1]), tostring(p[2]), tostring(p[3]))
        end
        table.insert(resolved, { found[1], found[2] })
    end
    return resolved
end
