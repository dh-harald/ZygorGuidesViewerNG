-- Ported from the reference Zygor codebase's Step.lua, scoped to leveling guides on 1.12.1.
-- OR-logic goal groups (|or) and the "confirm" one-click-completes-all shortcut are in
-- Step:IsComplete, |next jumps in Step:GetNext/GetJumpDestination. Not ported: party sync,
-- chat sharing, macro auto-generation.
--
-- Sticky steps: Guide:Parse resolves step.sticky_labels into step.stickies, and
-- ZGV:UpdateFrame fills ZGV.CurrentStickies on every render from ZGV:GetStickiesAt(stepnum),
-- the step's stickies that can still be sticky (Step:CanBeSticky) and are not complete.

local Step = {}
ZGV.StepProto = Step
ZGV.StepProto_mt = { __index = Step }

function Step:New(data)
    setmetatable(data, ZGV.StepProto_mt)
    return data
end

-- Filled by ZGV:UpdateFrame; Goal:IsVisible's notinsticky check reads it.
ZGV.CurrentStickies = ZGV.CurrentStickies or {}

function Step:IsCurrentlySticky()
    if not self.is_sticky then return false end
    for i, v in ipairs(ZGV.CurrentStickies) do
        if v == self then return true end
    end
    return false
end

-- A step marked |stickyif is sticky only while that condition holds.
function Step:CanBeSticky()
    if self.condition_sticky and not self.condition_sticky() then return false end
    return self.is_sticky
end

--- @return complete, possible
function Step:IsComplete()
    for i, goal in ipairs(self.goals) do
        goal:UpdateStatus()
    end

    -- "Click Here to Continue" (|confirm) completes the WHOLE step immediately once
    -- clicked, regardless of any other goal still pending on it -- a guide author's
    -- universal manual-override button. Matches the reference's "one click to complete
    -- them all" rule.
    for i, goal in ipairs(self.goals) do
        if goal.action == "confirm" and goal.status == "complete" then
            return true, true
        end
    end

    -- |or grouping: goals tagged with the same |or are alternatives, not all-required --
    -- e.g. "Awaken 5 Lazy Peons |q 5441/1 |or" and "Click Here to Continue |confirm |or"
    -- are two different ways to finish the same step, only one needs to actually complete.
    -- Once any one of them does, ALL goals in the group count as complete for the AND
    -- check below (ported from the reference's orneeded/orcount/orcomplete logic).
    local orneeded, orcount = 0, 0
    for i, goal in ipairs(self.goals) do
        if goal.status ~= "hidden" and goal.orlogic then
            orneeded = goal.orlogic
            if goal.status == "complete" then orcount = orcount + 1 end
        end
    end
    local orcomplete = orneeded > 0 and orcount >= orneeded

    local completeable = false
    local complete = true
    local possible = false
    local anyVisible = false

    for i, goal in ipairs(self.goals) do
        local status = goal.status
        -- "pending" (prereq not yet met, see Goal:GetStatus) counts as not-visible here too,
        -- same as "hidden" -- so a step gated entirely on an unmet prereq still hits the
        -- all-invisible shortcut below and auto-advances, even though the row itself still
        -- renders (grayed out) rather than being skipped like a truly hidden goal.
        if status ~= "hidden" and status ~= "pending" then anyVisible = true end
        if goal.orlogic and orcomplete then status = "complete" end
        if status == "complete" or status == "incomplete" then
            completeable = true
            if status ~= "complete" and not goal.optional then
                complete = false
            end
            if status == "incomplete" then
                possible = true
            end
        end
    end

    -- A step whose goals are ALL hidden (e.g. gated off entirely by a standalone |only/
    -- |if that doesn't match the current player/state -- see Goal:IsVisible) has nothing
    -- left to show or do. Treat it as already complete so navigation auto-advances past
    -- it instead of leaving an empty step on screen.
    if not anyVisible and table.getn(self.goals) > 0 then
        return true, true
    end

    return completeable and complete, possible
end

-- True when an automatic or right-click run of ZGV:StepForward passes over this step, as
-- ZygorGuidesViewerClassic's fast-forward does: the step is complete, or -- with the
-- skipimpossible option, on by default -- nothing on it can be done (a goal is impossible and
-- none is incomplete). A step with only passive goals stops the run, since those have no
-- completion check here.
function Step:IsSkippable()
    local complete, possible = self:IsComplete()
    if complete then return true end
    if possible or not ZGV.db.profile.skipimpossible then return false end
    for i, goal in ipairs(self.goals) do
        if goal.status == "impossible" then return true end
    end
    return false
end

-- True when every goal on this step is hidden (e.g. a whole step gated off by a
-- standalone |only/|if that doesn't match the current player/state -- see
-- Goal:IsVisible). Used by StepForward/StepBack to skip such steps entirely in
-- whichever direction the player is navigating -- there's nothing to show or do here,
-- ever, for this character, unlike a step that's merely already completed (which is
-- still worth being able to browse back to).
function Step:IsFullyHidden()
    if table.getn(self.goals) == 0 then return false end
    for i, goal in ipairs(self.goals) do
        if goal:IsVisible() then return false end
    end
    return true
end

-- Where the guide goes after this step, as in ZygorGuidesViewerClassic: the |next of the
-- first visible goal that is done or has no completion of its own, otherwise "+1".
function Step:GetNext()
    for i, goal in ipairs(self.goals) do
        if goal.next and goal:IsVisible() and (not goal:IsCompleteable() or goal:IsComplete()) then
            return goal.next
        end
    end
    return "+1"
end

-- The step number a jump leads to, and the guide title for a jump into another guide
-- ("Guide\\Title::label"; the step is then a number or a label of that guide). A number is
-- absolute, "+N"/"-N" relative. A label resolves to its nearest step, "+label"/"-label" to the
-- nearest one after/before this step. nil when the label does not exist.
function Step:GetJumpDestination(jump)
    jump = jump or self:GetNext()
    if type(jump) == "number" or string.find(jump, "^%d+$") then return tonumber(jump) end

    local sign = string.sub(jump, 1, 1)
    if sign == "+" or sign == "-" then jump = string.sub(jump, 2) else sign = nil end

    if string.find(jump, "^%d+$") then
        local delta = tonumber(jump)
        if sign == "-" then delta = -delta end
        return self.num + delta
    end

    if string.find(jump, "\\") then
        local guide, tag = string.match(jump, "^(.*)::(.*)$")
        if not guide then guide = jump end
        return tonumber(tag) or tag or 1, ZGV:SanitizeGuideTitle(guide)
    end

    local labs = self.parentGuide.steplabels and self.parentGuide.steplabels[jump]
    if not labs then return end
    local back, fore
    for i, num in ipairs(labs) do
        if num < self.num then back = num end
        if num > self.num then fore = num break end
    end
    if sign == "+" then return fore end
    if sign == "-" then return back end
    if not fore or (back and self.num - back < fore - self.num) then return back end
    return fore
end

function Step:GetStep(num)
    return self.parentGuide:GetStep(num)
end
