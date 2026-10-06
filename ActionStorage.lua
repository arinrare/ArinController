-- Reserves native C_GamepadUI action slots for the paddle buttons, or falls
-- back to actions stored in SavedVariables.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local SafeCall = ns.SafeCall

local STORAGE_SCAN_LIMIT = 512
local STORAGE_STOP_AFTER_INVALID = 32
local MIN_NATIVE_STORAGE_POOL = 48

local function IsValidNativeStorageSlot(slot)
    if not C_GamepadUI or type(C_GamepadUI.IsValidGamepadActionStorageSlotIndex) ~= "function" then
        return false
    end
    return SafeCall(C_GamepadUI.IsValidGamepadActionStorageSlotIndex, slot) == true
end

local function DiscoverNativeStorageSlots()
    if not C_GamepadUI
        or type(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex) ~= "function"
        or type(C_GamepadUI.IsValidGamepadActionStorageSlotIndex) ~= "function" then
        return nil
    end

    local first = SafeCall(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
    if type(first) ~= "number" then
        return nil
    end

    local petStart = SafeCall(C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex)
    local valid = {}
    local seenValid = false
    local invalidRun = 0

    for slot = first, first + STORAGE_SCAN_LIMIT do
        -- Pet storage is a separate range on Forever (for example pet=11 while
        -- general gamepad storage starts around 181). Only treat it as an upper
        -- boundary when it actually follows the general storage range.
        if type(petStart) == "number" and petStart > first and slot >= petStart then
            break
        end

        if IsValidNativeStorageSlot(slot) then
            valid[#valid + 1] = slot
            seenValid = true
            invalidRun = 0
        elseif seenValid then
            invalidRun = invalidRun + 1
            if invalidRun >= STORAGE_STOP_AFTER_INVALID then
                break
            end
        end
    end

    return valid
end

local function SavedNativeSlotsAreUsable()
    local saved = ArinControllerCharDB.nativeSlots
    if type(saved) ~= "table" or #saved ~= PANEL_COUNT * PADDLE_COUNT then
        return false
    end

    local seen = {}
    for _, slot in ipairs(saved) do
        if type(slot) ~= "number" or not IsValidNativeStorageSlot(slot) or seen[slot] then
            return false
        end
        seen[slot] = true
    end

    return true
end

local function HasFallbackActions()
    for panelIndex = 1, PANEL_COUNT do
        local panelActions = ArinControllerCharDB.fallbackActions and ArinControllerCharDB.fallbackActions[panelIndex]
        if panelActions then
            for paddleIndex = 1, PADDLE_COUNT do
                if panelActions[paddleIndex] then
                    return true
                end
            end
        end
    end
    return false
end

local function InitializeNativeStorage()
    ns.nativeStorageEnabled = false
    ns.nativeStorageSlots = {}
    ns.nativeStorageStatus = "unavailable"

    if SavedNativeSlotsAreUsable() then
        for i, slot in ipairs(ArinControllerCharDB.nativeSlots) do
            ns.nativeStorageSlots[i] = slot
        end
        ns.nativeStorageEnabled = true
        ns.nativeStorageStatus = "using previously reserved C_GamepadUI slots"
        return
    end

    -- Do not silently switch an existing SavedVariables profile to native action
    -- slots; doing so would make already assigned fallback actions appear empty.
    -- New/empty profiles can use native storage immediately.
    if HasFallbackActions() then
        ns.nativeStorageStatus = "preserving existing SavedVariables actions"
        return
    end

    local valid = DiscoverNativeStorageSlots()
    if not valid then
        ns.nativeStorageStatus = "C_GamepadUI action storage API unavailable"
        return
    end
    if #valid < MIN_NATIVE_STORAGE_POOL then
        ns.nativeStorageStatus = string.format("native pool too small (%d valid slots)", #valid)
        return
    end

    -- Reserve empty slots from the high end of the dedicated gamepad storage pool.
    -- This deliberately avoids overwriting anything Blizzard/the player already uses.
    local chosen = {}
    for i = #valid, 1, -1 do
        local slot = valid[i]
        if not C_ActionBar.HasAction(slot) then
            table.insert(chosen, 1, slot)
            if #chosen == PANEL_COUNT * PADDLE_COUNT then
                break
            end
        end
    end

    if #chosen ~= PANEL_COUNT * PADDLE_COUNT then
        ns.nativeStorageStatus = string.format("only %d unused native slots found", #chosen)
        return
    end

    ArinControllerCharDB.nativeSlots = chosen
    for i, slot in ipairs(chosen) do
        ns.nativeStorageSlots[i] = slot
    end
    ns.nativeStorageEnabled = true
    ns.nativeStorageStatus = "using newly reserved C_GamepadUI slots"
end

local function FlatButtonIndex(panelIndex, paddleIndex)
    return ((panelIndex - 1) * PADDLE_COUNT) + paddleIndex
end

local function GetNativeSlot(panelIndex, paddleIndex)
    return ns.nativeStorageSlots[FlatButtonIndex(panelIndex, paddleIndex)]
end

ns.DiscoverNativeStorageSlots = DiscoverNativeStorageSlots
ns.InitializeNativeStorage = InitializeNativeStorage
ns.GetNativeSlot = GetNativeSlot
