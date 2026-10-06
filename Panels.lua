-- The four paddle panels: creation, position, visibility, focus visuals,
-- appearance, and Edit Mode.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local LAYOUT = ns.LAYOUT
local ATLAS = ns.ATLAS
local NATIVE_CVAR_SCALING = ns.NATIVE_CVAR_SCALING
local NATIVE_CVAR_HIGHLIGHT = ns.NATIVE_CVAR_HIGHLIGHT
local PANELS = ns.PANELS
local addon = ns.addon
local panelFrames = ns.panelFrames
local buttons = ns.buttons
local focusRouting = ns.focusRouting
local Print = ns.Print
local SafeCall = ns.SafeCall
local ApplyArt = ns.ApplyArt
local GetNativeCVarBool = ns.GetNativeCVarBool
local NATIVE_CROSSBAR_FRAME = ns.NATIVE_CROSSBAR_FRAME
local DefaultPanelPosition = ns.DefaultPanelPosition
local ResolvePanelAnchor = ns.ResolvePanelAnchor
local IsEditable = ns.IsEditable
local UpdatePromptVisibility = ns.UpdatePromptVisibility
local GetButtonCenter = ns.GetButtonCenter
local LayoutButtonVisual = ns.LayoutButtonVisual
local CreateActionButton = ns.CreateActionButton
local GetVisualPanelFromGamepadState = ns.GetVisualPanelFromGamepadState

local lastVisualPanel
local lastCrossbarFocused

-- Mirrors GamepadMainActionBarFrameMixin:UpdateActionBarFocusedState: the
-- native crossbar collapses every bar while a binding set other than the core
-- gameplay one (game menu, bags, settings) owns the controller. Polled rather
-- than registered through BindToCoreBindingActive so no addon code runs inside
-- Blizzard's listener loop. Unknown counts as focused, as before.
local function IsNativeCrossbarFocused()
    local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    if type(manager) ~= "table" or type(manager.IsOnlyCoreBindingSetActive) ~= "function" then
        return true
    end
    return SafeCall(manager.IsOnlyCoreBindingSetActive, manager) ~= false
end

local function SetPanelPosition(panelIndex)
    local panel = panelFrames[panelIndex]
    if not panel then
        return
    end

    local pos = ArinControllerDB.panelPositions[panelIndex] or DefaultPanelPosition(panelIndex)
    panel:ClearAllPoints()
    panel:SetPoint(ResolvePanelAnchor(pos))
end

local function SavePanelPosition(panelIndex)
    local panel = panelFrames[panelIndex]
    if not panel then
        return
    end

    local point, relativeTo, relativePoint, x, y = panel:GetPoint(1)
    if not point then
        return
    end

    -- Dragging re-anchors the panel to UIParent, so only a position that is
    -- still attached to the native crossbar keeps its frame reference.
    local relativeName = relativeTo and relativeTo ~= UIParent and type(relativeTo.GetName) == "function" and relativeTo:GetName() or nil
    ArinControllerDB.panelPositions[panelIndex] = {
        point = point,
        relativeTo = relativeName == NATIVE_CROSSBAR_FRAME and relativeName or nil,
        relativePoint = relativePoint or point,
        x = x or 0,
        y = y or 0,
    }
end

local function IsGamepadInterfaceActive()
    if C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function" then
        local style = SafeCall(C_InputInterfaceStyle.GetCurrentStyle)
        if style ~= nil then
            local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad or 1
            return style == gamepad
        end
    end
    if type(IsGamePadEnabled) == "function" then
        return SafeCall(IsGamePadEnabled) == true
    end
    return true
end

-- Hides the panels outside gamepad mode unless they are being positioned.
-- The panels parent secure action buttons, so showing or hiding them is a
-- protected action; in combat it waits for PLAYER_REGEN_ENABLED. A Standard
-- controller profile has no back paddles, so its panels stay hidden entirely.
local function UpdatePanelVisibility()
    if InCombatLockdown() then
        ns.pendingAppearanceRefresh = true
        return
    end

    local active = ns.GetActiveProfile and ns.GetActiveProfile()
    local paddleController = not (active and active.controllerType == "standard")
    local shown = paddleController and (ArinControllerDB.gamepadOnly == false or IsGamepadInterfaceActive() or IsEditable())
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel then
            panel:SetShown(shown)
        end
    end
end

local function UpdateEditOverlays()
    local editable = IsEditable()
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel and panel.editOverlay then
            panel.editOverlay:SetShown(editable)
        end
    end
    UpdatePanelVisibility()
end

local function SetModifierIconFocused(panel, focused)
    local icon = panel.modifierIcon
    if not icon then
        return
    end

    if focused then
        if type(icon.SetFocused) == "function" then
            pcall(icon.SetFocused, icon)
        end
    elseif type(icon.SetPressable) == "function" then
        pcall(icon.SetPressable, icon)
    end
end

-- Uses Blizzard's InputIconTextureFrameTemplate so the LT / RT prompts follow
-- the connected controller's glyph style exactly like the native crossbar.
local function CreateModifierIcon(panel, panelInfo)
    if not panelInfo.lt and not panelInfo.rt then
        return nil
    end

    local leftKey = GAMEPAD_TRIGGER_LEFT or "PADLTRIGGER"
    local rightKey = GAMEPAD_TRIGGER_RIGHT or "PADRTRIGGER"
    local frame

    if panelInfo.lt and panelInfo.rt then
        local ok, created = pcall(CreateFrame, "Frame", nil, panel, "InputPromptTwoIconTemplate")
        if ok and created and type(created.SetPromptInputIconKey) == "function" then
            local configured = pcall(function()
                created:SetPromptInputIconKey(1, leftKey)
                created:SetPromptInputIconKey(2, rightKey)
                if type(created.SetUseDropShadow) == "function" then
                    created:SetUseDropShadow(true)
                end
            end)
            if configured then
                frame = created
            else
                created:Hide()
            end
        elseif ok and created then
            created:Hide()
        end
    else
        local ok, created = pcall(CreateFrame, "Frame", nil, panel, "InputIconTextureFrameTemplate")
        if ok and created and type(created.SetInputKey) == "function" then
            local configured = pcall(function()
                created:SetInputKey(panelInfo.lt and leftKey or rightKey)
                if type(created.EnableDropShadow) == "function" then
                    created:EnableDropShadow()
                end
            end)
            if configured then
                frame = created
            else
                created:Hide()
            end
        elseif ok and created then
            created:Hide()
        end
    end

    if not frame then
        -- Text fallback for clients without the gamepad prompt templates.
        frame = CreateFrame("Frame", nil, panel)
        frame:SetSize(48, 16)
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.text:SetPoint("CENTER")
        frame.text:SetText(panelInfo.label)
        frame.SetFocused = function(self)
            self.text:SetTextColor(1, 0.82, 0)
        end
        frame.SetPressable = function(self)
            self.text:SetTextColor(0.62, 0.62, 0.62)
        end
        frame:SetPressable()
    end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.MODIFIER_ICON_Y)
    return frame
end

-- isActive: the panel's layer is selected by the triggers. isFocused: it is
-- selected and the native crossbar has gamepad focus, so it draws expanded.
local function SetPanelActiveVisual(panelIndex, isActive, crossbarFocused)
    local panel = panelFrames[panelIndex]
    if not panel then
        return
    end

    local scalingEnabled = GetNativeCVarBool(NATIVE_CVAR_SCALING, true)
    local highlightEnabled = ArinControllerDB.highlightActivePanel ~= false and GetNativeCVarBool(NATIVE_CVAR_HIGHLIGHT, true)
    local isFocused = isActive and crossbarFocused
    local expanded = isFocused and scalingEnabled
    local wasExpanded = panel.expanded == true

    panel.isActive = isActive
    panel.isFocused = isFocused
    panel.expanded = expanded

    local inactiveOpacity = ArinControllerDB.inactiveOpacity or 1.0
    panel:SetAlpha(IsEditable() and 1 or (isActive and 1 or inactiveOpacity))

    panel.focusBackground:SetAlpha(LAYOUT.FOCUS_BACKGROUND_ALPHA * (ArinControllerDB.highlightStrength or 1.0))
    panel.focusBackground:SetShown(isFocused and highlightEnabled and panel.focusBackground.artAvailable)

    if panel.modifierIcon then
        -- The native crossbar hides its LT / RT prompts while a menu has focus.
        panel.modifierIcon:SetShown(ArinControllerDB.showPanelLabels ~= false and (crossbarFocused or IsEditable()))
        SetModifierIconFocused(panel, isFocused)
    end

    if expanded and not wasExpanded then
        -- Native focus: the focus shadow starts fully opaque and settles to 0.4.
        panel.focusFadeStart = GetTime()
    elseif not expanded then
        panel.focusFadeStart = nil
    end

    for paddleIndex = 1, PADDLE_COUNT do
        local button = buttons[panelIndex][paddleIndex]
        if button then
            LayoutButtonVisual(button)
            if expanded and not wasExpanded then
                button.visual.shadowFocus:SetAlpha(1)
            end
            UpdatePromptVisibility(button)
        end
    end
end

local function UpdateFocusFades()
    local now = GetTime()
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel and panel.focusFadeStart then
            local progress = (now - panel.focusFadeStart) / LAYOUT.FOCUS_FADE_DURATION
            local alpha
            if progress >= 1 then
                alpha = LAYOUT.FOCUS_SHADOW_MIN_ALPHA
                panel.focusFadeStart = nil
            else
                alpha = 1 - ((1 - LAYOUT.FOCUS_SHADOW_MIN_ALPHA) * progress)
            end

            for paddleIndex = 1, PADDLE_COUNT do
                local button = buttons[panelIndex][paddleIndex]
                if button then
                    button.visual.shadowFocus:SetAlpha(alpha)
                end
            end
        end
    end
end

local function UpdatePanelVisualState(panelIndex, force)
    local crossbarFocused = IsNativeCrossbarFocused()
    if not force and lastVisualPanel == panelIndex and lastCrossbarFocused == crossbarFocused then
        return
    end

    lastVisualPanel = panelIndex
    lastCrossbarFocused = crossbarFocused
    for i = 1, PANEL_COUNT do
        SetPanelActiveVisual(i, i == panelIndex, crossbarFocused)
    end
end

local function CreatePanelFrame(panelIndex)
    local panelInfo = PANELS[panelIndex]
    local panel = CreateFrame("Frame", "ArinControllerPanel" .. panelIndex, UIParent)
    panel.panelIndex = panelIndex
    panel.expanded = false
    panel:SetSize(LAYOUT.PANEL_WIDTH, LAYOUT.PANEL_HEIGHT)
    panel:SetFrameStrata("LOW")
    -- The panels nest inside the native crossbar; keep them above its slots so
    -- an expanded paddle grid never disappears behind a native ring.
    panel:SetFrameLevel(40)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    -- Registered before the slots are created so their first layout pass works.
    panelFrames[panelIndex] = panel

    -- Soft highlight the native crossbar draws behind the focused bar.
    panel.focusBackground = panel:CreateTexture(nil, "BACKGROUND", nil, -2)
    panel.focusBackground:SetSize(LAYOUT.FOCUS_BACKGROUND_WIDTH, LAYOUT.FOCUS_BACKGROUND_HEIGHT)
    panel.focusBackground:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.GRID_CENTER_Y)
    if not ApplyArt(panel.focusBackground, ATLAS.focusBackground, nil) then
        panel.focusBackground:SetColorTexture(0.68, 0.45, 0.08, 0.6)
        panel.focusBackground:SetSize(LAYOUT.PANEL_WIDTH - 20, LAYOUT.PANEL_WIDTH - 20)
        panel.focusBackground.artAvailable = true
    end
    panel.focusBackground:Hide()

    for paddleIndex = 1, PADDLE_COUNT do
        local button = CreateActionButton(panelIndex, paddleIndex, panel)
        local x, y = GetButtonCenter(paddleIndex, true)
        button:SetPoint("CENTER", panel, "CENTER", x, y)
    end

    panel.modifierIcon = CreateModifierIcon(panel, panelInfo)

    panel.editOverlay = CreateFrame("Button", nil, panel)
    panel.editOverlay:SetAllPoints()
    panel.editOverlay:SetFrameLevel(panel:GetFrameLevel() + 50)
    panel.editOverlay:RegisterForDrag("LeftButton", "RightButton")
    panel.editOverlay:Hide()

    panel.editOverlay.fill = panel.editOverlay:CreateTexture(nil, "BACKGROUND")
    if ApplyArt(panel.editOverlay.fill, ATLAS.editGlow, nil) then
        panel.editOverlay.fill:SetSize(LAYOUT.PANEL_WIDTH + 44, LAYOUT.PANEL_WIDTH + 44)
        panel.editOverlay.fill:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.GRID_CENTER_Y)
        panel.editOverlay.fill:SetAlpha(0.5)
    else
        panel.editOverlay.fill:SetAllPoints()
        panel.editOverlay.fill:SetColorTexture(0.95, 0.72, 0.16, 0.10)
    end

    local function CreateEdge(point1, point2, isHorizontal)
        local edge = panel.editOverlay:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(point1.point, point1.x, point1.y)
        edge:SetPoint(point2.point, point2.x, point2.y)
        if isHorizontal then
            edge:SetHeight(2)
        else
            edge:SetWidth(2)
        end
        edge:SetColorTexture(1.0, 0.82, 0.28, 0.95)
        return edge
    end

    panel.editOverlay.top = CreateEdge({ point = "TOPLEFT", x = -2, y = 2 }, { point = "TOPRIGHT", x = 2, y = 2 }, true)
    panel.editOverlay.bottom = CreateEdge({ point = "BOTTOMLEFT", x = -2, y = -2 }, { point = "BOTTOMRIGHT", x = 2, y = -2 }, true)
    panel.editOverlay.left = CreateEdge({ point = "TOPLEFT", x = -2, y = 2 }, { point = "BOTTOMLEFT", x = -2, y = -2 }, false)
    panel.editOverlay.right = CreateEdge({ point = "TOPRIGHT", x = 2, y = 2 }, { point = "BOTTOMRIGHT", x = 2, y = -2 }, false)

    panel.editOverlay.text = panel.editOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.editOverlay.text:SetPoint("CENTER", panel, "CENTER", 0, LAYOUT.GRID_CENTER_Y)
    panel.editOverlay.text:SetText(panelInfo.label .. "\nDRAG TO MOVE")

    panel.editOverlay:SetScript("OnDragStart", function()
        if not IsEditable() then
            return
        end
        if InCombatLockdown() then
            Print("Paddle panels cannot be moved during combat.")
            return
        end
        panel:StartMoving()
    end)

    panel.editOverlay:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        SavePanelPosition(panelIndex)
    end)

    SetPanelPosition(panelIndex)
    return panel
end

local function CreateUI()
    focusRouting.CreateRouters()
    for panelIndex = 1, PANEL_COUNT do
        buttons[panelIndex] = {}
        CreatePanelFrame(panelIndex)
    end

    UpdatePanelVisualState(1, true)
    UpdateEditOverlays()
end

local function ApplyAppearance()
    if not panelFrames[1] then
        return
    end

    if InCombatLockdown() then
        ns.pendingAppearanceRefresh = true
        return
    end

    local scale = ArinControllerDB.hudScale or 1.0
    for panelIndex = 1, PANEL_COUNT do
        local panel = panelFrames[panelIndex]
        if panel then
            panel:SetScale(scale)
        end
    end

    UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    UpdateEditOverlays()
    ns.pendingAppearanceRefresh = false
end

local function SetUnlocked(unlocked)
    ArinControllerDB.unlocked = unlocked and true or false
    if InCombatLockdown() then
        ns.pendingAppearanceRefresh = true
        Print("Layout lock changes will apply after combat.")
        return
    end
    UpdateEditOverlays()
    UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    Print(unlocked and "Unlocked. Drag each paddle panel independently." or "Locked. Edit Mode will still unlock the panels while it is open.")
end

local function ResetPosition(panelIndex)
    if InCombatLockdown() then
        Print("Paddle panels cannot be moved during combat.")
        return
    end

    if panelIndex then
        ArinControllerDB.panelPositions[panelIndex] = DefaultPanelPosition(panelIndex)
        SetPanelPosition(panelIndex)
        Print(PANELS[panelIndex].label .. " position reset.")
        return
    end

    for i = 1, PANEL_COUNT do
        ArinControllerDB.panelPositions[i] = DefaultPanelPosition(i)
        SetPanelPosition(i)
    end
    Print("All paddle panel positions reset.")
end

local function RegisterEditModeIntegration()
    if ns.editModeCallbacksRegistered or not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then
        return
    end

    ns.editModeCallbacksRegistered = true

    EventRegistry:RegisterCallback("EditMode.Enter", function()
        ns.editModeActive = true
        UpdateEditOverlays()
        UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    end, addon)

    -- Dragged panels save on OnDragStop. Re-saving every panel here would turn
    -- a fallback UIParent anchor into a stored position and lose the crossbar
    -- attachment for panels that were never moved.
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        ns.editModeActive = false
        UpdateEditOverlays()
        UpdatePanelVisualState(GetVisualPanelFromGamepadState(), true)
    end, addon)

    -- Reloading the UI while Edit Mode is already open does not emit another
    -- EditMode.Enter event for us, so mirror the manager's current state once.
    if EditModeManagerFrame and type(EditModeManagerFrame.IsEditModeActive) == "function" then
        local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
        if ok and active then
            ns.editModeActive = true
        end
    end
end

ns.SetPanelPosition = SetPanelPosition
ns.IsGamepadInterfaceActive = IsGamepadInterfaceActive
ns.UpdatePanelVisibility = UpdatePanelVisibility
ns.UpdateEditOverlays = UpdateEditOverlays
ns.UpdateFocusFades = UpdateFocusFades
ns.UpdatePanelVisualState = UpdatePanelVisualState
ns.IsNativeCrossbarFocused = IsNativeCrossbarFocused
ns.CreateUI = CreateUI
ns.ApplyAppearance = ApplyAppearance
ns.SetUnlocked = SetUnlocked
ns.ResetPosition = ResetPosition
ns.RegisterEditModeIntegration = RegisterEditModeIntegration
