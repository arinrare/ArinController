-- /arincontroller diag: the diagnostics report and its copyable viewer
local ADDON_NAME, ns = ...

local NATIVE_CVAR_SCALING = ns.NATIVE_CVAR_SCALING
local NATIVE_CVAR_HIGHLIGHT = ns.NATIVE_CVAR_HIGHLIGHT
local NATIVE_CVAR_PROMPTS = ns.NATIVE_CVAR_PROMPTS
local PANELS = ns.PANELS
local secureDriver = ns.secureDriver
local panelFrames = ns.panelFrames
local focusRouting = ns.focusRouting
local missingAtlases = ns.missingAtlases
local Print = ns.Print
local SafeCall = ns.SafeCall
local GetNativeCVarBool = ns.GetNativeCVarBool
local GetPaddleKey = ns.GetPaddleKey
local IsGamepadInterfaceActive = ns.IsGamepadInterfaceActive
local DiscoverNativeStorageSlots = ns.DiscoverNativeStorageSlots
local GetGamepadEmulationCVar = ns.GetGamepadEmulationCVar
local GetMappedButtonArrayIndex = ns.GetMappedButtonArrayIndex
local GetMappedState = ns.GetMappedState
local GetPaddleRawMappingDiagnostic = ns.GetPaddleRawMappingDiagnostic
local GetVisualPanelFromGamepadState = ns.GetVisualPanelFromGamepadState
local IsNativeCrossbarFocused = ns.IsNativeCrossbarFocused
local GetSpellAlertDiagnosticLines = ns.GetSpellAlertDiagnosticLines

local function GetMappedDiagnosticValues()
    local state = GetMappedState()
    if not state then
        return "unavailable"
    end

    local ltLuaIndex = GetMappedButtonArrayIndex(state, ns.ltButtonIndex)
    local rtLuaIndex = GetMappedButtonArrayIndex(state, ns.rtButtonIndex)
    local ltValue = ltLuaIndex ~= nil and state.buttons and state.buttons[ltLuaIndex]
    local rtValue = rtLuaIndex ~= nil and state.buttons and state.buttons[rtLuaIndex]
    local tableBase = state.buttons and state.buttons[0] ~= nil and 0 or 1

    return string.format(
        "tableBase=%d   LT index=%s/lua=%s/value=%s   RT index=%s/lua=%s/value=%s",
        tableBase,
        tostring(ns.ltButtonIndex), tostring(ltLuaIndex), tostring(ltValue),
        tostring(ns.rtButtonIndex), tostring(rtLuaIndex), tostring(rtValue)
    )
end

local function GetModifierDiagnosticValues()
    return string.format(
        "Shift=%s   Ctrl=%s   Alt=%s",
        tostring(GetGamepadEmulationCVar("GamePadEmulateShift")),
        tostring(GetGamepadEmulationCVar("GamePadEmulateCtrl")),
        tostring(GetGamepadEmulationCVar("GamePadEmulateAlt"))
    )
end

local function GetNativeArtDiagnostic()
    local missing = missingAtlases.count or 0
    if missing == 0 then
        return "all native crossbar atlases found"
    end

    local names = {}
    for name, flagged in pairs(missingAtlases) do
        if flagged == true and name ~= "count" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return string.format("%d native atlases missing (using bundled art): %s", missing, table.concat(names, ", "))
end

local function GetNativeStyleDiagnostic()
    return string.format(
        "scaling=%s   highlight=%s   prompts=%s",
        tostring(GetNativeCVarBool(NATIVE_CVAR_SCALING, true)),
        tostring(GetNativeCVarBool(NATIVE_CVAR_HIGHLIGHT, true)),
        tostring(GetNativeCVarBool(NATIVE_CVAR_PROMPTS, true))
    )
end

local function GetDiagnosticLines(separator)
    local firstStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadActionStorageSlotIndex)
    local stanceStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance)
    local petStorage = SafeCall(C_GamepadUI and C_GamepadUI.GetFirstGamepadPetActionStorageSlotIndex)
    local ltAction = GetBindingAction("PADLTRIGGER", true)
    local rtAction = GetBindingAction("PADRTRIGGER", true)
    local securePanelIndex = tonumber(secureDriver:GetAttribute("activePanel")) or 1
    local visualPanelIndex = GetVisualPanelFromGamepadState()
    local securePanelText = PANELS[securePanelIndex].label
    if focusRouting.enabled then
        local focusPanel = focusRouting.GetPanel()
        securePanelText = (focusPanel and PANELS[focusPanel].label or "native crossbar missing") .. " (from native crossbar focus)"
    end

    local lines = {
        "Storage mode: " .. (ns.nativeStorageEnabled and "native C_GamepadUI action slots" or "SavedVariables fallback"),
        "Storage detail: " .. ns.nativeStorageStatus,
        "Storage scope: actions and reserved slots are per character" .. (ArinControllerCharDB.migratedFromAccount and " (copied from the account-wide profile of 0.7.6 or older)" or ""),
        string.format("Gamepad storage: first=%s%sstance=%s%spet=%s", tostring(firstStorage), separator, tostring(stanceStorage), separator, tostring(petStorage)),
        "Panel driver: " .. ns.nativeHookStatus,
        string.format("LT binding: %s%sRT binding: %s", tostring(ltAction), separator, tostring(rtAction)),
        "Modifier CVars: " .. GetModifierDiagnosticValues(),
        "Mapped state: " .. GetMappedDiagnosticValues(),
        "Paddle raw mapping: " .. GetPaddleRawMappingDiagnostic(),
        string.format("Paddle inputs: P1=%s   P2=%s   P3=%s   P4=%s",
            tostring(GetPaddleKey(1)), tostring(GetPaddleKey(2)), tostring(GetPaddleKey(3)), tostring(GetPaddleKey(4))),
        "Interface style: " .. tostring(C_InputInterfaceStyle and type(C_InputInterfaceStyle.GetCurrentStyle) == "function" and SafeCall(C_InputInterfaceStyle.GetCurrentStyle) or "unknown")
            .. " (CVar InputDeviceInterfaceStyle=" .. tostring(GetGamepadEmulationCVar("InputDeviceInterfaceStyle")) .. ")",
        "Panels shown: " .. tostring(panelFrames[1] and panelFrames[1]:IsShown()) .. " (gamepad interface=" .. tostring(IsGamepadInterfaceActive()) .. ", gamepad only=" .. tostring(ArinControllerDB.gamepadOnly ~= false) .. ")",
        "Visual detection: " .. ns.visualDetectionMethod .. (ns.nativeModifierCallbackRegistered and " (+ native crossbar callback)" or ""),
        "Visual panel: " .. PANELS[visualPanelIndex].label,
        "Native crossbar focused: " .. (IsNativeCrossbarFocused() and "yes" or "no (a menu has gamepad focus)"),
        "Visual expanded: " .. (panelFrames[visualPanelIndex] and panelFrames[visualPanelIndex].expanded and "yes" or "no"),
        "Secure panel: " .. securePanelText,
        "Native style CVars: " .. GetNativeStyleDiagnostic(),
        "Native art: " .. GetNativeArtDiagnostic(),
        "Edit Mode: " .. (ns.editModeActive and "active" or "inactive") .. (ns.editModeCallbacksRegistered and " (listening for EditMode.Enter/Exit)" or " (integration unavailable)"),
    }

    if ns.nativeStorageEnabled then
        local values = {}
        for _, slot in ipairs(ns.nativeStorageSlots) do
            values[#values + 1] = tostring(slot)
        end
        lines[#lines + 1] = "Reserved native slots: " .. table.concat(values, ", ")

        -- Checks the reservation against the slots the native crossbar
        -- addresses (GamepadActionBarBindingUtil): the standard pages, each
        -- with its reserved UI slots removed, plus the active stance bar.
        local constants = Constants and Constants.GamepadActionBarConstants or {}
        local pageSlots = (constants.NUM_PAGEABLE_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT_STANDARD_PAGE or 32)
            - (constants.NUM_RESERVED_SLOTS_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 4)
        local pageCount = constants.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT or 3
        local barSlots = constants.NUM_SLOTS_PER_GAMEPAD_ACTION_BAR or 8
        local ranges = {}
        if type(firstStorage) == "number" then
            ranges[#ranges + 1] = { label = "pages", first = firstStorage, last = firstStorage + pageSlots * pageCount - 1 }
        end
        if type(stanceStorage) == "number" then
            ranges[#ranges + 1] = { label = "active stance", first = stanceStorage, last = stanceStorage + barSlots - 1 }
        end

        local conflicts = {}
        for _, slot in ipairs(ns.nativeStorageSlots) do
            for _, range in ipairs(ranges) do
                if slot >= range.first and slot <= range.last then
                    conflicts[#conflicts + 1] = string.format("%d (%s)", slot, range.label)
                end
            end
        end

        local rangeText = {}
        for _, range in ipairs(ranges) do
            rangeText[#rangeText + 1] = string.format("%s %d-%d", range.label, range.first, range.last)
        end
        local pool = DiscoverNativeStorageSlots()
        if pool and #pool > 0 then
            rangeText[#rangeText + 1] = string.format("valid pool %d-%d", pool[1], pool[#pool])
        end
        if type(stanceStorage) ~= "number" then
            rangeText[#rangeText + 1] = "no stance active"
        end

        lines[#lines + 1] = string.format("Native slot check: %s%s%s",
            #conflicts == 0 and "OK" or ("CONFLICT " .. table.concat(conflicts, ", ")),
            separator,
            table.concat(rangeText, ", "))
    end

    for _, line in ipairs(GetSpellAlertDiagnosticLines()) do
        lines[#lines + 1] = line
    end

    return lines
end

-- Removes chat markup (colors, textures, atlases, hyperlinks) so the report
-- pastes cleanly into GitHub issues and Discord.
local function StripMarkup(text)
    text = tostring(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|n", " ")
    text = text:gsub("||", "|")
    return text
end

-- Shared by /arincontroller diag and the diagnostics viewer so both stay identical.
local function BuildDiagnosticLines()
    local version = C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function"
        and SafeCall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
        or (type(GetAddOnMetadata) == "function" and SafeCall(GetAddOnMetadata, ADDON_NAME, "Version"))
    local gameVersion, build, _, interfaceVersion
    if type(GetBuildInfo) == "function" then
        gameVersion, build, _, interfaceVersion = GetBuildInfo()
    end

    local lines = {
        string.format("ArinController %s diagnostics", tostring(version or "unknown")),
        string.format("Client: %s (build %s, interface %s)", tostring(gameVersion), tostring(build), tostring(interfaceVersion)),
    }
    for _, line in ipairs(GetDiagnosticLines(" | ")) do
        lines[#lines + 1] = StripMarkup(line)
    end
    return lines
end

local function BuildDiagnostics()
    return table.concat(BuildDiagnosticLines(), "\n")
end

local function PrintDiagnostics()
    for _, line in ipairs(BuildDiagnosticLines()) do
        Print(line)
    end
end

local diagnosticsFrame

local function EnsureDiagnosticsFrame()
    if diagnosticsFrame then
        return diagnosticsFrame
    end

    local frame = CreateFrame("Frame", "ArinControllerDiagnosticsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 460)
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
    frame.title:SetText("ArinController diagnostics")

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", 24, -44)
    frame.hint:SetWidth(592)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetText("Click Select All, then press Ctrl+C to copy the report. Paste it into a GitHub issue or support message.")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 24, -66)
    scrollFrame:SetPoint("BOTTOMRIGHT", -44, 48)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(566)
    editBox:SetMaxLetters(0)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        frame:Hide()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    -- Read-only: typing into the box restores the report.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and frame.text then
            self:SetText(frame.text)
            self:HighlightText()
        end
    end)
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    -- Clicking anywhere in the text area focuses the box and selects everything.
    scrollFrame:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    function frame:Refresh()
        self.text = BuildDiagnostics()
        self.editBox:SetText(self.text)
        self.editBox:SetCursorPosition(0)
        if self.editBox:HasFocus() then
            self.editBox:HighlightText()
        end
    end

    frame.refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.refresh:SetSize(100, 22)
    frame.refresh:SetPoint("BOTTOMLEFT", 22, 16)
    frame.refresh:SetText("Refresh")
    frame.refresh:SetScript("OnClick", function()
        frame:Refresh()
    end)

    frame.selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.selectAll:SetSize(100, 22)
    frame.selectAll:SetPoint("LEFT", frame.refresh, "RIGHT", 8, 0)
    frame.selectAll:SetText("Select All")
    frame.selectAll:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetSize(100, 22)
    frame.close:SetPoint("BOTTOMRIGHT", -22, 16)
    frame.close:SetText("Close")
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:SetScript("OnHide", function()
        editBox:ClearFocus()
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ArinControllerDiagnosticsFrame")
    end

    frame:Hide()
    diagnosticsFrame = frame
    return frame
end

local function ShowDiagnosticsFrame()
    local frame = EnsureDiagnosticsFrame()
    frame:Show()
    frame:Refresh()
end

ns.PrintDiagnostics = PrintDiagnostics
ns.ShowDiagnosticsFrame = ShowDiagnosticsFrame
