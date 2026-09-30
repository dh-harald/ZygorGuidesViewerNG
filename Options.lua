-- The options table and the options window.
--
-- The root page holds no options; every option lives in a sub-group
-- (ZGV.ConfigTable.args.<group>), which LibConfig-1.0 and AceConfigDialog-3.0 both show as
-- a page of its own, nested under the addon's entry in the sidebar tree.

-- ZGV.registeredguides is fully populated at addon-load time (every guide file's
-- RegisterGuide call runs before OnInitialize/OnEnable) and never changes after that, so
-- this only ever needs building once instead of on every dropdown open (168 guides today --
-- rebuilding the same table from scratch each time was real, avoidable overhead).
local guideTitlesCache

-- Travel System options (Pointer.lua). LibRover:UpdateConfig maps these profile keys (defaults
-- in ZGV:OnInitialize) onto its own config; UpdateNow re-plans a running route with them.
local function ApplyTravelConfig()
    ZGV.LibRover:UpdateConfig(ZGV.db.profile)
    ZGV.LibRover:UpdateNow()
end

local function TravelHidden() return not ZGV.LibRover end
local function TravelDisabled() return not ZGV.db.profile.pathfinding end

local function TravelMethodToggle(key, order, name, desc)
    return {
        order = order,
        type = "toggle",
        name = name,
        desc = desc,
        disabled = TravelDisabled,
        get = function(info) return ZGV.db.profile[key] end,
        set = function(info, value)
            ZGV.db.profile[key] = value
            ApplyTravelConfig()
        end,
    }
end

-- Gear Advisor spec choice (Item-ItemScore.lua): "_" is the class's own weight table, every
-- other value a spec of ZGV.GearWeightsBySpec.
local function GearActiveBuild()
    local _, class = UnitClass("player")
    return ZGV:GetGearActiveBuild(class)
end

local function GearSelectedBuild()
    local _, class = UnitClass("player")
    local selected = ZGV.db.char.gear_selected_build
    local specs = ZGV.GearWeightsBySpec[class]
    if selected == "_" or (selected and specs and specs[selected]) then return selected end
    return GearActiveBuild()
end

local function GearSpecValues()
    local _, class = UnitClass("player")
    local values = { ["_"] = "Default (class)" }
    for spec, name in pairs(ZGV.GearSpecNames[class] or {}) do values[spec] = name end
    return values
end

-- Exposed on ZGV rather than kept local: OnInitialize registers it through LibConfig-1.0 on
-- vanilla and AceConfig-3.0 on Wrath, and a client-specific file can extend it in place.
ZGV.ConfigTable = {
    name = "ZygorGuidesViewerNG Options",
    type = "group",
    args = {
        intro = {
            order = 1,
            type = "description",
            name = "The options are grouped into the sections under this entry on the left.",
        },

        viewer = {
            order = 10,
            type = "group",
            name = "Guide Viewer",
            args = {
                guideSelection = {
                    order = 1,
                    type = "select",
                    name = "Select Guide",
                    desc = "Choose a guide from the list to load.",
                    get = function(info)
                        return ZGV.db.char.selectedGuide
                    end,
                    set = function(info, value)
                        ZGV:SetGuide(value)
                    end,
                    values = function()
                        if not guideTitlesCache then
                            guideTitlesCache = {}
                            for i, guide in ipairs(ZGV.registeredguides) do
                                if guide.title and guide:IsListed() then
                                    guideTitlesCache[guide.title] = guide.title
                                end
                            end
                        end
                        return guideTitlesCache
                    end,
                    width = "full",
                },
                skipImpossible = {
                    order = 2,
                    type = "toggle",
                    name = "Skip impossible steps",
                    desc = "While moving on after a completed step, or fast-forwarding with a right click on the next arrow, also pass steps that cannot be done, e.g. turning in a quest that is not in your log.",
                    get = function(info) return ZGV.db.profile.skipimpossible end,
                    set = function(info, value)
                        ZGV.db.profile.skipimpossible = value
                        ZGV:UpdateFrame()
                    end,
                },
            },
        },

        automation = {
            order = 20,
            type = "group",
            name = "Automation",
            args = {
                autoAcceptQuests = {
                    order = 1,
                    type = "toggle",
                    name = "Auto-accept quests",
                    desc = "Automatically accept quests the current guide step is asking for, once you've opened the NPC's dialog yourself.",
                    get = function(info) return ZGV.db.profile.autoAcceptQuests end,
                    set = function(info, value) ZGV.db.profile.autoAcceptQuests = value end,
                },
                autoCompleteQuests = {
                    order = 2,
                    type = "toggle",
                    name = "Auto-complete quests",
                    desc = "Automatically turn in quests the current guide step is asking for, once you've opened the NPC's dialog yourself.",
                    get = function(info) return ZGV.db.profile.autoCompleteQuests end,
                    set = function(info, value) ZGV.db.profile.autoCompleteQuests = value end,
                },
                autoCompleteRewardChoice = {
                    order = 3,
                    type = "select",
                    name = "Quest reward choice",
                    desc = "When a turned-in quest offers a choice of rewards, either pick the highest-scoring one automatically (using the same scoring as the Gear Advisor) or leave the choice screen open for you to pick manually.",
                    get = function(info) return ZGV.db.profile.autoCompleteRewardChoice end,
                    set = function(info, value) ZGV.db.profile.autoCompleteRewardChoice = value end,
                    values = { best = "Pick best automatically", manual = "Let me choose" },
                },
            },
        },

        -- ZygorGuidesViewerClassic's Action Buttons page, without its raid marker, trash
        -- button and bar scale options (see ActionBar.lua).
        actionbuttons = {
            order = 25,
            type = "group",
            name = "Action Buttons",
            args = {
                enable_actionbuttons = {
                    order = 1,
                    type = "toggle",
                    name = "Enable Action Buttons",
                    desc = "Offer buttons above the viewer for the current step's goals: use the item, target the NPC to talk to or the enemy to kill. \"/script ZGV:GoalAction()\" in a macro does the first button's action.",
                    get = function(info) return ZGV.db.profile.enable_actionbuttons end,
                    set = function(info, value)
                        ZGV.db.profile.enable_actionbuttons = value
                        ZGV.ActionBar:Update()
                    end,
                },
                enable_actionbar = {
                    order = 2,
                    type = "toggle",
                    name = "Enable Action Bar",
                    desc = "Show the buttons above the viewer. With the bar off, the key bindings and macros still work.",
                    disabled = function() return not ZGV.db.profile.enable_actionbuttons end,
                    get = function(info) return ZGV.db.profile.enable_actionbar end,
                    set = function(info, value)
                        ZGV.db.profile.enable_actionbar = value
                        ZGV.ActionBar:Update()
                    end,
                },
                typesHeader = {
                    order = 10,
                    type = "header",
                    name = "Button types:",
                },
                actionbar_quest = {
                    order = 11,
                    type = "toggle",
                    name = "Quest actions",
                    width = "full",
                    disabled = function() return not ZGV.db.profile.enable_actionbuttons end,
                    get = function(info) return ZGV.db.profile.actionbar_quest end,
                    set = function(info, value)
                        ZGV.db.profile.actionbar_quest = value
                        ZGV.ActionBar:Update()
                    end,
                },
                actionbar_talk = {
                    order = 12,
                    type = "toggle",
                    name = "Talk to NPC",
                    width = "full",
                    disabled = function() return not ZGV.db.profile.enable_actionbuttons end,
                    get = function(info) return ZGV.db.profile.actionbar_talk end,
                    set = function(info, value)
                        ZGV.db.profile.actionbar_talk = value
                        ZGV.ActionBar:Update()
                    end,
                },
                actionbar_kill = {
                    order = 13,
                    type = "toggle",
                    name = "Kill enemy",
                    width = "full",
                    disabled = function() return not ZGV.db.profile.enable_actionbuttons end,
                    get = function(info) return ZGV.db.profile.actionbar_kill end,
                    set = function(info, value)
                        ZGV.db.profile.actionbar_kill = value
                        ZGV.ActionBar:Update()
                    end,
                },
            },
        },

        travel = {
            order = 30,
            type = "group",
            name = "Travel System",
            hidden = TravelHidden,
            args = {
                pathfinding = {
                    order = 1,
                    type = "toggle",
                    name = "Enable Travel System",
                    desc = "Plan routes to the guide's waypoints through zone borders, known flight paths, boats, zeppelins, portals and the hearthstone.",
                    get = function(info) return ZGV.db.profile.pathfinding end,
                    set = function(info, value)
                        ZGV.db.profile.pathfinding = value
                        ZGV.LibRover:UpdateConfig(ZGV.db.profile)
                        -- the viewer re-sets its waypoint: routed, or straight with the travel system off
                        ZGV:StopRoute()
                        ZGV:UpdateFrame()
                    end,
                },
                travelMethodsHeader = {
                    order = 10,
                    type = "header",
                    name = "Travel methods",
                },
                travelusehs = TravelMethodToggle("travelusehs", 11, "Use Hearthstones",
                    "Let routes use the hearthstone when it is off cooldown."),
                traveluseitems = TravelMethodToggle("traveluseitems", 12, "Use items",
                    "Let routes use teleport items in your bags."),
                travelusespells = TravelMethodToggle("travelusespells", 13, "Use spells",
                    "Let routes use your teleport spells (mage teleports, Astral Recall)."),
                pathfinding_comfort = {
                    order = 20,
                    type = "select",
                    name = "Travel comfort preference",
                    desc = "Speed takes the fastest route; Comfort prefers flight paths over walking, and fewer changes of travel mode.",
                    disabled = TravelDisabled,
                    values = { [0] = "Speed", [1] = "Comfort" },
                    get = function(info) return ZGV.db.profile.pathfinding_comfort end,
                    set = function(info, value)
                        ZGV.db.profile.pathfinding_comfort = value
                        ApplyTravelConfig()
                    end,
                },
            },
        },

        maps = {
            order = 35,
            type = "group",
            name = "Maps",
            args = {
                maplines_enabled = {
                    order = 1,
                    type = "toggle",
                    name = "Enable ant trails",
                    desc = "Draw the travel route and the guide's patrol paths as lines on the world map and the minimap.",
                    get = function(info) return ZGV.db.profile.maplines_enabled end,
                    set = function(info, value) ZGV.db.profile.maplines_enabled = value end,
                },
            },
        },

        gear = {
            order = 40,
            type = "group",
            name = "Gear Advisor",
            args = {
                gearAdvisorEnabled = {
                    order = 1,
                    type = "toggle",
                    name = "Enable Gear Advisor",
                    desc = "Suggest equipping newly-acquired items that are a stat upgrade. Per-character -- only really useful while this character is still leveling.",
                    get = function(info) return ZGV.db.char.gearAdvisorEnabled end,
                    set = function(info, value) ZGV.db.char.gearAdvisorEnabled = value end,
                },
                gear_selected_build = {
                    order = 10,
                    type = "select",
                    name = "Score gear for spec:",
                    desc = "Pick a spec to see whether the Gear Advisor uses its stat weights. Choosing a talent build selects its spec here too.",
                    values = GearSpecValues,
                    get = function(info) return GearSelectedBuild() end,
                    set = function(info, value) ZGV.db.char.gear_selected_build = value end,
                },
                gearSpecActive = {
                    order = 11,
                    type = "description",
                    name = "This set is active.",
                    hidden = function() return GearSelectedBuild() ~= GearActiveBuild() end,
                },
                gearSpecUse = {
                    order = 12,
                    type = "execute",
                    name = "Use this set",
                    desc = "Score gear with this spec's stat weights from now on.",
                    hidden = function() return GearSelectedBuild() == GearActiveBuild() end,
                    func = function() ZGV:SetGearActiveBuild(GearSelectedBuild()) end,
                },
            },
        },

        talent = {
            order = 50,
            type = "group",
            name = "Talent Advisor",
            args = {
                zta_enabled = {
                    order = 1,
                    type = "toggle",
                    name = "Enable Talent Advisor",
                    desc = "Suggests which talents you should invest your talent points in on each level, for you to level optimally.",
                    get = function(info) return ZGV.db.profile.zta_enabled end,
                    set = function(info, value) ZGV.TalentAdvisor:SetEnabled(value) end,
                },
                buildHeader = {
                    order = 10,
                    type = "header",
                    name = "Player build",
                },
                build = {
                    order = 11,
                    type = "select",
                    name = "Select a build:",
                    desc = "The Advisor will keep suggesting talents to pick up as you progress, to ensure this build serves you optimally.",
                    disabled = function() return not ZGV.db.profile.zta_enabled end,
                    values = function()
                        local values = ZGV.TalentAdvisor:GetClassBuilds()
                        values["_"] = "No build selected"
                        return values
                    end,
                    get = function(info) return ZGV.db.char.zta_currentBuildKey end,
                    set = function(info, value) ZGV.TalentAdvisor:SetCurrentBuild(value) end,
                },
                zta_forcebuild = {
                    order = 12,
                    type = "toggle",
                    name = "Allow this build",
                    desc = "Allow this build. By default, it's wisest to avoid combining incompatible or broken builds. By forcing this, you're taking your own responsibility for what happens - you may end up with a ridiculous build.",
                    hidden = function()
                        local status = ZGV.TalentAdvisor.status
                        return not ZGV.db.profile.zta_forcebuild and not (status and status.code == "RED")
                    end,
                    get = function(info) return ZGV.db.profile.zta_forcebuild end,
                    set = function(info, value)
                        ZGV.db.profile.zta_forcebuild = value
                        ZGV.TalentAdvisor:UpdateSuggestions()
                        ZGV.TalentAdvisor:PlayTalented()
                        ZGV.TalentAdvisor.Popout_Update()
                    end,
                },
                buildStatus = {
                    order = 13,
                    type = "description",
                    name = function()
                        local ZTA = ZGV.TalentAdvisor
                        ZTA:EnsureLoaded()
                        ZTA:UpdateSuggestions()
                        return ZTA:GetStatusMessage()
                    end,
                },
                buildSource = {
                    order = 14,
                    type = "description",
                    name = function()
                        local build = ZGV.TalentAdvisor.currentBuildInfo
                        return build and build.source and ("Source: " .. build.source) or ""
                    end,
                },
                talentFrameHeader = {
                    order = 20,
                    type = "header",
                    name = "Talent Interface features",
                },
                zta_hints = {
                    order = 21,
                    type = "toggle",
                    name = "Show advice balloons",
                    desc = "Show advice as balloons indicating suggested talent upgrades:\n|cff00ff00+1|r ... |cff00ff00+5|r - upgrade this talent by # points,\n|cffff0000X|r - talent overdone, you have broken the build.",
                    get = function(info) return ZGV.db.profile.zta_hints end,
                    set = function(info, value)
                        ZGV.db.profile.zta_hints = value
                        ZGV.TalentAdvisor:CleanupTalentFrame()
                    end,
                },
                zta_preview = {
                    order = 22,
                    type = "toggle",
                    name = "Show selected build's talent ranks",
                    desc = "Display final talent ranks, according to the selected build, as numbers in the talent rank boxes:\n|cff00ff000|r/2 - upgrade this talent up to 2 ranks,\n2/2 - suggested rank reached,\n|cffff00003|r/2 - you have exceeded the suggested rank and broken the build.",
                    get = function(info) return ZGV.db.profile.zta_preview end,
                    set = function(info, value)
                        ZGV.db.profile.zta_preview = value
                        ZGV.TalentAdvisor:CleanupTalentFrame()
                    end,
                },
                zta_popup = {
                    order = 23,
                    type = "select",
                    name = "What shall we do when new talent points are available?",
                    desc = "Talent Advisor can pop up your talents frame or its own advice window, whenever new points are available for spending.",
                    values = {
                        [0] = "Nothing",
                        [1] = "Open the talents frame (for manual learning)",
                        [2] = "Open the advice window (for one-click learning)",
                    },
                    get = function(info) return ZGV.db.profile.zta_popup end,
                    set = function(info, value) ZGV.db.profile.zta_popup = value end,
                },
                zta_windowdocked = {
                    order = 24,
                    type = "toggle",
                    name = "Dock the advice window onto the Talent Interface",
                    desc = "When docked, the advice window appears and disappears with the Talent Interface, and opens with it while the selected build fits your talents.\nWhen not docked, it appears independently and can be moved anywhere.\nNote: you can just drag the advice window off the side of the Talent Interface to undock it, or back to dock it again.",
                    get = function(info) return ZGV.db.profile.zta_windowdocked end,
                    set = function(info, value)
                        ZGV.db.profile.zta_windowdocked = value
                        ZGV.TalentAdvisor.Popout_Hide()
                    end,
                },
            },
        },
    },
}

-- Opens the addon's options/settings window. This is the single call site that
-- needs a client branch: on vanilla the options are rendered by LibConfig-1.0
-- (the Blizzard Interface Options frame is broken on Unreal Azeroth); on Wrath
-- the native Interface Options frame still works, so we keep using it.
function ZGV:OpenOptions()
    if ZGV.IsWOTLK then
        InterfaceOptionsFrame_OpenToCategory("ZygorGuidesViewerNG")
    else
        LibStub("LibConfig-1.0"):OpenToCategory("ZygorGuidesViewerNG")
    end
end

-- The /zygor chat command, dispatched by AceConfigCmd-3.0. With no argument AceConfigCmd
-- prints the list of the arguments below.
ZGV.CommandTableName = "ZygorGuidesViewerNG"
ZGV.CommandTable = {
    name = "ZygorGuidesViewerNG",
    type = "group",
    args = {
        show = {
            order = 1,
            type = "execute",
            name = "Show/hide the guide viewer",
            func = function() ZGV:ViewerFrameToggle() end,
        },
        config = {
            order = 2,
            type = "execute",
            name = "Open the options window",
            func = function() ZGV:OpenOptions() end,
        },
        qqc = {
            order = 3,
            type = "execute",
            name = "Import completed quests from the server (needs server-side QueryQuestsCompleted support)",
            func = function() ZGV:QueryCompletedQuests() end,
        },
        help = {
            order = 4,
            type = "execute",
            name = "List these arguments",
            -- Nothing in AceConfigCmd-3.0 reads its info table after an execute handler
            -- returns, so the nested HandleCommand call is safe here.
            func = function()
                LibStub("AceConfigCmd-3.0").HandleCommand(ZGV, "zygor", ZGV.CommandTableName, "")
            end,
        },
    },
}
