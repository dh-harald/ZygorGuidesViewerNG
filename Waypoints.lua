-- TomTom integration for showing waypoints from a guide's goto/at coordinates (parsed in
-- Parser.lua into goal.mapname/x/y/dist, mapname resolved via Data/ZoneIDs.lua).
--
-- The installed TomTom build exposes the pre-rewrite (vanilla/wrath-era) API, confirmed by
-- reading its own source -- not the modern retail AddWaypoint/RemoveWaypoint surface. The
-- real entry point is
-- TomTom:AddMFWaypoint(continent, zoneNameOrNil, x, y, opts):
--   - pass continent=nil and the zone NAME as a string; it resolves the zone internally
--     via TomTom:GetZoneInfo(TomTom:CleanZoneName(zone)) (TomTom.lua ~line 865).
--   - x/y are 0..1 fractions, confirmed by TomTom's own source comment ("No need to
--     convert x and y because they're already 0-1 instead of 0-100", TomTom.lua ~line 923).
--   - opts.crazy = true auto-shows the big screen arrow (TomTom:SetArrowWaypoint).
--   - opts.arrivaldistance sets the arrival radius in yards -- this is what goal.dist
--     (parsed from the DSL's <dist/>dist suffix) feeds into. TomTom itself owns the
--     actual "has the player arrived" distance check once this is set; nothing here
--     re-implements that.
--   - AddMFWaypoint/LoadWayPoint return the same `uid` table used later to remove it.
--   - AddMFWaypoint(mapID, nil, x, y, opts) takes a LibHereBeDragons mapID instead of a zone
--     name (any first argument above 2); the travel route's legs come as mapIDs.
--   - opts.cleardistance is the radius at which TomTom clears the point by itself.
--
-- ZGV:UpdateFrame (ZygorGuidesViewerNG.lua) calls ZGV:SetWaypoint automatically for the
-- current step's first not-yet-done goal with coordinates. ZGV:TestWaypoint below is for
-- testing a specific guide/step without needing to actually select/navigate it.

local warnedMissing = false
local currentWaypoint
local lastArrow

-- Points TomTom's arrow at one spot, replacing the previous one. The spot is a LibHereBeDragons
-- mapID (TomTom:AddMFWaypoint(mapID, nil, ...), the travel route's legs) or, with mapID nil, a
-- zone name (the guide's own goal). TomTom never clears the point by itself (cleardistance 0,
-- unless cleardist says otherwise): on clearing it would point the arrow at the last waypoint in
-- its list, which is one of the step's map markers. Without x/y it only clears the arrow.
function ZGV:ShowArrow(mapID, mapname, x, y, title, arrivaldist, cleardist)
    if not (TomTom and TomTom.AddMFWaypoint) then
        if not warnedMissing then
            warnedMissing = true
            ZGV:Print("TomTom (or a compatible addon) is not installed, or doesn't expose AddMFWaypoint -- waypoints won't be shown.")
        end
        return
    end

    -- Remove the previous waypoint first -- otherwise every step change/re-render piles
    -- up another arrow instead of replacing the last one.
    if currentWaypoint and TomTom.RemoveWaypoint then
        TomTom:RemoveWaypoint(currentWaypoint, true)
        currentWaypoint = nil
    end
    lastArrow = nil

    if not x or not y or not (mapID or mapname) then return end

    currentWaypoint = TomTom:AddMFWaypoint(mapID, not mapID and mapname or nil, x, y, {
        title = title,
        crazy = true,
        arrivaldistance = arrivaldist,
        cleardistance = cleardist or 0,
        persistent = false,
        silent = true,
    })
    if currentWaypoint then
        lastArrow = { mapID = mapID, mapname = mapname, x = x, y = y, title = title,
            arrivaldist = arrivaldist, cleardist = cleardist }
    end
    return currentWaypoint
end

-- Map markers: every location of the current step at once, on the world map and the minimap, as
-- ZygorGuidesViewerClassic's ShowWaypoints shows them, while the arrow points at one of them.
-- They are plain TomTom waypoints without the arrow. points is a list of
-- { mapname, x, y, title }. The set is only rebuilt when a location changes (a changed title is
-- written into the existing waypoint, which TomTom reads when it shows the tooltip), and the
-- arrow's waypoint is then added again after the markers, so it stays the last one in TomTom's
-- list: that is the one TomTom returns the arrow to after its corpse arrow. While the player is
-- dead nothing changes, for the same reason.
local markers = {}
local markerKey

function ZGV:ShowMarkers(points)
    if not (TomTom and TomTom.AddMFWaypoint and TomTom.RemoveWaypoint) then return end
    if UnitIsDeadOrGhost("player") then return end

    local parts = {}
    for i, p in ipairs(points) do
        parts[i] = string.format("%s:%.4f:%.4f", p.mapname, p.x, p.y)
    end
    local key = table.concat(parts, "|")
    if key == markerKey then
        for i, uid in ipairs(markers) do
            if points[i] then uid.title = points[i].title end
        end
        return
    end
    markerKey = key

    for _, uid in ipairs(markers) do
        TomTom:RemoveWaypoint(uid, true)
    end
    markers = {}
    for _, p in ipairs(points) do
        local uid = TomTom:AddMFWaypoint(nil, p.mapname, p.x, p.y, {
            title = p.title,
            crazy = false,
            cleardistance = 0,
            persistent = false,
            silent = true,
        })
        if uid then tinsert(markers, uid) end
    end

    local a = lastArrow
    if a then
        ZGV:ShowArrow(a.mapID, a.mapname, a.x, a.y, a.title, a.arrivaldist, a.cleardist)
    end
end

-- The guide's waypoint for the current goal. With the travel system on, ZGV:RouteTo (Pointer.lua)
-- takes it over and points the arrow at the route's legs; otherwise, and for a |notravel goal
-- (notravel), it is one straight arrow. While the player is dead or a ghost the arrow is left
-- alone: TomTom points it at the corpse once, and any new waypoint would take it over.
function ZGV:SetWaypoint(mapname, x, y, title, dist, notravel)
    ZGV:StopPath()
    if UnitIsDeadOrGhost("player") then
        ZGV:StopRoute()
        return
    end
    if notravel then
        ZGV:StopRoute()
    elseif ZGV:RouteTo(mapname, x, y, title, dist) then
        return
    end
    return ZGV:ShowArrow(nil, mapname, x, y, title, dist)
end

-- A step without coordinates or a path drops the previous step's arrow, as ZygorGuidesViewerClassic's
-- ShowWaypoints clears before it points anywhere.
function ZGV:ClearWaypoint()
    ZGV:StopPath()
    ZGV:StopRoute()
    ZGV:ShowArrow()
end

-- Manual test hook: /run ZGV:TestWaypoint("Guide Title", stepnum)
-- Sets a waypoint on the first goal in that step that has coordinates.
function ZGV:TestWaypoint(guidetitle, stepnum)
    local guide = ZGV:GetGuideByTitle(guidetitle)
    if not guide then
        ZGV:Print("No such guide: "..tostring(guidetitle))
        return
    end

    if not guide.fully_parsed then guide:Parse() end

    local step = guide:GetStep(stepnum)
    if not step then
        ZGV:Print("No such step: "..tostring(stepnum))
        return
    end

    for i, goal in ipairs(step.goals) do
        if goal.mapname and goal.x and goal.y then
            return ZGV:SetWaypoint(goal.mapname, goal.x, goal.y, goal:GetText(), goal.dist, goal.waypoint_notravel)
        end
    end

    ZGV:Print("No goal with resolved map coordinates found in that step.")
end

-- Arriving at a goal's coordinates moves the arrow on to the next goal with coordinates, as
-- ZygorGuidesViewerClassic's Goal:CheckVisited and Step:CycleWaypointFrom do. Checked every
-- VISIT_CHECK_INTERVAL while the viewer is shown, for the current step's visible goals. A goal
-- is visited within its arrival distance ("<N"), within VISIT_DEFAULT_DIST yards without one,
-- or beyond N yards for ">N"; only on its own map (">N" also counts on any other map), and
-- never on a taxi. Only the moment of arrival counts. A red (incomplete) goal does not move the
-- arrow on arrival: it is checked again until it can. The arrow goes to the next goal after
-- the visited one in step order that has coordinates and is neither |noway, hidden nor
-- impossible; after the last one it stays on the visited goal.
local HBD = LibStub("LibHereBeDragons-1.0", true)
local VISIT_CHECK_INTERVAL = 0.1
local VISIT_DEFAULT_DIST = 3

local function IsVisited(goal, px, py, pm)
    if goal.visitmap == nil then
        goal.visitmap = HBD:GetMapIDFromZoneName(goal.mapname) or false
    end
    local gm = goal.visitmap
    if not gm then return false end
    if gm ~= pm then return goal.dist ~= nil and goal.dist < 0 end
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    local d = HBD:GetZoneDistance(pm, nil, px, py, gm, nil, goal.x, goal.y)
    if not d then return false end
    local dist = goal.dist or VISIT_DEFAULT_DIST
    if dist > 0 then return d <= dist end
    if dist < 0 then return d >= -dist end
    return false
end

local function NextWaypointGoal(step, from)
    for i = from.num + 1, table.getn(step.goals) do
        local goal = step.goals[i]
        local status = goal.status
        if goal.mapname and goal.x and goal.y and not goal.force_noway
            and status ~= "hidden" and status ~= "impossible" and status ~= "pending" then
            return goal
        end
    end
end

function ZGV:CheckVisitedGoals()
    local step = ZGV.CurrentStep
    if not (HBD and step) then return end
    if not (ZygorGuidesViewerNGFrame and ZygorGuidesViewerNGFrame:IsVisible()) then return end
    if UnitIsDeadOrGhost("player") then return end
    local px, py, pm = HBD:GetPlayerZonePosition()
    if not (px and pm) then return end

    for _, goal in ipairs(step.goals) do
        if goal.mapname and goal.x and goal.y and goal.status and goal.status ~= "hidden" then
            local visited = IsVisited(goal, px, py, pm)
            if visited and not goal.was_visited then
                if goal.status ~= "incomplete" then
                    goal.was_visited = true
                    local target = NextWaypointGoal(step, goal) or goal
                    ZGV.ManualWaypoint = { goal = target }
                    ZGV:SetWaypoint(target.mapname, target.x, target.y, target:GetText(), target.dist, target.waypoint_notravel)
                end
            else
                goal.was_visited = visited
            end
        end
    end
end

-- Called from ZGV:OnEnable.
function ZGV:StartVisitCheck()
    ZGV:ScheduleRepeatingTimer("CheckVisitedGoals", VISIT_CHECK_INTERVAL)
end
