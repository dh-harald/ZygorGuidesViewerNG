-- Travel system: LibTaxi-1.0 keeps the flight points this character knows in
-- ZGV.db.char.taxis (the "fpath" goal in Goal.lua reads that table), LibRover-1.0 is the route
-- finder built on it. Both are looked up optionally: without them the fpath goal never
-- completes, and the Travel System options (Options.lua) are hidden.

local LibTaxi = LibStub("LibTaxi-1.0", true)
local LibRover = LibStub("LibRover-1.0", true)
local HBD = LibStub("LibHereBeDragons-1.0", true)
ZGV.LibTaxi = LibTaxi
ZGV.LibRover = LibRover

-- Called from ZGV:OnEnable (PLAYER_LOGIN): LibTaxi reads UnitFactionGroup, which is nil
-- earlier, and LibRover's startup reads LibTaxi's flight points.
function ZGV:StartTravel()
    if not LibTaxi then return end
    ZGV:SeedInitialFlightPaths()
    LibTaxi:Startup(ZGV.db.char.taxis)
    ZGV:RegisterMessage("LibTaxi_KnowledgeChanged", "OnTaxiKnowledgeChanged")

    if not LibRover then return end
    LibRover:SetHost({ profile = ZGV.db.profile })
    LibRover:DoStartup()
end

-- A flight path learned or a flight master's map scanned: an fpath goal may be complete now.
function ZGV:OnTaxiKnowledgeChanged()
    ZGV:UpdateFrame()
end

-- Why a listed itinerary leaves this route node out, or nil when it shows it, as
-- ZygorGuidesViewerClassic's route list decides (the arrow still visits every node): the arrival half of a transport pair, and the
-- second half of a zone border pair, which stands on the same spot as the first with the same text.
local function ItinerarySkip(node, prevnode)
    if node.is_arrival and LibRover:GetCFG("strip_arrivals") then return "arrival" end
    if prevnode and node.text == prevnode.text and node.border == prevnode then return "border pair" end
end

-- The route the arrow currently follows: the guide's destination (key, mapID, mapname, x, y,
-- title, dist), the legs of the last path LibRover reported (legs, leg) and the leg timer.
local route

-- ZygorGuidesViewerClassic's arrival rules for a route node: a taxi, portal, ship or zeppelin
-- departure is never skipped by distance (LibRover re-plans once the player is on board), a
-- ship/zeppelin arrival counts from 100 yards, anything else from its own radius or 1 yard.
-- Returns radius, noskip.
local DEFAULT_LEG_RADIUS = 1
local function LegArrival(node)
    local mode, ntype = node.link and node.link.mode, node.type
    if ntype == "taxi" and mode ~= "taxi" then return node.radius or 5, true end
    if ntype == "portal" and mode ~= "portal" then return node.radius or 5, true end
    if ntype == "ship" or ntype == "zeppelin" then
        if mode ~= "ship" and mode ~= "zeppelin" then return node.radius or 5, true end
        return node.radius or 100
    end
    if node.noskip then return 5, true end
    return node.radius or DEFAULT_LEG_RADIUS
end

local function OnTaxi()
    return UnitOnTaxi and UnitOnTaxi("player") and true or false
end

-- A flight's landing leg counts as reached once the player is off the taxi: the flight sets the
-- player down a few yards from the node, which is further than its radius. The departure before
-- it is noskip, so this leg only becomes current once LibRover has re-planned on board.
local function Landed(node)
    return node.type == "taxi" and node.link and node.link.mode == "taxi" and not OnTaxi()
end

local function ShowDirect()
    route.legs, route.shown = nil, nil
    ZGV:ShowArrow(nil, route.mapname, route.x, route.y, route.title, route.dist)
end

-- Points the arrow at the current leg; the last leg is the guide's own waypoint, with the goal's
-- text and arrival distance. A re-plan that lands on the same node keeps the arrow as it is.
local function ShowLeg()
    local node = route.legs and route.legs[route.leg]
    if not node or node.type == "end" then
        if route.shown ~= "end" then
            ZGV:ShowArrow(nil, route.mapname, route.x, route.y, route.title, route.dist)
            route.shown = "end"
        end
        return
    end
    local text = node:GetTextAsItinerary()
    if route.shown == node and route.shownText == text then return end
    route.shown, route.shownText = node, text
    ZGV:ShowArrow(node.m, nil, node.x, node.y, text, (LegArrival(node)), 0)
end

-- Moves past every leg the player already stands on or has landed at (a noskip departure and the
-- last leg excepted), and answers whether it moved.
local function SkipReachedLegs()
    local moved = false
    local x, y, m = HBD:GetPlayerZonePosition()
    if not (x and m) then return false end
    while true do
        local node = route.legs and route.legs[route.leg]
        if not node or node.type == "end" then break end
        local radius, noskip = LegArrival(node)
        if noskip then break end
        local dist = HBD:GetZoneDistance(m, nil, x, y, node.m, nil, node.x, node.y)
        if not (Landed(node) or (dist and dist <= radius)) then break end
        route.leg = route.leg + 1
        moved = true
    end
    return moved
end

-- LibRover's answer, both to the first search and to every re-plan it makes on its own (the
-- player moved, changed zone, boarded or left a flight). Every node after the start is a leg,
-- as in ZygorGuidesViewerClassic's pointer.
local function PathFound(state, path, ext, reason)
    if not route or not ext or ext.token ~= route.key then return end
    if state == "success" then
        local legs = {}
        for i = 2, table.getn(path) do tinsert(legs, path[i]) end
        route.legs, route.leg = legs, 1
        SkipReachedLegs()
        ShowLeg()
    elseif state == "failure" or state == "arrival" then
        ShowDirect()
    end
end

local function RequestPath()
    LibRover:QueueFindPath(0, 0, 0, route.mapID, route.x, route.y, PathFound,
        { player = true, title = route.title, token = route.key })
end

-- Every half second: on reaching the current leg, move on to the next one and have LibRover
-- re-plan from here, as ZygorGuidesViewerClassic's pointer does.
function ZGV:CheckRouteLeg()
    if not (route and route.legs) then return end
    if SkipReachedLegs() then
        ShowLeg()
        if not OnTaxi() then LibRover:UpdateNow("quiet") end
    end
end

-- Takes over the guide's waypoint when the travel system can route to it, and answers whether it
-- did. The same destination again (UpdateFrame calls this on every render) keeps the route; only
-- a changed title or arrival distance (e.g. the goal's "(3/10)" progress) is passed on, and it
-- re-shows the arrow right away when the arrow points at the destination itself, since TomTom
-- sets an arrow's title only when the waypoint is added. Until the first path arrives, and
-- whenever none is found, the arrow points straight at the goal.
function ZGV:RouteTo(mapname, x, y, title, dist)
    local mapID = LibRover and HBD and x and y and mapname and ZGV.db.profile.pathfinding
        and LibRover:GetMapByNameFloor(mapname)
    if not mapID then
        ZGV:StopRoute()
        return false
    end

    local key = string.format("%d:%.4f:%.4f", mapID, x, y)
    if route and route.key == key then
        local changed = route.title ~= title or route.dist ~= dist
        route.title, route.dist = title, dist
        if changed and (not route.legs or route.shown == "end") then
            ZGV:ShowArrow(nil, route.mapname, route.x, route.y, title, dist)
        end
        return true
    end

    ZGV:StopRoute()
    route = { key = key, mapID = mapID, mapname = mapname, x = x, y = y, title = title, dist = dist }
    ShowDirect()
    RequestPath()
    route.timer = ZGV:ScheduleRepeatingTimer("CheckRouteLeg", 0.5)
    return true
end

function ZGV:StopRoute()
    if not route then return end
    ZGV:CancelTimer(route.timer)
    route = nil
    LibRover:Abort("route cleared", true)
end

-- Patrol paths (step.waypath, parsed from a step's "path" lines): the arrow walks the route point
-- by point, as ZygorGuidesViewerClassic's Pointer:GetNextInPath does, re-checked every 0.2 seconds
-- like its PointToNextTimer. Away from the path's zone the travel system routes to it first: to
-- the nearest point of a looped path, to the middle of an open one.
local follow

local PATH_DEFAULT_DIST = 30
local POINT_DEFAULT_RADIUS = 1

local function Dist(m1, x1, y1, m2, x2, y2)
    return HBD:GetZoneDistance(m1, nil, x1, y1, m2, nil, x2, y2)
end

local function anglenormal(a)
    while a > 6.2832 do a = a - 6.2832 end
    while a < 0 do a = a + 6.2832 end
    return a
end
local function anglexy(ax, ay, bx, by)
    local a = math.atan2(bx - ax, (ay - by) * 0.66)
    if a > 0 then a = -6.2832 + a end
    return anglenormal(a)
end
local function angle(a, b)
    return anglexy(a.x, a.y, b.x, b.y)
end
local function anglediff_cw(a, b)
    return anglenormal(b - a)
end

-- Classic's "smart" mode: find where along the route the player is (each segment subdivided at
-- the path's dist) and point to the end of that segment; off the route, split the corner at the
-- nearest point to decide between it and the one after. Segment i runs from point i to i+1.
-- Returns a point index or nil (keep).
local function SmartNext(points, loop, pathdist, px, py, pm, cur)
    local n = table.getn(points)
    local myway_i, mindist, on_path = 0, 9999, nil
    local onSeg = {}
    for i = 1, n do
        local way = points[i]
        local way2 = points[i + 1] or (loop and points[1])
        if not way2 then break end
        local segment = Dist(way.m, way.x, way.y, way2.m, way2.x, way2.y) or 9999
        local subdivs = math.max(1, math.ceil(segment / pathdist))
        for s = 0, subdivs - 1 do
            local sub = s / subdivs
            local dist = Dist(pm, px, py, way.m, way.x + (way2.x - way.x) * sub, way.y + (way2.y - way.y) * sub) or 9999
            if dist < pathdist then on_path, onSeg[i] = i, true end
            if dist < mindist then mindist, myway_i = dist, i end
        end
    end

    -- The last corner of a loop: the first segment decides whether the player is already past it.
    if loop and on_path == n and n > 1 then
        local way, way2 = points[1], points[2]
        local segment = Dist(way.m, way.x, way.y, way2.m, way2.x, way2.y) or 9999
        local subdivs = math.max(1, math.ceil(segment / pathdist))
        for s = 0, subdivs - 1 do
            local sub = s / subdivs
            local dist = Dist(pm, px, py, way.m, way.x + (way2.x - way.x) * sub, way.y + (way2.y - way.y) * sub) or 9999
            if dist < pathdist then on_path = 1 end
        end
    end
    -- The points are in route order: on the segment leading to the current point, go forward along
    -- the consecutive on-path segments from there. Classic takes the last on-path segment of the
    -- whole list instead, which flips back and forth on a route that returns along the same road.
    local s = cur and cur - 1
    if s and s < 1 then s = loop and n or nil end
    if s and onSeg[s] then
        for _ = 1, n do
            local nxt = s + 1
            if nxt > n then
                if not loop then break end
                nxt = 1
            end
            if not onSeg[nxt] then break end
            s = nxt
        end
        local e = s + 1
        if e > n then
            if not loop then return n end
            e = 1
        end
        return e
    end

    if on_path then myway_i = on_path end

    if mindist <= pathdist or on_path then
        myway_i = myway_i + 1
        while loop and myway_i > n do myway_i = myway_i - n end
        -- Past the end of an open path: stay on its last point.
        if points[myway_i] then return myway_i end
        return n
    elseif loop or myway_i < n - 1 then
        myway_i = myway_i + 1
        while myway_i > n do myway_i = myway_i - n end
        local a_i = myway_i - 1
        while a_i < 1 do a_i = a_i + n end
        local b_i = a_i + 1
        while b_i > n do b_i = b_i - n end
        local c_i = b_i + 1
        while c_i > n do c_i = c_i - n end
        local a, b, c = points[a_i], points[b_i], points[c_i]
        if not (a and b and c) then return myway_i end

        local angle_b_a = angle(b, a)
        local angle_b_c = angle(b, c)
        local angle_b_p = anglexy(b.x, b.y, px, py)
        local adherence = 0.6
        local angle_b_up = anglenormal(angle_b_a + anglediff_cw(angle_b_a, angle_b_c) * (1 - adherence))
        local angle_b_dn = anglenormal(angle_b_c + anglediff_cw(angle_b_c, angle_b_a) * adherence)
        if anglediff_cw(angle_b_a, angle_b_p) < anglediff_cw(angle_b_a, angle_b_up)
            or anglediff_cw(angle_b_dn, angle_b_p) < anglediff_cw(angle_b_dn, angle_b_a) then
            return b_i
        end
        return c_i
    end
    if points[myway_i + 1] then return myway_i + 1 end
    return n
end

-- The point the arrow should show now, by the path's follow mode; nil keeps the current one.
local function NextInPath(px, py, pm)
    local points, cur = follow.points, follow.cur
    local path = follow.path
    local mode = path.follow or "loose"
    local loop = path.loop
    local n = table.getn(points)

    local function reached(i)
        local p = points[i]
        local dist = Dist(pm, px, py, p.m, p.x, p.y)
        return dist and dist <= (p.dist or POINT_DEFAULT_RADIUS)
    end

    if mode == "smart" then
        return SmartNext(points, loop, path.dist or PATH_DEFAULT_DIST, px, py, pm, cur)

    elseif mode == "strict" then
        -- Every point in order, no shortcuts.
        if not cur then return 1 end
        if reached(cur) then
            if points[cur + 1] then return cur + 1 end
            if loop then return 1 end
        end
        return nil

    elseif mode == "strictbounce" then
        -- Every point in order, then back the same way.
        if not cur then return 1 end
        if not reached(cur) then return nil end
        if follow.direction == "reverse" then
            if points[cur - 1] then return cur - 1 end
            follow.direction = "normal"
            return points[cur + 1] and cur + 1 or nil
        end
        if points[cur + 1] then return cur + 1 end
        follow.direction = "reverse"
        return points[cur - 1] and cur - 1 or nil

    elseif mode == "loose" then
        -- Starts at the nearest point; stepping on any point ahead moves on to the one after it.
        -- The points are searched in route order from the current one -- to the end of an open
        -- path, half way round a loop -- so reaching it always moves on and a point already
        -- passed never pulls the arrow back (Classic searches every point from the first).
        if not cur then
            local nearest, nearestDist
            for i = 1, n do
                local p = points[i]
                local dist = Dist(pm, px, py, p.m, p.x, p.y)
                if dist and (not nearestDist or dist < nearestDist) then nearest, nearestDist = i, dist end
            end
            return nearest or 1
        end
        local ahead = loop and math.floor(n / 2) or n - cur
        for k = 0, ahead do
            local i = cur + k
            if i > n then i = i - n end
            if reached(i) then
                if points[i + 1] then return i + 1 end
                if loop then return 1 end
                return nil
            end
        end
        return nil
    end

    return 1
end

local function PathTitle(i)
    return (follow.path.title or "Path").." ("..i..")"
end

local function ShowPathPoint(i)
    follow.cur = i
    local p = follow.points[i]
    ZGV:ShowArrow(p.m, nil, p.x, p.y, PathTitle(i), p.dist or POINT_DEFAULT_RADIUS, 0)
end

-- Where the travel system takes the player when no point of the path is in their zone: the
-- nearest point of a looped path, the middle of an open one (in its first point's zone).
-- Returns mapID, mapname, x, y.
local function PathTravelTarget(px, py, pm)
    local points = follow.points
    local n = table.getn(points)
    if follow.path.loop then
        local nearest, nearestDist
        for i = 1, n do
            local p = points[i]
            local dist = Dist(pm, px, py, p.m, p.x, p.y)
            if dist and (not nearestDist or dist < nearestDist) then nearest, nearestDist = i, dist end
        end
        local p = points[nearest or 1]
        return p.m, p.mapname, p.x, p.y
    end
    local first = points[1]
    local x, y, count = 0, 0, 0
    for i = 1, n do
        if points[i].m == first.m then
            x, y, count = x + points[i].x, y + points[i].y, count + 1
        end
    end
    return first.m, first.mapname, x / count, y / count
end

local function PathHasMap(m)
    for _, p in ipairs(follow.points) do
        if p.m == m then return true end
    end
    return false
end

function ZGV:CheckPathPoint()
    if not follow then return end
    local px, py, pm = HBD:GetPlayerZonePosition()
    if not (px and pm) then return end

    if not PathHasMap(pm) then
        if not follow.travelling then
            follow.travelling, follow.cur = true, nil
            local m, mapname, x, y = PathTravelTarget(px, py, pm)
            local title = follow.path.title or "Path"
            if not ZGV:RouteTo(mapname, x, y, title) then
                ZGV:ShowArrow(m, nil, x, y, title)
            end
        end
        return
    end
    if follow.travelling then
        follow.travelling = nil
        ZGV:StopRoute()
    end

    local i = NextInPath(px, py, pm)
    if i and i ~= follow.cur then ShowPathPoint(i) end
end

-- Points the arrow along a step's patrol path. The same path again (UpdateFrame calls this on
-- every render) keeps the follower's position on it.
function ZGV:FollowPath(waypath)
    if UnitIsDeadOrGhost("player") then
        ZGV:StopPath()
        ZGV:StopRoute()
        return
    end
    if follow and follow.path == waypath then return end
    ZGV:StopPath()
    ZGV:StopRoute()

    local first = waypath.coords[1]
    if not first then
        ZGV:ShowArrow()
        return
    end
    local mapID = HBD and HBD:GetMapIDFromZoneName(first.mapname)
    if not mapID then
        -- Without map data the path cannot be followed: point at its first point.
        ZGV:ShowArrow(nil, first.mapname, first.x, first.y, "Path (1)", first.dist)
        return
    end

    local points = {}
    for i, c in ipairs(waypath.coords) do
        local m = HBD:GetMapIDFromZoneName(c.mapname)
        tinsert(points, { m = m or mapID, mapname = m and c.mapname or first.mapname, x = c.x, y = c.y, dist = c.dist })
    end
    follow = { path = waypath, points = points }
    ZGV:CheckPathPoint()
    follow.timer = ZGV:ScheduleRepeatingTimer("CheckPathPoint", 0.2)
end

function ZGV:StopPath()
    if not follow then return end
    ZGV:CancelTimer(follow.timer)
    follow = nil
end

-- What the map lines (below) draw, as ZygorGuidesViewerClassic's UpdateMapLines draws its
-- "route", "path" and "farm" point sets: the travel route from the player through the legs still
-- ahead, and the patrol path (closed when it loops). Each set is { points, first, player, loop };
-- a point has m (LibHereBeDragons mapID), x, y. A straight arrow with no route draws nothing, as
-- Classic draws no line without the travel system. The returned tables are reused between calls.
local lineSets, routeSet, pathSet = {}, {}, {}
function ZGV:GetMapLineSets()
    local n = 0
    if route and route.legs and route.legs[route.leg] then
        routeSet.points, routeSet.first, routeSet.player, routeSet.loop = route.legs, route.leg, true, nil
        n = n + 1
        lineSets[n] = routeSet
    end
    if follow then
        pathSet.points, pathSet.first, pathSet.player, pathSet.loop = follow.points, 1, nil, follow.path.loop
        n = n + 1
        lineSets[n] = pathSet
    end
    for i = n + 1, 2 do lineSets[i] = nil end
    return lineSets
end

--------------------------------------------------------------------------------------------
-- Map lines: ZygorGuidesViewerClassic's map lines (its Pointer:UpdateMapLines), drawn on the
-- world map and the minimap for the sets ZGV:GetMapLineSets returns.
--
-- A line is a row of small round dots, the way pfQuest draws its routes on this client class:
-- neither client has the Line widget or Texture:SetRotation, and Unreal Azeroth does not map the
-- 8-argument SetTexCoord onto a quad the way 1.12.1 documents it, so a rotated texture cannot
-- stand in for a line segment there. The dots keep their spacing across a set's corners and are
-- placed from each segment's own start, so cutting a segment at the map's edge or the minimap's
-- circle does not shift them. Textures parented to the minimap are not clipped to its circle, so
-- minimap segments are cut at the circle here, as Classic's UpdateMapLines does.

local sqrt, min, max = math.sqrt, math.min, math.max

-- Skins/mapline.tga (scripts/make_mapline.py) is one soft white dot.
local MAPLINE_TEXTURE = ZGV.DIR .. "\\Skins\\mapline"

-- Dot size and spacing, in the map's units; thinner than Classic's maplines_thickness (5) at the
-- user's request. The single ant colour (Pointer.Icons.ant_default), worldmap_maplines_opacity and
-- minimap_maplines_opacity are Classic's defaults.
local DOT_SIZE = 3
local DOT_SPACING = 4
local LINE_R, LINE_G, LINE_B = 0.8, 0.8, 0.8
local WORLDMAP_ALPHA, MINIMAP_ALPHA = 1, 1
-- Classic cuts minimap lines at this fraction of the minimap's radius.
local MINIMAP_CUT = 0.95
local UPDATE_INTERVAL = 0.1

-- Minimap diameter in yards per zoom level, the vanilla tables LibHereBeDragons-Pins-1.0,
-- Astrolabe and pfQuest all use.
local MINIMAP_SIZE = {
    indoor = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 },
    outdoor = { [0] = 466 + 2/3, [1] = 400, [2] = 333 + 1/3, [3] = 266 + 2/3, [4] = 200, [5] = 133 + 1/3 },
}

-- Indoor or outdoor, as LibHereBeDragons-Pins-1.0 (loaded by TomTom) decided it for its own
-- minimap pins; outdoor without it, which is also what it answers on Unreal Azeroth.
local function MinimapEnvironment()
    local pins = LibStub("LibHereBeDragons-Pins-1.0", true)
    if pins and pins.GetMinimapEnvironment then
        return (pins:GetMinimapEnvironment()) or "outdoor"
    end
    return "outdoor"
end

-- A set of dot textures on one map. Coordinates are in the parent's units, y growing downward,
-- measured from the anchor point ("TOPLEFT" of the world map, "CENTER" of the minimap). carry is
-- how far into the next segment its first dot falls.
local function NewLayer(parent, anchor, alpha)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(parent:GetFrameLevel() + 1)
    frame:SetAlpha(alpha)
    return { frame = frame, anchor = anchor, textures = {}, used = 0, carry = 0 }
end

local function DrawDot(layer, x, y)
    local n = layer.used + 1
    layer.used = n
    local tex = layer.textures[n]
    if not tex then
        tex = layer.frame:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(MAPLINE_TEXTURE)
        tex:SetVertexColor(LINE_R, LINE_G, LINE_B)
        tex:SetWidth(DOT_SIZE)
        tex:SetHeight(DOT_SIZE)
        layer.textures[n] = tex
    end
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", layer.frame, layer.anchor, x, -y)
    tex:Show()
end

-- The dots of one segment from (ax, ay) to (bx, by), only those between the fractions t0 and t1 of
-- it (the part left after cutting); t0 is nil when nothing of it is left.
local function DrawDots(layer, ax, ay, bx, by, t0, t1)
    local dx, dy = bx - ax, by - ay
    local len = sqrt(dx * dx + dy * dy)
    local d = layer.carry
    if t0 and len > 0 then
        local first, last = t0 * len, t1 * len
        if d < first then d = d + math.ceil((first - d) / DOT_SPACING) * DOT_SPACING end
        while d <= last do
            DrawDot(layer, ax + dx * d / len, ay + dy * d / len)
            d = d + DOT_SPACING
        end
    end
    if d < len then d = d + math.ceil((len - d) / DOT_SPACING) * DOT_SPACING end
    layer.carry = d - len
end

local function FinishLayer(layer)
    for i = layer.used + 1, table.getn(layer.textures) do
        layer.textures[i]:Hide()
    end
end

-- The player's position for the lines: x, y, mapID. LibHereBeDragons keeps serving the position
-- from before the world map was opened for as long as it stays open, since reading it would mean
-- moving the map the user is viewing. While it is open, the position is read on the displayed map
-- itself; that answers 0,0 when the player is not on it, and the held position is used then.
local function PlayerPosition()
    if WorldMapFrame and WorldMapFrame:IsVisible() then
        local m = HBD:GetCurrentMapID()
        local x, y = GetPlayerMapPosition("player")
        if m and x and y and not (x == 0 and y == 0) then return x, y, m end
    end
    local x, y, m = HBD:GetPlayerZonePosition()
    return x, y, m
end

-- A set's points in drawing order: the player (at px, py on map pm) first for the route, back to
-- the start for a loop.
local seq, playerPoint = {}, {}
local function BuildSequence(set, px, py, pm)
    local n = 0
    if set.player and px then
        playerPoint.m, playerPoint.x, playerPoint.y = pm, px, py
        n = 1
        seq[1] = playerPoint
    end
    local points = set.points
    for i = set.first, table.getn(points) do
        local p = points[i]
        if p.m and p.x and p.y then
            n = n + 1
            seq[n] = p
        end
    end
    if set.loop and n > 2 then
        n = n + 1
        seq[n] = seq[1]
    end
    return n
end

-- Liang-Barsky: narrows the segment's parameter range [t0, t1] by one edge of the 0..1 map
-- square; nil once nothing is left.
local function ClipEdge(p, q, t0, t1)
    if p == 0 then
        if q < 0 then return nil end
        return t0, t1
    end
    local r = q / p
    if p < 0 then
        if r > t1 then return nil end
        if r > t0 then t0 = r end
    else
        if r < t0 then return nil end
        if r < t1 then t1 = r end
    end
    return t0, t1
end

-- The fractions t0, t1 of a segment that lie inside the 0..1 map square, or nil.
local function ClipToSquare(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = ClipEdge(-dx, x1, 0, 1)
    if t0 then t0, t1 = ClipEdge(dx, 1 - x1, t0, t1) end
    if t0 then t0, t1 = ClipEdge(-dy, y1, t0, t1) end
    if t0 then t0, t1 = ClipEdge(dy, 1 - y1, t0, t1) end
    if not t0 or t0 > t1 then return nil end
    return t0, t1
end

-- The fractions t0, t1 of a segment that lie inside a circle of radius r around the origin, or nil.
local function ClipToCircle(x1, y1, x2, y2, r)
    local dx, dy = x2 - x1, y2 - y1
    local a = dx * dx + dy * dy
    if a == 0 then return nil end
    local b = 2 * (x1 * dx + y1 * dy)
    local c = x1 * x1 + y1 * y1 - r * r
    local disc = b * b - 4 * a * c
    if disc <= 0 then return nil end
    local sq = sqrt(disc)
    local t0 = max(0, (-b - sq) / (2 * a))
    local t1 = min(1, (-b + sq) / (2 * a))
    if t0 > t1 then return nil end
    return t0, t1
end

local function Enabled()
    return HBD and ZGV.db and ZGV.db.profile.maplines_enabled
end

-- Whether a layer has to be redrawn: what it shows (the map or zoom, a scale) or where the player
-- is (a) and b)) changed, or a set is a different one (a re-planned route is a new legs table).
-- Records the new state.
local function Changed(state, view, scale, a, b)
    local changed = state.view ~= view or state.scale ~= scale or state.a ~= a or state.b ~= b
    state.view, state.scale, state.a, state.b = view, scale, a, b
    local sets = ZGV:GetMapLineSets()
    for i = 1, 2 do
        local set = sets[i]
        local points, first, loop = set and set.points, set and set.first, set and set.loop
        if state[i] ~= points or state[i + 2] ~= first or state[i + 4] ~= loop then changed = true end
        state[i], state[i + 2], state[i + 4] = points, first, loop
    end
    return changed
end

--------------------------------------------------------------------------------------------
-- World map: every segment translated onto the map being viewed, cut at the map's edges.

local worldLayer = NewLayer(WorldMapButton, "TOPLEFT", WORLDMAP_ALPHA)

local worldState = {}
local function UpdateWorldMap()
    local mapID = Enabled() and HBD:GetCurrentMapID()
    local width, height = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
    local playerX, playerY, playerM = PlayerPosition()
    if not Changed(worldState, mapID or false, width, playerX, playerY) then return end
    worldLayer.used = 0
    if mapID then
        for _, set in ipairs(ZGV:GetMapLineSets()) do
            local n = BuildSequence(set, playerX, playerY, playerM)
            local px, py
            worldLayer.carry = 0
            for i = 1, n do
                local p = seq[i]
                local x, y = p.x, p.y
                if p.m ~= mapID then
                    x, y = HBD:TranslateZoneCoordinates(p.x, p.y, p.m, nil, mapID, nil, true)
                end
                if x and px then
                    local t0, t1 = ClipToSquare(px, py, x, y)
                    DrawDots(worldLayer, px * width, py * height, x * width, y * height, t0, t1)
                else
                    worldLayer.carry = 0
                end
                px, py = x, y
            end
        end
    end
    FinishLayer(worldLayer)
end

local worldNext = 0
worldLayer.frame:SetScript("OnUpdate", function()
    local now = GetTime()
    if now < worldNext then return end
    worldNext = now + UPDATE_INTERVAL
    UpdateWorldMap()
end)

--------------------------------------------------------------------------------------------
-- Minimap: every segment relative to the player in yards, scaled by the minimap's zoom and cut
-- at its circle. The minimap does not rotate on either client.

local miniLayer = NewLayer(Minimap, "CENTER", MINIMAP_ALPHA)

local miniState = {}
local function UpdateMinimap()
    local px, py, pm
    if Enabled() then px, py, pm = PlayerPosition() end
    local sizes = MINIMAP_SIZE[MinimapEnvironment()] or MINIMAP_SIZE.outdoor
    local yards = sizes[Minimap:GetZoom()] or sizes[0]
    local radius = Minimap:GetWidth() / 2
    local scale = radius / (yards / 2)
    if not Changed(miniState, pm or false, scale, px, py) then return end
    miniLayer.used = 0
    if px then
        local cut = radius * MINIMAP_CUT - DOT_SIZE / 2
        for _, set in ipairs(ZGV:GetMapLineSets()) do
            local n = BuildSequence(set, px, py, pm)
            local lx, ly
            miniLayer.carry = 0
            for i = 1, n do
                local p = seq[i]
                local _, dx, dy = HBD:GetZoneDistance(pm, nil, px, py, p.m, nil, p.x, p.y)
                local x, y
                if dx then x, y = dx * scale, dy * scale end
                if x and lx then
                    local t0, t1 = ClipToCircle(lx, ly, x, y, cut)
                    DrawDots(miniLayer, lx, ly, x, y, t0, t1)
                else
                    miniLayer.carry = 0
                end
                lx, ly = x, y
            end
        end
    end
    FinishLayer(miniLayer)
end

local miniNext = 0
miniLayer.frame:SetScript("OnUpdate", function()
    local now = GetTime()
    if now < miniNext then return end
    miniNext = now + UPDATE_INTERVAL
    UpdateMinimap()
end)

-- Dying drops the route, coming back to life plans it again (see ZGV:SetWaypoint).
function ZGV:OnPlayerDeathChanged()
    ZGV:UpdateFrame()
end
ZGV:RegisterEvent("PLAYER_DEAD", "OnPlayerDeathChanged")
ZGV:RegisterEvent("PLAYER_ALIVE", "OnPlayerDeathChanged")
ZGV:RegisterEvent("PLAYER_UNGHOST", "OnPlayerDeathChanged")

-- Manual test hook: /run ZGV:TestRoute("Undercity", 63.0, 48.0)
-- Plans a route from the player to that spot (English zone name, coordinates in percent as the
-- guides show them) and prints every route node: travel mode, map and position, the leg's text.
-- A node the itinerary leaves out (ItinerarySkip) is printed grey, with the reason.
function ZGV:TestRoute(zone, x, y)
    if not LibRover then
        ZGV:Print("LibRover-1.0 is not loaded.")
        return
    end
    if not LibRover.ready then
        ZGV:Print(string.format("LibRover is not ready yet (%d%%).", math.floor((LibRover.init_progress or 0) * 100)))
        return
    end
    local mapID = LibRover:GetMapByNameFloor(zone)
    if not (mapID and x and y) then
        ZGV:Print("Unknown zone or missing coordinates: "..tostring(zone))
        return
    end

    local started = GetTime()
    LibRover:QueueFindPath(0, 0, 0, mapID, x / 100, y / 100, function(state, path, extra, reason)
        if state == "progress" then return end
        if state == "success" then
            ZGV:Print(string.format("Route to %s %.1f,%.1f: %d legs, %.1f s to plan",
                zone, x, y, table.getn(path) - 1, GetTime() - started))
            for i = 2, table.getn(path) do
                local node = path[i]
                local skip = ItinerarySkip(node, path[i - 1])
                ZGV:Print(string.format("%s%d. [%s] %s %.1f,%.1f -- %s%s", skip and "|cff888888" or "",
                    i - 1, node.link and node.link.mode or "?",
                    LibRover.MapName(node), (node.x or 0) * 100, (node.y or 0) * 100,
                    tostring(node:GetTextAsItinerary()), skip and " (hidden: "..skip..")|r" or ""))
            end
        elseif state == "arrival" then
            ZGV:Print("Already there.")
        else
            ZGV:Print("No route: "..tostring(reason))
        end
        for _, e in ipairs(LibRover.ERRORS) do ZGV:Print("LibRover error: "..e) end
        -- LibRover runs one search at a time: stop this one re-planning, and give it back the
        -- guide's route if there is one.
        LibRover:Abort("test route done", true)
        if route then RequestPath() end
    end, { player = true, title = zone })
end
