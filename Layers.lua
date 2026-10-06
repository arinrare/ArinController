-- Paddle key bindings, the secure driver that switches paddle layers with
-- LT / RT, and LT / RT state detection for the visuals.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local secureDriver = ns.secureDriver
local buttons = ns.buttons
local focusRouting = ns.focusRouting
local SafeCall = ns.SafeCall
local GetPaddleKey = ns.GetPaddleKey

local ltModifier
local rtModifier

-- All binding strings a paddle must answer to: the bare key plus every
-- combination of the emulated LT/RT modifiers. While a trigger is held the
-- client resolves "SHIFT-F9" before "F9", and the layer driver already picks
-- the right panel, so every variant points at the same slot.
local function GetPaddleBindingKeys(paddleIndex)
    local key = GetPaddleKey(paddleIndex)
    if not key then
        return {}
    end

    local modifiers = {}
    for _, modifier in ipairs({ ltModifier, rtModifier }) do
        if type(modifier) == "string" then
            local upper = modifier:upper()
            if not tContains(modifiers, upper) then
                modifiers[#modifiers + 1] = upper
            end
        end
    end
    table.sort(modifiers) -- ALT < CTRL < SHIFT, the client's canonical order

    local keys = { key }
    if #modifiers >= 1 then
        for _, modifier in ipairs(modifiers) do
            keys[#keys + 1] = modifier .. "-" .. key
        end
    end
    if #modifiers >= 2 then
        keys[#keys + 1] = table.concat(modifiers, "-") .. "-" .. key
    end
    return keys
end

-- The secure layer driver reads the paddle keys from attributes.
local function WriteSecureKeyAttributes()
    for paddleIndex = 1, PADDLE_COUNT do
        local keys = GetPaddleBindingKeys(paddleIndex)
        secureDriver:SetAttribute("paddleKeyCount" .. paddleIndex, #keys)
        for n = 1, #keys do
            secureDriver:SetAttribute("paddleKey" .. paddleIndex .. "_" .. n, keys[n])
        end
    end
end

local function BindPaddlesToPanel(panelIndex)
    panelIndex = tonumber(panelIndex) or 1
    if panelIndex < 1 or panelIndex > PANEL_COUNT then
        panelIndex = 1
    end

    if InCombatLockdown() then
        ns.pendingSecureRefresh = true
        return
    end

    ClearOverrideBindings(secureDriver)
    for paddleIndex = 1, PADDLE_COUNT do
        local button = focusRouting.enabled and focusRouting.routers[paddleIndex] or buttons[panelIndex][paddleIndex]
        for _, key in ipairs(GetPaddleBindingKeys(paddleIndex)) do
            SetOverrideBindingClick(secureDriver, true, key, button:GetName(), "LeftButton")
        end
    end
    secureDriver:SetAttribute("activePanel", panelIndex)
    ns.lastBoundPanel = panelIndex
end

local function RegisterSecureFrameRefs()
    if InCombatLockdown() then
        ns.pendingSecureRefresh = true
        return
    end

    for panelIndex = 1, PANEL_COUNT do
        for paddleIndex = 1, PADDLE_COUNT do
            secureDriver:SetFrameRef(
                string.format("P%dB%d", panelIndex, paddleIndex),
                buttons[panelIndex][paddleIndex]
            )
        end
    end

    WriteSecureKeyAttributes()
    secureDriver:SetAttribute("activePanel", 1)
end

local SECURE_STATE_BINDINGS = [[
    local panel = tonumber(newstate) or 1
    if panel < 1 or panel > 4 then
        panel = 1
    end

    self:SetAttribute("activePanel", panel)
    self:ClearBindings()
    for i = 1, 4 do
        local ref = self:GetFrameRef("P" .. panel .. "B" .. i)
        local count = tonumber(self:GetAttribute("paddleKeyCount" .. i)) or 0
        if ref then
            for n = 1, count do
                local key = self:GetAttribute("paddleKey" .. i .. "_" .. n)
                if key and key ~= "" then
                    self:SetBindingClick(true, key, ref, "LeftButton")
                end
            end
        end
    end
]]

local function GetGamepadEmulationCVar(name)
    local value
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        value = SafeCall(C_CVar.GetCVar, name)
    elseif type(GetCVar) == "function" then
        value = SafeCall(GetCVar, name)
    end
    return type(value) == "string" and value:upper() or nil
end

local function FindEmulatedModifier(buttonName)
    buttonName = buttonName and buttonName:upper()
    if not buttonName then
        return nil
    end

    local mappings = {
        { cvar = "GamePadEmulateShift", modifier = "shift" },
        { cvar = "GamePadEmulateCtrl", modifier = "ctrl" },
        { cvar = "GamePadEmulateAlt", modifier = "alt" },
    }

    for _, mapping in ipairs(mappings) do
        if GetGamepadEmulationCVar(mapping.cvar) == buttonName then
            return mapping.modifier
        end
    end
    return nil
end

local function SetupSecurePanelDriver()
    if InCombatLockdown() then
        ns.nativeHookStatus = "modifier driver deferred until combat ends"
        ns.pendingSecureRefresh = true
        return false
    end

    if ns.securePanelDriverRegistered then
        pcall(UnregisterStateDriver, secureDriver, "paddlepanel")
        ns.securePanelDriverRegistered = false
    end

    ltModifier = FindEmulatedModifier("PADLTRIGGER")
    rtModifier = FindEmulatedModifier("PADRTRIGGER")

    local failure
    if not ltModifier or not rtModifier or ltModifier == rtModifier then
        failure = string.format(
            "native modifier mapping incomplete (LT=%s, RT=%s)",
            tostring(ltModifier),
            tostring(rtModifier)
        )
    else
        WriteSecureKeyAttributes()
        secureDriver:SetAttribute("_onstate-paddlepanel", SECURE_STATE_BINDINGS)

        local driver = string.format(
            "[mod:%s,mod:%s] 4; [mod:%s] 2; [mod:%s] 3; 1",
            ltModifier,
            rtModifier,
            ltModifier,
            rtModifier
        )

        if not pcall(RegisterStateDriver, secureDriver, "paddlepanel", driver) then
            failure = "found LT/RT modifier mappings but failed to register secure state driver"
        end
    end

    if failure then
        -- Without a secure modifier signal, follow the native crossbar focus
        -- so the paddles still switch layers in combat.
        focusRouting.enabled = focusRouting.Setup()
        ns.nativeHookStatus = failure .. (focusRouting.enabled
            and "; paddles follow the native crossbar focus"
            or "; using mapped-state fallback out of combat")
        BindPaddlesToPanel(ns.lastBoundPanel)
        return false
    end

    focusRouting.enabled = false
    ns.securePanelDriverRegistered = true
    ns.nativeHookStatus = string.format(
        "secure native modifier driver (LT=%s, RT=%s)",
        ltModifier,
        rtModifier
    )
    return true
end

local function TryHookNativeTriggerDriver()
    -- v0.6 no longer wraps Blizzard's PADTRIGGER click frame. Forever binds LT
    -- and RT to the same native click target, so a wrapper cannot tell which
    -- physical trigger caused the click. The controller's modifier-emulation
    -- CVars are a better native signal and can drive a SecureStateDriver safely.
    return SetupSecurePanelDriver()
end

local function CacheGamepadButtonIndices()
    ns.ltButtonIndex = SafeCall(C_GamePad and C_GamePad.ButtonBindingToIndex, "PADLTRIGGER")
    ns.rtButtonIndex = SafeCall(C_GamePad and C_GamePad.ButtonBindingToIndex, "PADRTRIGGER")
end

local function GetMappedButtonArrayIndex(state, index)
    if not state or not state.buttons or type(index) ~= "number" then
        return nil
    end

    -- ButtonBindingToIndex returns the engine button index. Blizzard's Lua
    -- state table has differed between clients/tooling assumptions, so detect
    -- whether the returned buttons table exposes element 0 instead of guessing.
    if state.buttons[0] ~= nil then
        return index
    end
    return index + 1
end

local function GetMappedButtonDown(state, index)
    local arrayIndex = GetMappedButtonArrayIndex(state, index)
    return arrayIndex ~= nil and state.buttons[arrayIndex] == true
end

local function GetMappedState()
    if not C_GamePad or type(C_GamePad.GetDeviceMappedState) ~= "function" then
        return nil
    end

    local activeID = SafeCall(C_GamePad.GetActiveDeviceID)
    local state
    if type(activeID) == "number" then
        state = SafeCall(C_GamePad.GetDeviceMappedState, activeID)
    end
    return state or SafeCall(C_GamePad.GetDeviceMappedState)
end

-- Asks the client the same question the native crossbar asks
-- (GamepadMode.IsLeftModifierDown / IsRightModifierDown): is the crossbar
-- modifier binding held? Returns nil when neither native signal is available.
local function IsNativeModifierDown(side)
    if type(GamepadMode) == "table" then
        local func = side == "left" and GamepadMode.IsLeftModifierDown or GamepadMode.IsRightModifierDown
        if type(func) == "function" then
            local ok, down = pcall(func)
            if ok then
                return down == true, "GamepadMode"
            end
        end
    end

    if type(GetBindingKey) == "function" and type(IsKeyDown) == "function" then
        local bindingName = side == "left" and "GAMEPADLEFTMOD" or "GAMEPADRIGHTMOD"
        local ok, key1, key2 = pcall(GetBindingKey, bindingName, 1)
        if ok and (key1 or key2) then
            for _, key in ipairs({ key1, key2 }) do
                local downOk, down = pcall(IsKeyDown, key)
                if downOk and down then
                    return true, "modifier bindings"
                end
            end
            return false, "modifier bindings"
        end
    end

    return nil
end

local function GetVisualPanelFromGamepadState()
    local lt, method = IsNativeModifierDown("left")
    local rt = IsNativeModifierDown("right")

    if lt == nil or rt == nil then
        local state = GetMappedState()
        if not state then
            ns.visualDetectionMethod = "secure driver state"
            local securePanel = secureDriver:GetAttribute("activePanel")
            return tonumber(securePanel) or 1
        end

        ns.visualDetectionMethod = "mapped controller state"
        lt = GetMappedButtonDown(state, ns.ltButtonIndex)
        rt = GetMappedButtonDown(state, ns.rtButtonIndex)
    else
        ns.visualDetectionMethod = method
    end

    if lt and rt then
        return 4
    elseif lt then
        return 2
    elseif rt then
        return 3
    end
    return 1
end

ns.BindPaddlesToPanel = BindPaddlesToPanel
ns.RegisterSecureFrameRefs = RegisterSecureFrameRefs
ns.GetGamepadEmulationCVar = GetGamepadEmulationCVar
ns.SetupSecurePanelDriver = SetupSecurePanelDriver
ns.TryHookNativeTriggerDriver = TryHookNativeTriggerDriver
ns.CacheGamepadButtonIndices = CacheGamepadButtonIndices
ns.GetMappedButtonArrayIndex = GetMappedButtonArrayIndex
ns.GetMappedState = GetMappedState
ns.GetVisualPanelFromGamepadState = GetVisualPanelFromGamepadState
