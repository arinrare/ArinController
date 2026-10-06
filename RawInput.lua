-- Raw input watcher: /arincontroller test and /arincontroller learn
local _, ns = ...

local PADDLE_COUNT = ns.PADDLE_COUNT
local Print = ns.Print
local SafeCall = ns.SafeCall
local CacheGamepadButtonIndices = ns.CacheGamepadButtonIndices

local INPUT_WATCH_TEST_DURATION = 30
local INPUT_WATCH_LEARN_STEP_TIMEOUT = 30

local function GetRawState(deviceID)
    if not C_GamePad or type(C_GamePad.GetDeviceRawState) ~= "function" or type(deviceID) ~= "number" then
        return nil
    end
    local raw = SafeCall(C_GamePad.GetDeviceRawState, deviceID)
    if type(raw) == "table" and type(raw.rawButtons) == "table" then
        return raw
    end
    return nil
end

-- Finds a device that exposes raw state: the active one first, then any other.
local function FindRawInputDevice()
    local activeID = SafeCall(C_GamePad and C_GamePad.GetActiveDeviceID)
    local raw = GetRawState(activeID)
    if raw then
        return activeID, raw
    end

    local ids = SafeCall(C_GamePad and C_GamePad.GetAllDeviceIDs)
    if type(ids) == "table" then
        for _, id in ipairs(ids) do
            raw = GetRawState(id)
            if raw then
                return id, raw
            end
        end
    end
    return nil, nil
end

-- Raw button tables may be 0- or 1-based like the mapped state table; return a
-- snapshot keyed by the 0-based rawIndex used in GamePadConfig files.
local function SnapshotRawButtons(raw)
    local snapshot = {}
    local base = raw.rawButtons[0] ~= nil and 0 or 1
    local count = tonumber(raw.rawButtonCount) or #raw.rawButtons
    for rawIndex = 0, math.max(count - 1, 0) do
        snapshot[rawIndex] = raw.rawButtons[rawIndex + base] == true
    end
    return snapshot
end

local function GetDeviceConfig(vendorID, productID)
    if not C_GamePad or type(C_GamePad.GetConfig) ~= "function" then
        return nil
    end
    local config = SafeCall(C_GamePad.GetConfig, { vendorID = vendorID, productID = productID })
    if type(config) == "table" then
        return config
    end
    return nil
end

local function DescribeRawButtonMapping(config, rawIndex)
    if config and type(config.rawButtonMappings) == "table" then
        for _, mapping in ipairs(config.rawButtonMappings) do
            if mapping.rawIndex == rawIndex then
                if mapping.button and mapping.button ~= "" and mapping.button ~= "None" then
                    return mapping.button
                elseif mapping.axis then
                    return string.format("axis %s", tostring(mapping.axis))
                end
                return "None"
            end
        end
    end
    return "unmapped"
end

local function GetPaddleRawMappingDiagnostic()
    local deviceID, raw = FindRawInputDevice()
    if not raw then
        return "no raw gamepad state available"
    end

    local config = GetDeviceConfig(raw.vendorID, raw.productID)
    local parts = {}
    for paddle = 1, PADDLE_COUNT do
        local found = "none"
        if config and type(config.rawButtonMappings) == "table" then
            for _, mapping in ipairs(config.rawButtonMappings) do
                if type(mapping.button) == "string" and mapping.button:upper() == ("PADPADDLE" .. paddle) then
                    found = "raw " .. tostring(mapping.rawIndex)
                    break
                end
            end
        end
        parts[#parts + 1] = string.format("P%d=%s", paddle, found)
    end

    return string.format(
        "%s (%d:%d, device %s, %s raw buttons)   %s",
        tostring(raw.name),
        tonumber(raw.vendorID) or 0,
        tonumber(raw.productID) or 0,
        tostring(deviceID),
        tostring(raw.rawButtonCount or #raw.rawButtons),
        table.concat(parts, "  ")
    )
end

local function StopInputWatcher(message)
    if not ns.inputWatcher then
        return
    end
    ns.inputWatcher = nil
    if message then
        Print(message)
    end
end

local function StartInputWatcher(mode)
    local deviceID, raw = FindRawInputDevice()
    if not raw then
        Print("No gamepad raw state is available. Make sure the controller is connected and gamepad input is enabled.")
        return false
    end

    ns.inputWatcher = {
        mode = mode,
        deviceID = deviceID,
        vendorID = raw.vendorID,
        productID = raw.productID,
        deviceName = raw.name,
        config = GetDeviceConfig(raw.vendorID, raw.productID),
        previous = SnapshotRawButtons(raw),
        startedAt = GetTime(),
        stepStartedAt = GetTime(),
        step = 1,
        results = {},
    }

    Print(string.format(
        "%s: %s (vendor %d, product %d) with %s raw buttons.",
        mode == "learn" and "Learning paddles" or "Testing raw input",
        tostring(raw.name),
        tonumber(raw.vendorID) or 0,
        tonumber(raw.productID) or 0,
        tostring(raw.rawButtonCount or #raw.rawButtons)
    ))
    return true
end

-- Writes a device config that maps the learned raw buttons to PADPADDLE1-4.
-- The client stores addon configs in GamePadConfig_AddOns.json, loaded last.
local function ApplyLearnedPaddleMapping(watcher)
    if not C_GamePad or type(C_GamePad.SetConfig) ~= "function" then
        Print("This client does not expose C_GamePad.SetConfig; write the mapping into a GamePadConfig_*.json file instead.")
        return false
    end
    if InCombatLockdown() then
        Print("Gamepad configs cannot be changed during combat. Run /arincontroller learn again after combat.")
        return false
    end

    local config = GetDeviceConfig(watcher.vendorID, watcher.productID) or {}
    config.configID = config.configID or { vendorID = watcher.vendorID, productID = watcher.productID }
    config.name = config.name or ("ArinController mapping for " .. tostring(watcher.deviceName))
    config.comment = "Paddle buttons learned by ArinController (/arincontroller learn)"
    config.rawButtonMappings = config.rawButtonMappings or {}
    config.rawAxisMappings = config.rawAxisMappings or {}
    config.axisConfigs = config.axisConfigs or {}
    config.stickConfigs = config.stickConfigs or {}

    local byIndex = {}
    for _, mapping in ipairs(config.rawButtonMappings) do
        byIndex[mapping.rawIndex] = mapping
        -- Release any raw button that previously carried a paddle binding.
        if type(mapping.button) == "string" and mapping.button:upper():match("^PADPADDLE%d$") then
            mapping.button = "None"
        end
    end

    for paddle = 1, PADDLE_COUNT do
        local rawIndex = watcher.results[paddle]
        local mapping = byIndex[rawIndex]
        if not mapping then
            mapping = { rawIndex = rawIndex }
            config.rawButtonMappings[#config.rawButtonMappings + 1] = mapping
            byIndex[rawIndex] = mapping
        end
        mapping.button = "PADPADDLE" .. paddle
        mapping.axis = nil
        mapping.axisValue = nil
        mapping.comment = "ArinController paddle " .. paddle
    end

    local ok, err = pcall(C_GamePad.SetConfig, config)
    if not ok then
        Print("The client rejected the gamepad config: " .. tostring(err))
        return false
    end
    if type(C_GamePad.ApplyConfigs) == "function" then
        pcall(C_GamePad.ApplyConfigs)
    end

    local summary = {}
    for paddle = 1, PADDLE_COUNT do
        summary[#summary + 1] = string.format("P%d=raw %d", paddle, watcher.results[paddle])
    end
    Print("Saved paddle mapping: " .. table.concat(summary, ", ") .. ". Reload the UI if the paddles do not respond immediately.")
    return true
end

local function ClearLearnedPaddleMapping()
    if not C_GamePad or type(C_GamePad.DeleteConfig) ~= "function" then
        Print("This client does not expose C_GamePad.DeleteConfig.")
        return
    end
    if InCombatLockdown() then
        Print("Gamepad configs cannot be changed during combat.")
        return
    end

    local _, raw = FindRawInputDevice()
    if not raw then
        Print("No gamepad raw state is available.")
        return
    end

    local ok, err = pcall(C_GamePad.DeleteConfig, { vendorID = raw.vendorID, productID = raw.productID })
    if not ok then
        Print("Could not remove the device config: " .. tostring(err))
        return
    end
    if type(C_GamePad.ApplyConfigs) == "function" then
        pcall(C_GamePad.ApplyConfigs)
    end
    Print(string.format("Removed the addon gamepad config for %s. The client's default mapping is back in effect.", tostring(raw.name)))
end

local function PrintLearnPrompt(step)
    Print(string.format("Press paddle P%d now (%d seconds). Type /arincontroller learn cancel to stop.", step, INPUT_WATCH_LEARN_STEP_TIMEOUT))
end

local function UpdateInputWatcher()
    local watcher = ns.inputWatcher
    if not watcher then
        return
    end

    local now = GetTime()
    if watcher.mode == "test" and now - watcher.startedAt > INPUT_WATCH_TEST_DURATION then
        StopInputWatcher("Raw input test finished.")
        return
    end
    if watcher.mode == "learn" and now - watcher.stepStartedAt > INPUT_WATCH_LEARN_STEP_TIMEOUT then
        StopInputWatcher(string.format("No press detected for P%d. Learning cancelled; nothing was changed.", watcher.step))
        return
    end

    local raw = GetRawState(watcher.deviceID)
    if not raw then
        StopInputWatcher("Lost the gamepad raw state. Stopped.")
        return
    end

    local current = SnapshotRawButtons(raw)
    local pressed = {}
    for rawIndex, down in pairs(current) do
        if down and not watcher.previous[rawIndex] then
            pressed[#pressed + 1] = rawIndex
        end
    end
    watcher.previous = current
    if #pressed == 0 then
        return
    end
    table.sort(pressed)

    if watcher.mode == "test" then
        for _, rawIndex in ipairs(pressed) do
            Print(string.format("Raw button %d pressed (client maps it to %s).", rawIndex, DescribeRawButtonMapping(watcher.config, rawIndex)))
        end
        return
    end

    -- Learn mode: one raw button per paddle, in order P1..P4.
    local rawIndex = pressed[1]
    for paddle, assigned in pairs(watcher.results) do
        if assigned == rawIndex then
            Print(string.format("Raw button %d is already P%d. Press a different paddle for P%d.", rawIndex, paddle, watcher.step))
            return
        end
    end

    -- A raw button the client already uses for something else (A/B/X/Y, D-pad,
    -- shoulders...) means the controller profile mirrors the paddle onto that
    -- button. Rebinding it would steal the button from the native UI.
    local currentMapping = DescribeRawButtonMapping(watcher.config, rawIndex)
    local isFree = currentMapping == "None"
        or currentMapping == "unmapped"
        or currentMapping:upper():match("^PADPADDLE%d$") ~= nil
    if not isFree and not watcher.force then
        Print(string.format(
            "Raw button %d is the client's %s button, so the controller is sending this paddle as %s rather than as a paddle. Learning stopped; nothing was changed.",
            rawIndex, currentMapping, currentMapping
        ))
        Print("Unassign the paddles in the Xbox Accessories app (or switch the profile slot off), reconnect over USB, then run /arincontroller test: the paddles should appear as their own raw buttons. Use /arincontroller learn force only if you really want to take this button away from the native UI.")
        ns.inputWatcher = nil
        return
    end

    watcher.results[watcher.step] = rawIndex
    Print(string.format("P%d = raw button %d (currently %s).", watcher.step, rawIndex, DescribeRawButtonMapping(watcher.config, rawIndex)))
    watcher.step = watcher.step + 1
    watcher.stepStartedAt = now

    if watcher.step > PADDLE_COUNT then
        local finished = watcher
        ns.inputWatcher = nil
        if ApplyLearnedPaddleMapping(finished) then
            CacheGamepadButtonIndices()
        end
        return
    end

    PrintLearnPrompt(watcher.step)
end

local function StartRawInputTest()
    if ns.inputWatcher then
        StopInputWatcher("Stopped watching raw input.")
        return
    end
    if StartInputWatcher("test") then
        Print(string.format("Press each paddle. Raw button presses are printed for %d seconds; type /arincontroller test again to stop early.", INPUT_WATCH_TEST_DURATION))
    end
end

local function StartPaddleLearning(force)
    if ns.inputWatcher then
        StopInputWatcher("Stopped the previous watcher.")
    end
    if StartInputWatcher("learn") then
        ns.inputWatcher.force = force == true
        if force then
            Print("Force mode: raw buttons already used by the client will be rebound to the paddles.")
        end
        PrintLearnPrompt(1)
    end
end

ns.GetPaddleRawMappingDiagnostic = GetPaddleRawMappingDiagnostic
ns.StopInputWatcher = StopInputWatcher
ns.ClearLearnedPaddleMapping = ClearLearnedPaddleMapping
ns.UpdateInputWatcher = UpdateInputWatcher
ns.StartRawInputTest = StartRawInputTest
ns.StartPaddleLearning = StartPaddleLearning
