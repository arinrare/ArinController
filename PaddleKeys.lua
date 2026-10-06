-- Paddle input assignment, press-to-assign capture, and the setup guide
local _, ns = ...

local PADDLE_COUNT = ns.PADDLE_COUNT
local secureDriver = ns.secureDriver
local buttons = ns.buttons
local Print = ns.Print
local GetPaddleKey = ns.GetPaddleKey
local GetKeyDisplayName = ns.GetKeyDisplayName
local GetKeyNote = ns.GetKeyNote
local IsPaddleKeyAllowed = ns.IsPaddleKeyAllowed
local BindPaddlesToPanel = ns.BindPaddlesToPanel
local RegisterSecureFrameRefs = ns.RegisterSecureFrameRefs
local SetupSecurePanelDriver = ns.SetupSecurePanelDriver
local GetVisualPanelFromGamepadState = ns.GetVisualPanelFromGamepadState

local CAPTURE_IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true,
}

local CAPTURE_TIMEOUT = 20

local captureFrame
local captureState
local guideFrame

local RefreshGuideFrame -- defined with the guide below

-- Re-applies the configured paddle keys to the override bindings and the
-- secure layer driver. Deferred until after combat when necessary.
local function ApplyPaddleKeys(announce)
    if not buttons[1] or not buttons[1][1] then
        return
    end

    if InCombatLockdown() then
        ns.pendingSecureRefresh = true
        if announce then
            Print("Paddle input changes will apply after combat.")
        end
        return
    end

    ClearOverrideBindings(secureDriver)
    RegisterSecureFrameRefs()
    if ns.securePanelDriverRegistered then
        SetupSecurePanelDriver()
    end
    BindPaddlesToPanel(GetVisualPanelFromGamepadState())

    local seen = {}
    for paddleIndex = 1, PADDLE_COUNT do
        local key = GetPaddleKey(paddleIndex)
        if key then
            if seen[key] then
                Print(string.format("P%d and P%d both use %s; only one of them will fire.", seen[key], paddleIndex, GetKeyDisplayName(key)))
            else
                seen[key] = paddleIndex
            end
        end
    end

    if RefreshGuideFrame then
        RefreshGuideFrame()
    end
    -- Set by Settings.lua once the settings page exists.
    if ns.RefreshSettingsKeyRows then
        ns.RefreshSettingsKeyRows()
    end
end

-- Pass deferApply when setting several keys, then call ApplyPaddleKeys once.
local function SetPaddleKey(paddleIndex, key, deferApply)
    key = (key and key:upper()) or "NONE"
    local allowed, reason = IsPaddleKeyAllowed(key)
    if not allowed then
        Print(reason)
        return false
    end

    ArinControllerDB.paddleKeys["P" .. paddleIndex] = key
    if ns.OnLivePaddleKeyChanged then
        ns.OnLivePaddleKeyChanged(paddleIndex)
    end
    if not deferApply then
        ApplyPaddleKeys(true)
    end
    return true
end

local function StopKeyCapture(message)
    captureState = nil
    if captureFrame then
        captureFrame:Hide()
    end
    if message then
        Print(message)
    end
end

local function UpdateCaptureText()
    if not captureFrame or not captureState then
        return
    end
    captureFrame.title:SetText(string.format("Assign paddle P%d", captureState.paddle))
    captureFrame.text:SetText(string.format(
        "Press the paddle now. Whatever button or key the controller sends will be assigned to P%d.\nCurrently: %s.  Esc or Cancel stops.",
        captureState.paddle,
        GetKeyDisplayName(GetPaddleKey(captureState.paddle))
    ))
end

local function HandleCapturedKey(key)
    local state = captureState
    if not state or type(key) ~= "string" or key == "" then
        return
    end

    key = key:upper()
    local paddle = state.paddle
    local allowed, reason = IsPaddleKeyAllowed(key)
    if not allowed then
        Print(reason)
        if captureFrame then
            captureFrame.text:SetText(string.format("%s\n\nStill waiting for P%d. Esc or Cancel stops.", reason, paddle))
        end
        state.startedAt = GetTime()
        return
    end

    SetPaddleKey(paddle, key)
    Print(string.format("P%d assigned to %s.", paddle, GetKeyDisplayName(key)))

    if state.sequence and paddle < PADDLE_COUNT then
        state.paddle = paddle + 1
        state.startedAt = GetTime()
        UpdateCaptureText()
    else
        StopKeyCapture(nil)
    end
end

local function EnsureCaptureFrame()
    if captureFrame then
        return captureFrame
    end

    local frame = CreateFrame("Frame", "ArinControllerCaptureFrame", UIParent, "BackdropTemplate")
    frame:SetSize(480, 170)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(200)
    frame:SetClampedToScreen(true)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -18)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("TOP", frame.title, "BOTTOM", 0, -8)
    frame.text:SetWidth(420)
    frame.text:SetJustifyH("CENTER")

    frame.cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.cancel:SetSize(110, 22)
    frame.cancel:SetPoint("BOTTOM", 0, 14)
    frame.cancel:SetText("Cancel")
    frame.cancel:SetScript("OnClick", function()
        StopKeyCapture("Assignment cancelled.")
    end)

    frame:EnableKeyboard(true)
    if frame.EnableGamePadButton then
        frame:EnableGamePadButton(true)
    end
    frame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            StopKeyCapture("Assignment cancelled.")
            return
        end
        if CAPTURE_IGNORED_KEYS[key] then
            return
        end
        HandleCapturedKey(key)
    end)
    -- The frame does not propagate input, so captured presses never reach the
    -- native UI.
    frame:SetScript("OnGamePadButtonDown", function(_, button)
        HandleCapturedKey(button)
    end)
    frame:SetScript("OnUpdate", function()
        if captureState and GetTime() - captureState.startedAt > CAPTURE_TIMEOUT then
            StopKeyCapture("No input detected; assignment cancelled.")
        end
    end)
    frame:SetScript("OnHide", function()
        captureState = nil
    end)
    frame:Hide()

    captureFrame = frame
    return frame
end

-- Starts press-to-assign for one paddle, or for P1..P4 in sequence.
local function StartKeyCapture(paddleIndex, sequence)
    if InCombatLockdown() then
        Print("Paddle inputs cannot be assigned during combat.")
        return
    end

    -- The frame must exist before the capture state is set: creating it ends
    -- with a Hide() whose OnHide handler clears captureState, which used to
    -- leave the very first prompt blank and unresponsive.
    local frame = EnsureCaptureFrame()
    captureState = {
        paddle = paddleIndex or 1,
        sequence = sequence == true,
        startedAt = GetTime(),
    }
    UpdateCaptureText()
    frame:Show()
end

local GUIDE_TEXT = table.concat({
    "On Windows the Xbox Elite Series 2 does not report its paddles to games. WoW only sees whatever the Xbox Accessories app maps a paddle to. ArinController never takes over a button the native gamepad UI uses (A/B/X/Y, D-pad, bumpers, triggers, stick clicks, View, Menu), so each paddle has to arrive as an input WoW does not use.",
    "",
    "|cffffd100Option 1: Xbox Accessories app, keyboard key mapping|r",
    "1. Open Xbox Accessories, select the controller, and edit the profile whose slot is active (the slot LED shows which one).",
    "2. Map each paddle to a keyboard key by pressing a real key that WoW leaves unbound. On a compact keyboard F9, F10, F11, F12 are the natural set; F6-F8, Page Up/Down, Scroll Lock, Pause, and Numpad keys also work when present. Do not use a key you type in chat. Save the profile.",
    "3. Below, click Assign and press each paddle. The addon refuses any key that already has a WoW binding and tells you which one.",
    "4. Share is also free if the app offers it as a paddle target, but that covers only one paddle.",
    "",
    "|cffffd100Option 2: Steam Input or reWASD|r",
    "Same idea, but these tools can send keys that are not on your keyboard (F13-F24), which can never be pressed by accident. Steam: enable the Xbox Extended Feature Support driver under Settings > Controller, add WoW as a non-Steam game, map the paddles in its controller layout, and leave the paddles unassigned in Xbox Accessories.",
    "",
    "|cffffd100PlayStation DualSense Edge|r",
    "Without a profile the Edge's back buttons repeat face buttons, which the addon refuses. Steam Input and reWASD see them as their own inputs: enable PlayStation controller support in Steam, bind the back buttons (and Fn buttons if wanted) to F13-F16 in WoW's controller layout, then assign them here. No PS5 is needed.",
    "",
    "The live line at the bottom shows what WoW receives for any press. If a paddle shows up as A, B, X, Y or another native button, the controller profile is still mirroring it and the addon will refuse it. If a paddle press switches the interface to mouse and keyboard mode, look for an interface style option under Settings > Controls and pin it to gamepad.",
}, "\n")

local function EnsureGuideFrame()
    if guideFrame then
        return guideFrame
    end

    local frame = CreateFrame("Frame", "ArinControllerGuideFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 700)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -18)
    frame.title:SetText("ArinController setup guide")

    frame.body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.body:SetPoint("TOPLEFT", 24, -48)
    frame.body:SetWidth(592)
    frame.body:SetJustifyH("LEFT")
    frame.body:SetJustifyV("TOP")
    frame.body:SetSpacing(2)
    frame.body:SetText(GUIDE_TEXT)

    frame.rowsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.rowsHeader:SetPoint("TOPLEFT", frame.body, "BOTTOMLEFT", 0, -14)
    frame.rowsHeader:SetText("Current paddle inputs")

    frame.rows = {}
    local previous = frame.rowsHeader
    for paddleIndex = 1, PADDLE_COUNT do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(572, 24)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(400)
        row.label:SetJustifyH("LEFT")

        row.assign = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.assign:SetSize(120, 22)
        row.assign:SetPoint("RIGHT", 0, 0)
        row.assign:SetText("Assign P" .. paddleIndex)
        row.assign:SetScript("OnClick", function()
            StartKeyCapture(paddleIndex, false)
        end)

        frame.rows[paddleIndex] = row
        previous = row
    end

    frame.lastInput = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.lastInput:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
    frame.lastInput:SetWidth(572)
    frame.lastInput:SetJustifyH("LEFT")
    frame.lastInput:SetText("Last input detected while this window is open: none yet. Press a paddle to see what WoW receives.")

    frame.assignAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.assignAll:SetSize(170, 22)
    frame.assignAll:SetPoint("BOTTOMLEFT", 22, 16)
    frame.assignAll:SetText("Assign all by pressing")
    frame.assignAll:SetScript("OnClick", function()
        StartKeyCapture(1, true)
    end)

    frame.openSettings = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.openSettings:SetSize(120, 22)
    frame.openSettings:SetPoint("LEFT", frame.assignAll, "RIGHT", 8, 0)
    frame.openSettings:SetText("Open settings")
    frame.openSettings:SetScript("OnClick", function()
        if ns.settingsCategory and Settings and type(Settings.OpenToCategory) == "function" then
            Settings.OpenToCategory(ns.settingsCategory:GetID())
        end
    end)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetSize(100, 22)
    frame.close:SetPoint("BOTTOMRIGHT", -22, 16)
    frame.close:SetText("Close")
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Live readout: report presses without swallowing them. Propagation (for
    -- keys and gamepad buttons alike) is set by SetPropagateKeyboardInput, which
    -- is blocked in combat; ToggleGuideFrame never creates the frame in combat,
    -- and input is only read once propagation is confirmed.
    if frame.SetPropagateKeyboardInput and pcall(frame.SetPropagateKeyboardInput, frame, true) then
        frame:EnableKeyboard(true)
        frame:SetScript("OnKeyDown", function(_, key)
            if not CAPTURE_IGNORED_KEYS[key] then
                frame.lastInput:SetText(string.format("Last input detected: %s (%s)", GetKeyDisplayName(key), key))
            end
        end)
        if frame.EnableGamePadButton then
            frame:EnableGamePadButton(true)
            frame:SetScript("OnGamePadButtonDown", function(_, button)
                frame.lastInput:SetText(string.format("Last input detected: %s (%s)", GetKeyDisplayName(button), button))
            end)
        end
    end

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ArinControllerGuideFrame")
    end

    frame:Hide()
    guideFrame = frame
    return frame
end

RefreshGuideFrame = function()
    if not guideFrame or not guideFrame:IsShown() then
        return
    end
    for paddleIndex = 1, PADDLE_COUNT do
        local key = GetPaddleKey(paddleIndex)
        local note = key and GetKeyNote(key)
        local text = string.format("P%d:  %s", paddleIndex, GetKeyDisplayName(key))
        if key and key:match("^PADPADDLE%d$") then
            text = text .. "  |cffff6060(native paddle key; not reported by the Elite Series 2 on Windows)|r"
        elseif note and not key:match("^F%d+$") and key ~= "PADSOCIAL" then
            text = text .. "  |cffa0a0a0" .. note .. "|r"
        end
        guideFrame.rows[paddleIndex].label:SetText(text)
    end
end

local function ToggleGuideFrame()
    if not guideFrame and InCombatLockdown() then
        Print("The setup guide can be opened after combat.")
        return
    end

    local frame = EnsureGuideFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        RefreshGuideFrame()
    end
end

ns.ApplyPaddleKeys = ApplyPaddleKeys
ns.SetPaddleKey = SetPaddleKey
ns.StartKeyCapture = StartKeyCapture
ns.ToggleGuideFrame = ToggleGuideFrame
