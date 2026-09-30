local CHAIN=ZGV.ChainCall

function ZGV:ButtonTooltip(text)
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

function ZGV:ViewerFrameToggle()
    if ZygorGuidesViewerNGFrame:IsShown() then
        ZygorGuidesViewerNGFrame:Hide()
        ZGV.db.char.viewer.shown = false
    else
        ZygorGuidesViewerNGFrame:Show()
        ZGV.db.char.viewer.shown = true
    end
end

function ZGV:ViewerFrameSetLockIcon(button)
    if ZGV.db.char.viewer.locked then
        button:GetNormalTexture():SetTexCoord(0.25390625, 0.49609375, 0.00390625, 0.24609375)
        button:GetHighlightTexture():SetTexCoord(0.25390625, 0.49609375, 0.25390625, 0.49609375)
        button:GetPushedTexture():SetTexCoord(0.25390625, 0.49609375, 0.25390625, 0.49609375)
    else
        button:GetNormalTexture():SetTexCoord(0.00390625, 0.24609375, 0.00390625, 0.24609375)
        button:GetHighlightTexture():SetTexCoord(0.00390625, 0.24609375, 0.25390625, 0.49609375)
        button:GetPushedTexture():SetTexCoord(0.00390625, 0.24609375, 0.25390625, 0.49609375)
    end
end

function ZGV:ViewerFrameLock(button)
    ZGV.db.char.viewer.locked = not ZGV.db.char.viewer.locked
    ZGV:ViewerFrameSetLockIcon(button)
end

function ZGV:ViewerFrameClose()
    ZygorGuidesViewerNGFrame:Hide()
    ZGV.db.char.viewer.shown = false
end

function ZGV:ViewerFrameOnMouseDown(frame)
    if ZGV.db.char.viewer.locked then return end
    frame.isMoving = 1
    frame:StartMoving()
end

-- Saves the viewer's position relative to the nearest horizontal screen edge (left/right
-- third) or the horizontal center (middle third), always measured from the screen's top, so
-- the stored offset stays small and keeps its meaning when the UI's width/height changes
-- (the Unreal Azeroth client resizes UIParent with its window). Vertically it is always the
-- top: the viewer grows downward as its rows change (see ZGV:UpdateFrame), like the reference
-- viewer's default. Read from GetLeft/GetRight/GetTop (UIParent coordinates, the frame has no
-- scale of its own) rather than GetPoint, so the result does not depend on whichever anchor
-- StopMovingOrSizing left on the frame. The frame is not re-anchored here, only the position
-- is stored; ZGV:OnInitialize applies it on the next load.
function ZGV:ContainerGetPosition(frame)
    local left, right, top = frame:GetLeft(), frame:GetRight(), frame:GetTop()
    local screenWidth, screenHeight = UIParent:GetRight(), UIParent:GetTop()
    if not (left and right and top and screenWidth and screenHeight) then return end

    local center = (left + right) / 2
    local point, x
    if center <= screenWidth / 3 then
        point, x = "TOPLEFT", left
    elseif center >= screenWidth * 2 / 3 then
        point, x = "TOPRIGHT", right - screenWidth
    else
        point, x = "TOP", center - screenWidth / 2
    end

    ZGV.db.char.viewer = ZGV.db.char.viewer or {}
    ZGV.db.char.viewer.point = point
    ZGV.db.char.viewer.relativePoint = point
    ZGV.db.char.viewer.xOfs = math.floor(x + 0.5)
    ZGV.db.char.viewer.yOfs = math.floor(top - screenHeight + 0.5)
end

function ZGV:ViewerFrameOnMouseUp(frame)
    if ZGV.db.char.viewer.locked then return end
    frame:StopMovingOrSizing()
    ZGV:ContainerGetPosition(frame)
    frame.isMoving = nil
end

local function AlignFrame(self)
    local frame = self
    local framemaster = frame:GetParent()
    local width = frame:GetWidth()
    local height = frame:GetHeight()

    -- local upsideup = not ZGV.db.profile.resizeup
    local upsideup = true

    local UP_TOP = upsideup and "TOP" or "BOTTOM"
    local UP_TOPLEFT = upsideup and "TOPLEFT" or "BOTTOMLEFT"
    local UP_BOTTOMLEFT = upsideup and "BOTTOMLEFT" or "TOPLEFT"
    local UP_BOTTOM = upsideup and "BOTTOM" or "TOP"
    local UP_TOPRIGHT = upsideup and "TOPRIGHT" or "BOTTOMRIGHT"
    local UP_BOTTOMRIGHT = upsideup and "BOTTOMRIGHT" or "TOPRIGHT"
    local UP = upsideup and 1 or -1

    local backdrop_coords = {
        TopLeftCorner = {4/8+1/128, 5/8-1/128, 1/16, 1-1/16 },
        TopRightCorner = {5/8+1/128, 6/8-1/128, 1/16, 1-1/16 },
        BottomLeftCorner = {6/8+1/128, 7/8-1/128, 1/16, 1-1/16 },
        BottomRightCorner = {7/8+1/128, 8/8-1/128, 1/16, 1-1/16 },
        TopEdge = {2/8+1/128, 3/8-1/128, 1/16, 1-1/16 },
        BottomEdge = {3/8+1/128, 4/8-1/128, 1/16, 1-1/16 },
    }
    local function flipy(x1,x2,y1,y2)
        return x1,x2,y2,y1
    end
    local function flipx(x1,x2,y1,y2)
        return x2,x1,y1,y2
    end
    local function rotl(x1,x2,y1,y2)
        return x1,y2,x2,y2,x1,y1,x2,y1
    end

    -- self.Controls.DefaultStateButton.min_height = 60
end

-- The viewer's level inside its BACKGROUND strata: above everything else living there,
-- such as a minimap moved into BACKGROUND by a UI replacement (ElvUI puts it there, with
-- its minimap buttons at level 20), while any window of a higher strata still covers it.
local VIEWER_FRAME_LEVEL = 100

-- Raises frame and its whole child tree by delta, keeping their relative order. Children
-- first, so each one's level is read before anything above it changes. The XML children
-- already exist when OnLoad runs and do not follow a later SetFrameLevel on their parent
-- (measured on Unreal Azeroth). Named children are re-resolved through getglobal: on Unreal
-- Azeroth GetChildren returns stripped wrappers for XML-created frames.
local function RaiseFrameTree(frame, delta)
    local children = { frame:GetChildren() }
    for i = 1, table.getn(children) do
        local child = children[i]
        local name = child:GetName()
        if name and getglobal(name) then child = getglobal(name) end
        RaiseFrameTree(child, delta)
    end
    frame:SetFrameLevel(frame:GetFrameLevel() + delta)
end

function ZGV:ViewerFrameOnLoad(frame)
    frame.AlignFrame = AlignFrame
    -- Keep the viewer on the lowest frame strata so any window that opens (bags, quest
    -- log, spellbook, merchant, ...) draws on top of it instead of behind it.
    frame:SetFrameStrata("BACKGROUND")
    local delta = VIEWER_FRAME_LEVEL - frame:GetFrameLevel()
    if delta > 0 then RaiseFrameTree(frame, delta) end
    -- The step number at the reference viewer's StepNumFontSize (Starlight style). Its viewer
    -- has no guide name bar; 11 is its SectionTitleFontSize and fits the bar's 16px height.
    ZygorGuidesViewerNGFrameGuideNameBarText:SetFont(ZGV.FontBold, 11)
    ZygorGuidesViewerNGFrameNavBarStepText:SetFont(ZGV.Font, 14)
end

-- The Next button's tooltip, with ZygorGuidesViewerClassic's texts.
function ZGV:NextButtonOnEnter()
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:SetText("Next step")
    GameTooltip:AddLine("Click: skip one step", 0, 1, 0)
    GameTooltip:AddLine("Right-click: fast-forward to next incomplete step", 0, 1, 0)
    GameTooltip:Show()
end

-- The Next button: left click one step, right click to the next incomplete step, Shift ten
-- times either, as in ZygorGuidesViewerClassic. button is OnClick's arg1.
function ZGV:NextButtonOnClick(button)
    local mode = (button == "RightButton") and "fast" or nil
    local count = IsShiftKeyDown() and 10 or 1
    for i = 1, count do
        ZGV:StepForward(mode)
    end
end
