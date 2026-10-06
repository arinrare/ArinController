-- Switches paddle layers in combat by following the native crossbar focus,
-- for setups where LT and RT are not emulated modifier keys.
local _, ns = ...

local PADDLE_COUNT = ns.PADDLE_COUNT
local secureDriver = ns.secureDriver
local buttons = ns.buttons
local focusRouting = ns.focusRouting
local SafeCall = ns.SafeCall
local SetButtonPushed = ns.SetButtonPushed

-- The paddle's router (see focusRouting.CreateRouters) performs the action itself, so
-- it keeps a copy of every panel's attributes under the button name "panelN".
-- The "*" prefix makes them match with any modifier key held.
local ROUTED_ATTRIBUTES = { "type", "action", "spell", "item", "macrotext" }

function focusRouting.SyncAttributes(button)
    local router = focusRouting.routers[button.paddleIndex]
    if not router then
        return
    end
    local suffix = "-panel" .. button.panelIndex
    for _, name in ipairs(ROUTED_ATTRIBUTES) do
        router:SetAttribute("*" .. name .. suffix, button:GetAttribute(name))
    end
end

-- Picks the panel from the native crossbar focus at the moment a paddle is
-- pressed. The crossbar raises its focused bar one frame level above the
-- others (Blizzard_GamepadActionBars ShowHighlight/HideHighlight), and that
-- level is readable from restricted code in combat. Refs 1-4 are the top,
-- left, right and bottom bars, matching panels 1-4. No single highest bar
-- (not set up yet, or a stance/possess bar holds the focus) means panel 1.
local PRECLICK = [[
    local panel, best, tied = 1, nil, false
    for i = 1, 4 do
        local ref = self:GetFrameRef("nativeBar" .. i)
        if not ref then
            tied = true
            break
        end
        local level = ref:GetFrameLevel()
        if not best or level > best then
            panel, best, tied = i, level, false
        elseif level == best then
            tied = true
        end
    end
    if tied then
        panel = 1
    end
    self:SetAttribute("routedPanel", panel)
    return "panel" .. panel
]]

-- When LT and RT are not emulated Shift/Ctrl/Alt, no macro condition can see
-- them, so the layer driver cannot switch bindings in combat. Instead each
-- paddle key is bound to one hidden router that chooses the panel itself.
function focusRouting.CreateRouters()
    for paddleIndex = 1, PADDLE_COUNT do
        local router = CreateFrame("Button", "ArinControllerRouter" .. paddleIndex, UIParent, "SecureActionButtonTemplate")
        router.paddleIndex = paddleIndex
        router:SetSize(1, 1)
        router:SetAlpha(0)
        router:EnableMouse(false)
        router:RegisterForClicks("AnyUp", "AnyDown")
        router:SetAttribute("useOnKeyDown", true)
        secureDriver:WrapScript(router, "OnClick", PRECLICK)
        -- Mirror the pressed look onto the panel button that fired.
        router:SetScript("PostClick", function(self, _, down)
            if self.pushedButton then
                SetButtonPushed(self.pushedButton, false)
                self.pushedButton = nil
            end
            if down then
                local panel = tonumber(self:GetAttribute("routedPanel")) or 1
                local button = buttons[panel] and buttons[panel][self.paddleIndex]
                if button then
                    SetButtonPushed(button, true)
                    self.pushedButton = button
                end
            end
        end)
        focusRouting.routers[paddleIndex] = router
    end
end

-- The top, left, right and bottom crossbar bars, or nil when the native
-- crossbar is missing. Restricted code may only read protected frames in
-- combat; the bars are protected through their secure action buttons, but
-- fall back to a button in case the client does not propagate that.
local NATIVE_BAR_ANCHORS = { "TopCenteredAnchor", "LeftCenteredAnchor", "RightCenteredAnchor", "BottomCenteredAnchor" }

local function FindNativeBars()
    local pageUnit = _G.GamepadMainActionBarFramePageUnit
        or (_G.GamepadMainActionBarFrame and _G.GamepadMainActionBarFrame.PageUnit)
    if not pageUnit then
        return nil
    end

    local frames = {}
    for i, anchorKey in ipairs(NATIVE_BAR_ANCHORS) do
        local bar = pageUnit[anchorKey] and pageUnit[anchorKey].Bar
        if not bar then
            return nil
        end
        local frame = bar
        if not SafeCall(bar.IsProtected, bar) then
            frame = bar.Left and bar.Left.ActionButton1
            if not frame or not SafeCall(frame.IsProtected, frame) then
                return nil
            end
        end
        frames[i] = frame
    end
    return frames
end

-- The panel the routers would pick right now (same rule as PRECLICK).
function focusRouting.GetPanel()
    local frames = FindNativeBars()
    if not frames then
        return nil
    end
    local panel, best, tied = 1, nil, false
    for i, frame in ipairs(frames) do
        local level = frame:GetFrameLevel()
        if not best or level > best then
            panel, best, tied = i, level, false
        elseif level == best then
            tied = true
        end
    end
    return tied and 1 or panel
end

function focusRouting.Setup()
    local frames = FindNativeBars()
    if not frames or not focusRouting.routers[1] or type(SecureHandlerSetFrameRef) ~= "function" then
        return false
    end
    for _, router in ipairs(focusRouting.routers) do
        for i, frame in ipairs(frames) do
            SecureHandlerSetFrameRef(router, "nativeBar" .. i, frame)
        end
    end
    return true
end
