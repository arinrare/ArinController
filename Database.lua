-- Default panel positions and the SavedVariables (account-wide and per
-- character), including migrations from older versions.
local _, ns = ...

local PANEL_COUNT = ns.PANEL_COUNT
local PADDLE_COUNT = ns.PADDLE_COUNT
local LAYOUT = ns.LAYOUT

-- Native crossbar geometry (Blizzard_GamepadActionBars/ActionBarTemplates.xml
-- and MainActionBarFrame.xml). GamepadMainActionBarFrame is 656 x 202 and sits
-- 25 units above the bottom of the screen; its four bars form a cross around
-- its centre: BASE on top (0, 58), LT left (-195, 0), RT right (195, 0) and
-- LT + RT at the bottom (0, -58). Each bar has a d-pad group on the left and a
-- face-button group on the right, whose inner slots are only 18 units apart,
-- so a 2 x 2 paddle grid cannot sit inside that gap. Instead every paddle
-- group is centred on its own bar and nested in the notch above the two inner
-- slots (the top d-pad and top face-button slots leave 80+ units of free width
-- there). LT + RT uses the free box in the middle of the cross, between the
-- BASE and LT + RT bars. All offsets are grid centres relative to the
-- crossbar's centre and are chosen so the expanded (focused) grid still
-- clears the expanded native slots.
local NATIVE_CROSSBAR_FRAME = "GamepadMainActionBarFrame"
local NATIVE_CROSSBAR_CENTER_Y = 25 + (202 / 2)
local DEFAULT_GRID_CENTERS = {
    [1] = { x = 0, y = 58 + 68 },   -- BASE: above the top bar
    [2] = { x = -195, y = 68 },     -- LT: above the left bar
    [3] = { x = 195, y = 68 },      -- RT: above the right bar
    [4] = { x = 0, y = 2 },         -- LT + RT: centre of the cross
}

local function DefaultPanelPosition(panelIndex)
    local center = DEFAULT_GRID_CENTERS[panelIndex] or DEFAULT_GRID_CENTERS[1]
    return {
        point = "CENTER",
        relativeTo = NATIVE_CROSSBAR_FRAME,
        relativePoint = "CENTER",
        x = center.x,
        -- The grid is drawn LAYOUT.GRID_CENTER_Y above the panel's centre.
        y = center.y - LAYOUT.GRID_CENTER_Y,
    }
end

-- Positions used by 0.6 / 0.7: panels flanking the crossbar on both sides.
local function LegacyDefaultPanelPosition(panelIndex)
    local outer = 328 + 16 + (LAYOUT.PANEL_WIDTH / 2)
    local inner = outer + LAYOUT.PANEL_WIDTH + 20
    local offsets = { -inner, -outer, outer, inner }
    return { point = "BOTTOM", relativePoint = "BOTTOM", x = offsets[panelIndex] or 0, y = 40 }
end

local function IsLegacyDefaultPosition(pos, panelIndex)
    local legacy = LegacyDefaultPanelPosition(panelIndex)
    return type(pos) == "table"
        and pos.relativeTo == nil
        and (pos.point or "BOTTOM") == legacy.point
        and (pos.relativePoint or "BOTTOM") == legacy.relativePoint
        and math.abs((tonumber(pos.x) or 0) - legacy.x) < 0.5
        and math.abs((tonumber(pos.y) or 0) - legacy.y) < 0.5
end

-- Resolves a stored position to something SetPoint accepts. Positions are
-- normally relative to the native crossbar so they follow it if it is moved
-- or scaled; when that frame does not exist the same spot is computed
-- relative to the bottom of the screen instead.
local function ResolvePanelAnchor(pos)
    local relativeTo = pos.relativeTo and _G[pos.relativeTo] or nil
    if relativeTo and type(relativeTo.GetObjectType) == "function" then
        return pos.point or "CENTER", relativeTo, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0
    end
    if pos.relativeTo == NATIVE_CROSSBAR_FRAME then
        return pos.point or "CENTER", UIParent, "BOTTOM", pos.x or 0, (pos.y or 0) + NATIVE_CROSSBAR_CENTER_Y
    end
    return pos.point or "BOTTOM", UIParent, pos.relativePoint or "BOTTOM", pos.x or 0, pos.y or 40
end

local function EnsureDatabase()
    ArinControllerDB = ArinControllerDB or {}
    local previousVersion = tonumber(ArinControllerDB.version) or 0
    -- Every build since 0.7.1 writes a version. A profile that has data but no
    -- version is therefore older, so it still needs the 0.7.1 migration.
    if ArinControllerDB.version == nil and next(ArinControllerDB) ~= nil then
        previousVersion = 7
    end
    ArinControllerDB.version = 8
    ArinControllerDB.unlocked = ArinControllerDB.unlocked == true

    if ArinControllerDB.hudScale == nil then
        ArinControllerDB.hudScale = 1.0
    end
    if ArinControllerDB.inactiveOpacity == nil then
        ArinControllerDB.inactiveOpacity = 1.0
    end
    if ArinControllerDB.highlightActivePanel == nil then
        ArinControllerDB.highlightActivePanel = true
    end
    if ArinControllerDB.highlightStrength == nil then
        ArinControllerDB.highlightStrength = 1.0
    end
    if ArinControllerDB.showPaddleBadges == nil then
        ArinControllerDB.showPaddleBadges = true
    end
    if ArinControllerDB.showPanelLabels == nil then
        ArinControllerDB.showPanelLabels = false
    end
    if ArinControllerDB.gamepadOnly == nil then
        ArinControllerDB.gamepadOnly = true
    end

    ArinControllerDB.paddleKeys = ArinControllerDB.paddleKeys or {}
    for paddleIndex = 1, PADDLE_COUNT do
        local key = ArinControllerDB.paddleKeys["P" .. paddleIndex]
        if type(key) ~= "string" or key == "" then
            ArinControllerDB.paddleKeys["P" .. paddleIndex] = "PADPADDLE" .. paddleIndex
        end
    end

    -- 0.7 adopts the native crossbar look, where unfocused bars are collapsed
    -- rather than dimmed. Existing profiles are moved to that default once.
    if previousVersion > 0 and previousVersion < 7 then
        ArinControllerDB.inactiveOpacity = 1.0
    end

    -- 0.7.1 nests the panels in the native crossbar, which already shows the
    -- LT / RT / LT + RT prompts under its own bars, so the addon's copies of
    -- those prompts become opt-in. Panels that still sit at the 0.6 / 0.7
    -- default spots move to the new layout; panels the user moved are kept.
    if previousVersion > 0 and previousVersion < 8 then
        ArinControllerDB.showPanelLabels = false
        ArinControllerDB.migrateLegacyPanelPositions = true
    end

    ArinControllerDB.hudScale = math.max(0.65, math.min(1.50, tonumber(ArinControllerDB.hudScale) or 1.0))
    ArinControllerDB.inactiveOpacity = math.max(0.10, math.min(1.0, tonumber(ArinControllerDB.inactiveOpacity) or 1.0))
    ArinControllerDB.highlightStrength = math.max(0.0, math.min(1.0, tonumber(ArinControllerDB.highlightStrength) or 1.0))
    ArinControllerDB.panelPositions = ArinControllerDB.panelPositions or {}

    -- Up to 0.7.6 the actions and reserved native slots lived here, account-wide.
    -- They are now per character (see EnsureCharacterDatabase), but the account
    -- copies are kept so every character can migrate them on its first login.
    ArinControllerDB.nativeSlots = ArinControllerDB.nativeSlots or {}
    ArinControllerDB.fallbackActions = ArinControllerDB.fallbackActions or {}
    for panelIndex = 1, PANEL_COUNT do
        ArinControllerDB.fallbackActions[panelIndex] = ArinControllerDB.fallbackActions[panelIndex] or {}
    end

    -- Migrate the original four-slot layout into the BASE panel if present.
    if ArinControllerDB.buttons and not ArinControllerDB.migratedLegacyButtons then
        for paddleIndex = 1, PADDLE_COUNT do
            local old = ArinControllerDB.buttons[paddleIndex]
            if old and old.action and not ArinControllerDB.fallbackActions[1][paddleIndex] then
                ArinControllerDB.fallbackActions[1][paddleIndex] = old.action
            end
        end
        ArinControllerDB.migratedLegacyButtons = true
    end

    -- v0.5 stored one position for the complete strip. Preserve that placement
    -- while splitting the four panels into independently movable frames.
    if not ArinControllerDB.migratedPanelPositions then
        local oldPosition = ArinControllerDB.position
        if type(oldPosition) == "table" then
            local legacyWidth = 114
            local legacyGap = 14
            local totalWidth = (legacyWidth * PANEL_COUNT) + (legacyGap * (PANEL_COUNT - 1))
            local firstCenter = -(totalWidth / 2) + (legacyWidth / 2)
            for panelIndex = 1, PANEL_COUNT do
                if not ArinControllerDB.panelPositions[panelIndex] then
                    ArinControllerDB.panelPositions[panelIndex] = {
                        point = "BOTTOM",
                        relativePoint = "BOTTOM",
                        x = (tonumber(oldPosition.x) or 0) + firstCenter + ((panelIndex - 1) * (legacyWidth + legacyGap)),
                        y = tonumber(oldPosition.y) or 115,
                    }
                end
            end
        end
        ArinControllerDB.migratedPanelPositions = true
    end

    for panelIndex = 1, PANEL_COUNT do
        local pos = ArinControllerDB.panelPositions[panelIndex]
        if type(pos) ~= "table" or (ArinControllerDB.migrateLegacyPanelPositions and IsLegacyDefaultPosition(pos, panelIndex)) then
            pos = DefaultPanelPosition(panelIndex)
            ArinControllerDB.panelPositions[panelIndex] = pos
        end
        local default = DefaultPanelPosition(panelIndex)
        pos.point = pos.point or default.point
        pos.relativePoint = pos.relativePoint or default.relativePoint
        pos.x = tonumber(pos.x) or default.x
        pos.y = tonumber(pos.y) or default.y
        if type(pos.relativeTo) ~= "string" then
            pos.relativeTo = nil
        end
    end
    ArinControllerDB.migrateLegacyPanelPositions = nil
end

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

-- Actions and reserved native slots are per character: a spell that one class
-- knows is nothing another class can cast, and action slot contents differ per
-- character anyway. Before 0.7.7 both lived account-wide in ArinControllerDB, so a
-- character that has no per-character table yet takes a copy of those values
-- once. That keeps whatever it saw before the update. Wrong-class spells that
-- came along can be cleared with /arincontroller clear.
local function EnsureCharacterDatabase()
    ArinControllerCharDB = ArinControllerCharDB or {}
    local db = ArinControllerCharDB

    if db.version == nil then
        if type(ArinControllerDB.fallbackActions) == "table" and type(db.fallbackActions) ~= "table" then
            db.fallbackActions = CopyTable(ArinControllerDB.fallbackActions)
        end
        if type(ArinControllerDB.nativeSlots) == "table" and type(db.nativeSlots) ~= "table" then
            db.nativeSlots = CopyTable(ArinControllerDB.nativeSlots)
        end
        local copiedActions = false
        for _, panelActions in pairs(db.fallbackActions or {}) do
            if type(panelActions) == "table" and next(panelActions) ~= nil then
                copiedActions = true
            end
        end
        if copiedActions or next(db.nativeSlots or {}) ~= nil then
            db.migratedFromAccount = true
        end
    end
    db.version = 1

    db.nativeSlots = db.nativeSlots or {}
    db.fallbackActions = db.fallbackActions or {}
    for panelIndex = 1, PANEL_COUNT do
        db.fallbackActions[panelIndex] = db.fallbackActions[panelIndex] or {}
    end
end

ns.NATIVE_CROSSBAR_FRAME = NATIVE_CROSSBAR_FRAME
ns.DefaultPanelPosition = DefaultPanelPosition
ns.ResolvePanelAnchor = ResolvePanelAnchor
ns.EnsureDatabase = EnsureDatabase
ns.EnsureCharacterDatabase = EnsureCharacterDatabase
