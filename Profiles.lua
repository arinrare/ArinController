-- Controller profiles. A profile is a snapshot of the whole gamepad layout:
-- every native crossbar storage slot (all four trigger layers across all three
-- action-bar pages, minus the game-reserved base face buttons) plus the addon's
-- own reserved paddle slots, together with the four paddle input keys.
--
-- Switching works exactly like the rest of the addon: the profile's data is
-- written back into the live storage and the normal ApplyPaddleKeys +
-- RefreshButtons path re-applies it. No part of the core addon needs to know
-- about profiles; the live tables stay the source of truth.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local Print = ns.Print
local SafeCall = ns.SafeCall

local PROFILE_VERSION = 4
local DEFAULT_PROFILE_ID = "bkp_default"

-- Base face buttons (X/Y/A/B) are game-reserved and live in the slots the
-- native crossbar excludes from its pageable range, so they are never captured
-- or written. Everything else in the range is fair game.

local function CopyTable(source)
    if type(source) ~= "table" then
        return source
    end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = CopyTable(value)
    end
    return copy
end

local function GenerateProfileId()
    return "bkp_" .. tostring(time() * 1000 % 1000000) .. math.random(1000, 9999)
end

local function GetProfiles()
    return ArinControllerCharDB and ArinControllerCharDB.profiles
end

-- Escapes Lua pattern magic characters so a profile name can be matched
-- literally when looking for its "(Copy N)" siblings.
local function EscapePattern(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

-- ---------------------------------------------------------------------------
-- Native gamepad storage. The crossbar's pageable slots are contiguous and
-- have the reserved slot count already removed, so iterating that range covers
-- every layer on every page while skipping the system-reserved face buttons.
-- ---------------------------------------------------------------------------

local function GetCrossbarSlotRange()
    if not C_GamepadUI or type(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex) ~= "function" then
        return nil
    end
    local first = SafeCall(C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
    if type(first) ~= "number" then
        return nil
    end

    local constants = Constants and Constants.GamepadActionBarConstants
    local pageable = constants and constants.NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT_STANDARD_PAGE or 32
    local reserved = constants and constants.NUM_RESERVED_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 4
    local pages = constants and constants.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 3
    pages = tonumber(pages) or 3
    pageable = tonumber(pageable) or 32
    reserved = tonumber(reserved) or 4

    local pageSlots = pageable - reserved
    if pageSlots <= 0 or pages <= 0 then
        return nil
    end
    return first, first + (pageSlots * pages) - 1
end

-- Active stance / druid-rogue-warrior form bar: a separate storage block of
-- NUM_SLOTS_PER_GAMEPAD_ACTION_BAR slots.
local function GetStanceSlotRange()
    if not C_GamepadUI or type(C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance) ~= "function" then
        return nil
    end
    local first = SafeCall(C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance)
    if type(first) ~= "number" then
        return nil
    end
    local constants = Constants and Constants.GamepadActionBarConstants
    local barSlots = constants and constants.NUM_SLOTS_PER_GAMEPAD_ACTION_BAR or 8
    barSlots = tonumber(barSlots) or 8
    if barSlots <= 0 then
        return nil
    end
    return first, first + barSlots - 1
end

-- Pet utility bar: its own storage block. The range is discovered by walking
-- forward while the client reports a valid gamepad action storage slot, so the
-- count does not depend on a constant that may not exist on this build.
local function GetPetSlotRange()
    if not C_GamepadUI
        or type(C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex) ~= "function"
        or type(C_GamepadUI.IsValidGamepadActionStorageSlotIndex) ~= "function" then
        return nil
    end
    local first = SafeCall(C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex)
    if type(first) ~= "number" then
        return nil
    end
    local last = first - 1
    for slot = first, first + 15 do
        if SafeCall(C_GamepadUI.IsValidGamepadActionStorageSlotIndex, slot) then
            last = slot
        else
            break
        end
    end
    if last < first then
        return nil
    end
    return first, last
end

local function CollectRange(first, last)
    local slots = {}
    if type(first) == "number" then
        for slot = first, last do
            slots[#slots + 1] = slot
        end
    end
    return slots
end

local function GetPaddleStorageSlots()
    local live = ns.nativeStorageSlots
    if type(live) == "table" and #live > 0 then
        return live
    end
    local saved = ArinControllerCharDB and ArinControllerCharDB.nativeSlots
    if type(saved) == "table" then
        return saved
    end
    return {}
end

local function GetCrossbarSlots()
    return CollectRange(GetCrossbarSlotRange())
end

local function GetStanceSlots()
    return CollectRange(GetStanceSlotRange())
end

local function GetPetSlots()
    return CollectRange(GetPetSlotRange())
end

-- Every slot a profile tracks: the crossbar pages, the active stance bar, the
-- pet utility bar, and the addon's own reserved paddle slots, de-duplicated.
-- The reserved base X/Y/A/B face buttons are never here.
local function GetTrackedSlots()
    local slots = {}
    local seen = {}

    local function add(list)
        for _, slot in ipairs(list) do
            if type(slot) == "number" and not seen[slot] then
                slots[#slots + 1] = slot
                seen[slot] = true
            end
        end
    end

    add(GetCrossbarSlots())
    add(GetStanceSlots())
    add(GetPetSlots())
    add(GetPaddleStorageSlots())

    return slots
end

-- Reads a slot as a portable descriptor. Every action type is preserved as the
-- raw GetActionInfo triple, so exotic bindings such as Forever's pet-utility,
-- stance or flyout icons are never dropped the way a whitelist would be.
local function ReadSlotDescriptor(slot)
    local actionType, id, subType = SafeCall(GetActionInfo, slot)
    if not actionType then
        return nil
    end
    return { kind = actionType, id = id, subType = subType }
end

-- True when the client exposes a pickup that can recreate this action type on
-- the cursor. A captured slot whose kind we cannot rebuild is left in place
-- rather than cleared, so no binding is ever destroyed by a profile apply.
local function CanRestoreKind(kind)
    if kind == "spell" then
        return (C_Spell and type(C_Spell.PickupSpell) == "function") or type(PickupSpell) == "function"
    elseif kind == "item" then
        return (C_Item and type(C_Item.PickupItem) == "function") or type(PickupItem) == "function"
    elseif kind == "macro" then
        return type(PickupMacro) == "function"
    elseif kind == "companion" then
        return (C_MountJournal and type(C_MountJournal.Pickup) == "function")
            or (C_PetJournal and type(C_PetJournal.PickupPet) == "function")
            or type(PickupCompanion) == "function"
    elseif kind == "flyout" then
        return type(PickupFlyout) == "function"
    elseif kind == "equipmentset" then
        return (C_EquipmentSet and type(C_EquipmentSet.PickupEquipmentSet) == "function")
            or type(PickupEquipmentSet) == "function"
    elseif kind == "pet" then
        return type(PickupPetAction) == "function"
    end
    return false
end

-- Picks a descriptor back up onto the cursor so it can be dropped into a slot.
local function PickupDescriptor(descriptor)
    if not descriptor or not CanRestoreKind(descriptor.kind) then
        return false
    end
    if descriptor.kind == "spell" then
        if C_Spell and type(C_Spell.PickupSpell) == "function" then
            return pcall(C_Spell.PickupSpell, descriptor.id)
        elseif PickupSpell then
            return pcall(PickupSpell, descriptor.id)
        end
    elseif descriptor.kind == "item" then
        if C_Item and type(C_Item.PickupItem) == "function" then
            return pcall(C_Item.PickupItem, descriptor.id)
        elseif PickupItem then
            return pcall(PickupItem, descriptor.id)
        end
    elseif descriptor.kind == "macro" then
        return pcall(PickupMacro, descriptor.id)
    elseif descriptor.kind == "companion" then
        if descriptor.subType == "MOUNT" and C_MountJournal and type(C_MountJournal.Pickup) == "function" then
            return pcall(C_MountJournal.Pickup, descriptor.id)
        elseif descriptor.subType == "CRITTER" and C_PetJournal and type(C_PetJournal.PickupPet) == "function" then
            return pcall(C_PetJournal.PickupPet, descriptor.id)
        elseif type(PickupCompanion) == "function" then
            return pcall(PickupCompanion, descriptor.subType, descriptor.id)
        end
    elseif descriptor.kind == "flyout" and type(PickupFlyout) == "function" then
        return pcall(PickupFlyout, descriptor.id)
    elseif descriptor.kind == "equipmentset" then
        if C_EquipmentSet and type(C_EquipmentSet.PickupEquipmentSet) == "function" then
            return pcall(C_EquipmentSet.PickupEquipmentSet, descriptor.id)
        elseif type(PickupEquipmentSet) == "function" then
            return pcall(PickupEquipmentSet, descriptor.id)
        end
    elseif descriptor.kind == "pet" and type(PickupPetAction) == "function" then
        return pcall(PickupPetAction, descriptor.id)
    end
    return false
end

-- Writes a descriptor into a slot, or clears the slot when descriptor is nil.
-- A descriptor whose action type has no pickup is left untouched (never
-- cleared) so no binding is ever destroyed by a profile apply.
local function WriteSlotDescriptor(slot, descriptor)
    if InCombatLockdown() then
        return false
    end

    if descriptor and not CanRestoreKind(descriptor.kind) then
        return false
    end

    ClearCursor()
    if C_ActionBar and type(C_ActionBar.HasAction) == "function" and C_ActionBar.HasAction(slot) then
        pcall(PickupAction, slot)
        ClearCursor()
    end

    if not descriptor then
        return true
    end

    PickupDescriptor(descriptor)
    if C_ActionBar and type(C_ActionBar.PutActionInSlot) == "function" then
        local ok = pcall(C_ActionBar.PutActionInSlot, slot)
        ClearCursor()
        return ok
    end
    ClearCursor()
    return false
end

-- Deep-copies the current live gamepad storage into { [slot] = descriptor }.
-- Always called at switch time, when the action bars are guaranteed loaded.
-- __slots records every slot in scope (even empty ones) so a restore clears
-- exactly the range this snapshot captured, and no more.
local function CaptureNativeState()
    local slots = GetTrackedSlots()
    local state = { __slots = {} }
    for _, slot in ipairs(slots) do
        state.__slots[slot] = true
        local descriptor = ReadSlotDescriptor(slot)
        if descriptor then
            state[slot] = descriptor
        elseif C_ActionBar and type(C_ActionBar.HasAction) == "function" and C_ActionBar.HasAction(slot) then
            -- The slot visibly holds something GetActionInfo cannot express.
            -- Record an opaque marker so a restore leaves it alone instead of
            -- treating it as empty and clearing it.
            state[slot] = { kind = "__opaque__" }
        end
    end
    return state
end

-- The slot numbers a captured snapshot may write. Fresh snapshots carry the
-- exact list in __slots; legacy snapshots (no __slots) fall back to the old
-- behaviour (crossbar pages + paddle slots) so they never touch stance or pet
-- ranges they were never captured with.
local function SnapshotSlotList(state)
    local out = {}
    local seen = {}
    local function add(items)
        for _, slot in ipairs(items) do
            if type(slot) == "number" and not seen[slot] then
                out[#out + 1] = slot
                seen[slot] = true
            end
        end
    end
    if state and state.__slots then
        for slot in pairs(state.__slots) do
            add({ slot })
        end
    else
        add(GetCrossbarSlots())
        add(GetPaddleStorageSlots())
    end
    return out
end

-- Re-writes a captured snapshot. A nil snapshot means "leave the live layout
-- alone"; an empty profile snapshot (__clear) clears every tracked slot. The
-- paddle slots are only touched while the addon is using native storage.
local function RestoreNativeState(state)
    if state == nil or InCombatLockdown() then
        return
    end

    local slots
    if state.__clear then
        slots = GetTrackedSlots()
    else
        slots = SnapshotSlotList(state)
    end

    local paddleSet = {}
    if not ns.nativeStorageEnabled then
        for _, slot in ipairs(GetPaddleStorageSlots()) do
            paddleSet[slot] = true
        end
    end

    for _, slot in ipairs(slots) do
        if not paddleSet[slot] then
            WriteSlotDescriptor(slot, state.__clear and nil or state[slot])
        end
    end
end

-- ---------------------------------------------------------------------------
-- Profile snapshot/apply
-- ---------------------------------------------------------------------------

local function SaveLiveIntoProfile(profile)
    profile.paddleKeys = CopyTable(ArinControllerDB.paddleKeys or {})
    profile.actions = {}
    for panelIndex = 1, PANEL_COUNT do
        profile.actions[panelIndex] = CopyTable((ArinControllerCharDB.fallbackActions or {})[panelIndex] or {})
    end
    profile.native = CaptureNativeState()
end

local function ApplyProfile(profile)
    ArinControllerDB.paddleKeys = CopyTable(profile.paddleKeys or {})

    if profile.native ~= nil then
        RestoreNativeState(profile.native)
    end
    if not ns.nativeStorageEnabled then
        for panelIndex = 1, PANEL_COUNT do
            ArinControllerCharDB.fallbackActions[panelIndex] = CopyTable((profile.actions or {})[panelIndex] or {})
        end
    end

    if ns.ApplyPaddleKeys then
        ns.ApplyPaddleKeys(true)
    end
    if ns.RefreshButtons then
        ns.RefreshButtons()
    end
    -- Standard profiles have no paddles, so the panels must be shown/hidden
    -- again after the active profile's controller type changes.
    if ns.UpdatePanelVisibility then
        ns.UpdatePanelVisibility()
    end
end

-- Called on ADDON_LOADED after EnsureCharacterDatabase. Stores whatever is
-- currently bound as the Default profile, preserving existing bindings. Version
-- 3 added the native crossbar snapshot; version 4 adds the generic action-type
-- capture (pet utilities, stance/flyout icons) plus the stance and pet storage
-- ranges. Version 1 tables (phantom entries such as "Default (Copy 1)") are
-- still reset the way version 2 did.
local function EnsureProfiles()
    local profiles = ArinControllerCharDB.profiles
    local version = profiles and (tonumber(profiles.version) or 0) or 0
    if profiles and version >= PROFILE_VERSION then
        return
    end

    -- Real version-2/3 profiles exist: upgrade them in place. Their snapshots
    -- keep working through the __slots fallback, and SwitchProfile re-captures
    -- with the current scope on the next switch.
    if profiles and version >= 2 and profiles.items and next(profiles.items) ~= nil then
        profiles.version = PROFILE_VERSION
        return
    end

    -- Missing/older storage: rebuild a single fresh "Default" from the live
    -- state, wiping stale entries.
    local defaultProfile = {
        id = DEFAULT_PROFILE_ID,
        name = "Default",
        controllerType = "elite",
        paddleCount = PADDLE_COUNT,
        paddleKeys = {},
        actions = {},
    }
    SaveLiveIntoProfile(defaultProfile)
    -- Leave the crossbar uncaptured until the first real switch, because
    -- ADDON_LOADED can run before the action bars are populated.
    defaultProfile.native = nil
    ArinControllerCharDB.profiles = {
        version = PROFILE_VERSION,
        activeProfileId = DEFAULT_PROFILE_ID,
        items = {
            [DEFAULT_PROFILE_ID] = defaultProfile,
        },
    }
end

local function GetActiveProfile()
    local profiles = GetProfiles()
    if profiles and profiles.activeProfileId and profiles.items then
        return profiles.items[profiles.activeProfileId]
    end
    return nil
end

local function GetProfileList()
    local list = {}
    local profiles = GetProfiles()
    if profiles and profiles.items then
        for id, profile in pairs(profiles.items) do
            list[#list + 1] = {
                id = id,
                name = profile.name,
                controllerType = profile.controllerType,
                paddleCount = profile.paddleCount,
            }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Smallest positive number not already used by a "<base> N" profile, so
-- deleting e.g. "Xbox Elite 2" frees 2 for the next create (no gaps grow).
local function FindLowestFreeNumber(base)
    local pattern = "^" .. EscapePattern(base) .. " (%d+)$"
    local used = {}
    local profiles = GetProfiles()
    if profiles and profiles.items then
        for _, profile in pairs(profiles.items) do
            local number = tonumber((profile.name or ""):match(pattern))
            if number then
                used[number] = true
            end
        end
    end
    local number = 1
    while used[number] do
        number = number + 1
    end
    return number
end

-- Creates a fully unbound profile: every tracked crossbar/paddle slot empty and
-- every paddle key "NONE". The reserved base X/Y/A/B slots are not tracked, so
-- applying the profile leaves them alone.
local function CreateProfile(controllerType)
    controllerType = controllerType == "standard" and "standard" or "elite"
    local base = controllerType == "elite" and "Xbox Elite" or "Xbox Standard"
    local number = FindLowestFreeNumber(base)

    local profile = {
        id = GenerateProfileId(),
        name = base .. " " .. number,
        controllerType = controllerType,
        paddleCount = controllerType == "elite" and PADDLE_COUNT or 0,
        paddleKeys = {},
        actions = {},
        native = { __clear = true },
    }
    for paddleIndex = 1, PADDLE_COUNT do
        profile.paddleKeys["P" .. paddleIndex] = "NONE"
    end
    for panelIndex = 1, PANEL_COUNT do
        profile.actions[panelIndex] = {}
    end

    local profiles = GetProfiles()
    profiles.items[profile.id] = profile
    return profile
end

-- Live switch: saves the current live state into the outgoing profile, then
-- loads the target profile and re-applies through the normal addon path.
local function SwitchProfile(profileId)
    local profiles = GetProfiles()
    if not profiles or not profiles.items or not profiles.items[profileId] then
        return false
    end
    if InCombatLockdown() then
        Print("Profiles cannot be switched during combat.")
        return false
    end

    local active = GetActiveProfile()
    if active and active.id ~= profileId then
        SaveLiveIntoProfile(active)
    end

    profiles.activeProfileId = profileId
    ApplyProfile(profiles.items[profileId])
    return true
end

-- Copies the active profile's full layout onto another existing profile. The
-- target keeps its own name and controller type: a Standard target drops the
-- addon's back paddles entirely, an Elite target keeps them.
local function CopyProfileInto(targetId)
    local profiles = GetProfiles()
    if not profiles or not profiles.items then
        return false
    end
    local target = profiles.items[targetId]
    if not target then
        return false
    end
    local source = GetActiveProfile()
    if not source or source.id == targetId then
        return false
    end

    -- Capture whatever is live right now into the source before copying.
    SaveLiveIntoProfile(source)

    target.controllerType = target.controllerType == "standard" and "standard" or "elite"
    target.actions = CopyTable(source.actions or {})

    local nativeCopy = CopyTable(source.native or {})
    if target.controllerType == "standard" then
        target.paddleCount = 0
        target.paddleKeys = {}
        for paddleIndex = 1, PADDLE_COUNT do
            target.paddleKeys["P" .. paddleIndex] = "NONE"
        end
        -- Drop the Elite back paddles: leave the addon's reserved slots out of
        -- the copied snapshot so they are cleared when the target is applied.
        for _, slot in ipairs(GetPaddleStorageSlots()) do
            nativeCopy[slot] = nil
            if nativeCopy.__slots then
                nativeCopy.__slots[slot] = nil
            end
        end
    else
        target.paddleCount = PADDLE_COUNT
        target.paddleKeys = CopyTable(source.paddleKeys or {})
    end
    target.native = nativeCopy

    return true, target.name
end

local function DeleteProfile(profileId)
    local profiles = GetProfiles()
    if not profiles or not profiles.items or not profiles.items[profileId] then
        return false
    end
    if profileId == profiles.activeProfileId then
        return false
    end
    local count = 0
    for _ in pairs(profiles.items) do
        count = count + 1
    end
    if count <= 1 then
        return false
    end
    profiles.items[profileId] = nil
    return true
end

-- Save hooks: mirror a single change from the live tables into the active
-- profile as it is made, so profiles stay in sync while binding.
local function OnLiveActionChanged(panelIndex, paddleIndex)
    local active = GetActiveProfile()
    if not active then
        return
    end
    active.actions = active.actions or {}
    active.actions[panelIndex] = active.actions[panelIndex] or {}
    local value = ArinControllerCharDB.fallbackActions and ArinControllerCharDB.fallbackActions[panelIndex]
        and ArinControllerCharDB.fallbackActions[panelIndex][paddleIndex]
    active.actions[panelIndex][paddleIndex] = value
end

local function OnLivePaddleKeyChanged(paddleIndex)
    local active = GetActiveProfile()
    if not active then
        return
    end
    active.paddleKeys = active.paddleKeys or {}
    active.paddleKeys["P" .. paddleIndex] = ArinControllerDB.paddleKeys["P" .. paddleIndex]
end

ns.EnsureProfiles = EnsureProfiles
ns.GetActiveProfile = GetActiveProfile
ns.GetProfileList = GetProfileList
ns.CreateProfile = CreateProfile
ns.SwitchProfile = SwitchProfile
ns.CopyProfileInto = CopyProfileInto
ns.DeleteProfile = DeleteProfile
ns.OnLiveActionChanged = OnLiveActionChanged
ns.OnLivePaddleKeyChanged = OnLivePaddleKeyChanged

-- Read-only diagnostics for validating the tracked slot range in game.
ns.GetTrackedSlots = GetTrackedSlots
ns.GetCrossbarSlotRange = GetCrossbarSlotRange
ns.GetStanceSlotRange = GetStanceSlotRange
ns.GetPetSlotRange = GetPetSlotRange
ns.ReadSlotDescriptor = ReadSlotDescriptor
