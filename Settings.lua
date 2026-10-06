-- The addon's page in the game's Settings window
local _, ns = ...

local PADDLE_COUNT = ns.PADDLE_COUNT
local Print = ns.Print
local GetPaddleKey = ns.GetPaddleKey
local GetKeyDisplayName = ns.GetKeyDisplayName
local UpdatePanelVisibility = ns.UpdatePanelVisibility
local StartKeyCapture = ns.StartKeyCapture
local ToggleGuideFrame = ns.ToggleGuideFrame
local ApplyAppearance = ns.ApplyAppearance
local SetUnlocked = ns.SetUnlocked
local ResetPosition = ns.ResetPosition
local ShowDiagnosticsFrame = ns.ShowDiagnosticsFrame
local GetProfileList = ns.GetProfileList
local GetActiveProfile = ns.GetActiveProfile
local CreateProfile = ns.CreateProfile
local SwitchProfile = ns.SwitchProfile
local CopyProfileInto = ns.CopyProfileInto
local DeleteProfile = ns.DeleteProfile

-- Everything lives on one canvas page built from plain widgets. Forever's
-- vertical-layout settings list hangs the client when the Settings window is
-- closed in gamepad mode after that page was shown (canvas pages such as
-- ChattyLittleNpc's do not), and its subcategories crash the gamepad
-- smart-navigation cursor (ScrollUtil.lua IsSelected on a released list button).
local function RegisterSettings()
    if ns.settingsRegistered or not Settings or type(Settings.RegisterCanvasLayoutCategory) ~= "function" then
        return
    end

    ns.settingsRegistered = true

    -- Hidden until the Settings window displays it, so OnShow always fires.
    local panel = CreateFrame("Frame")
    panel.name = "ArinController"
    panel:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(560, 1)
    scrollFrame:SetScrollChild(content)

    -- Each control registers a function that reloads it from ArinControllerDB.
    local refreshers = {}
    local y = -6
    local sliderCount = 0

    local note = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 6, y)
    note:SetWidth(540)
    note:SetJustifyH("LEFT")
    note:SetText("With a controller, use the mouse on this page. The gamepad cursor cannot enter it without freezing Forever when Settings is closed. Paddle keys, lock/unlock and reset also work through /arincontroller.")
    y = y - 34

    local function AttachTooltip(control, label, tooltip)
        control:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        control:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local function AddSection(label)
        y = y - 12
        local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 6, y)
        header:SetText(label)
        y = y - 26
        return header
    end

    local function AddCheckbox(key, label, tooltip, onChange)
        local checkbox = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", 14, y)
        checkbox.Text:SetText(label)
        checkbox:SetScript("OnClick", function(self)
            ArinControllerDB[key] = self:GetChecked() and true or false
            onChange(ArinControllerDB[key])
        end)
        AttachTooltip(checkbox, label, tooltip)
        table.insert(refreshers, function()
            checkbox:SetChecked(ArinControllerDB[key] == true)
        end)
        y = y - 30
    end

    -- OptionsSliderTemplate needs a global name on Classic-derived clients.
    local function AddSlider(key, label, minValue, maxValue, step, tooltip)
        sliderCount = sliderCount + 1
        y = y - 16
        local slider = CreateFrame("Slider", "ArinControllerSettingsSlider" .. sliderCount, content, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 22, y)
        slider:SetWidth(250)
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        if slider.Low then
            slider.Low:SetText(string.format("%.2f", minValue))
        end
        if slider.High then
            slider.High:SetText(string.format("%.2f", maxValue))
        end

        local function UpdateLabel(value)
            slider.Text:SetText(string.format("%s: %.2f", label, value))
        end

        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / step + 0.5) * step
            UpdateLabel(value)
            -- Refreshing the page calls SetValue too; only real changes apply.
            if math.abs((tonumber(ArinControllerDB[key]) or 0) - value) > 0.001 then
                ArinControllerDB[key] = value
                ApplyAppearance()
            end
        end)
        AttachTooltip(slider, label, tooltip)
        table.insert(refreshers, function()
            local value = tonumber(ArinControllerDB[key]) or minValue
            slider:SetValue(value)
            UpdateLabel(value)
        end)
        y = y - 40
    end

    -- buttonText may be a function so the paddle rows can show the current key.
    local function AddButton(label, buttonText, onClick, tooltip)
        local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 20, y - 5)
        text:SetText(label)

        local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        button:SetSize(180, 22)
        button:SetPoint("TOPLEFT", 250, y)
        button:SetScript("OnClick", onClick)
        AttachTooltip(button, label, tooltip)
        if type(buttonText) == "function" then
            table.insert(refreshers, function()
                button:SetText(buttonText())
            end)
        else
            button:SetText(buttonText)
        end
        y = y - 28
        return button, text
    end

    -- Custom dropdown list. The dropdown widget keeps only Blizzard's artwork (see
    -- AddDropdown below); the list itself is our own frames, so nothing here rides
    -- Blizzard's MenuProxy/FrameControlsManager path that ends at the protected
    -- SetOverrideBindingClick call (PulseHaptics Popup.lua documents the trace).
    -- https://github.com/Stanzilla/WoWUIBugs/issues/299 / TaintLess DisplayModeTaint.
    local POPUP_STRATA = "FULLSCREEN_DIALOG"
    local ENTRY_HEIGHT = 22
    local LIST_PADDING = 4
    local TEXT_INSET = 10

    local popupCatcher
    local popupList
    local popupEntries = {}
    local popupState = {}

    local function MarkGatewayIgnored(frame)
        if frame and type(SmartNavigation_MarkFrameIgnored) == "function" then
            pcall(SmartNavigation_MarkFrameIgnored, frame)
        end
    end

    local function ClosePopup()
        if popupCatcher then
            popupCatcher:Hide()
        end
        popupState.onSelect = nil
        popupState.owner = nil
    end

    local function EnsurePopup()
        if popupList then
            return
        end

        popupCatcher = CreateFrame("Button", nil, UIParent)
        popupCatcher:SetAllPoints(UIParent)
        popupCatcher:SetFrameStrata(POPUP_STRATA)
        popupCatcher:Hide()
        popupCatcher:SetScript("OnClick", ClosePopup)
        MarkGatewayIgnored(popupCatcher)

        popupList = CreateFrame("Frame", nil, popupCatcher, "BackdropTemplate")
        popupList:SetFrameLevel(popupCatcher:GetFrameLevel() + 10)
        popupList:EnableMouse(true)
        if popupList.SetBackdrop then
            popupList:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 },
            })
        end
        MarkGatewayIgnored(popupList)
    end

    -- Option: { value, label }. Selected value checked for the checkmark.
    local function OpenList(owner, options, selectedValue, onSelect)
        EnsurePopup()
        if popupState.owner == owner and popupCatcher:IsShown() then
            ClosePopup()
            return
        end
        popupState.owner = owner
        popupState.onSelect = onSelect

        local shown = 0
        local widest = 0
        for index, option in ipairs(options) do
            local entry = popupEntries[index]
            if not entry then
                entry = CreateFrame("Button", nil, popupList, "UIPanelButtonTemplate")
                entry:SetHeight(ENTRY_HEIGHT)
                entry:SetScript("OnClick", function(self)
                    local handler = popupState.onSelect
                    ClosePopup()
                    if handler then
                        handler(self.value)
                    end
                end)
                MarkGatewayIgnored(entry)
                popupEntries[index] = entry
            end
            entry.value = option.value
            local selected = option.value == selectedValue
            entry:SetText((selected and "> " or "  ") .. option.label)
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", popupList, "TOPLEFT", 2, -((index - 1) * ENTRY_HEIGHT) - 2)
            entry:SetPoint("RIGHT", popupList, "RIGHT", -2, 0)
            entry:Show()
            shown = index
            local width = entry:GetFontString() and entry:GetFontString():GetStringWidth() or 0
            if width > widest then
                widest = width
            end
        end
        for index = shown + 1, #popupEntries do
            popupEntries[index]:Hide()
        end

        local ownerWidth = (owner.GetWidth and owner:GetWidth()) or 140
        local width = math.max(ownerWidth, widest + TEXT_INSET + 16)
        popupList:SetSize(width, shown * ENTRY_HEIGHT + LIST_PADDING * 2)

        local ownerBottom = (owner.GetBottom and owner:GetBottom()) or 0
        local ownerTop = (owner.GetTop and owner:GetTop()) or 0
        local uiHeight = (UIParent.GetHeight and UIParent:GetHeight()) or 768
        popupList:ClearAllPoints()
        if ownerBottom - popupList:GetHeight() < 30 and uiHeight - ownerTop > ownerBottom then
            popupList:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, -2)
        else
            popupList:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
        end
        popupList:Show()
        popupCatcher:Show()
    end

    -- A Blizzard-looking dropdown row that opens our own list instead of
    -- Blizzard's menu: the button is fully self-built (no template artwork that
    -- fights our anchors, no SetupMenu/UIDropDownMenu wiring), and clicking just
    -- calls OpenList above. getOptions supplies { value, label }; getSelected
    -- marks the current row; onSelect receives the picked value; getText feeds
    -- the button label and the refreshers.
    local function AddDropdown(label, getOptions, getSelected, onSelect, getText)
        y = y - 12
        local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 6, y)
        header:SetText(label)
        y = y - 24

        local dropdown = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        dropdown:SetSize(300, 22)
        dropdown:SetPoint("TOPLEFT", 20, y)

        dropdown.Value = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dropdown.Value:SetPoint("LEFT", dropdown, "LEFT", 10, 0)
        dropdown.Value:SetJustifyH("LEFT")

        dropdown.Arrow = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dropdown.Arrow:SetPoint("RIGHT", dropdown, "RIGHT", -10, 0)
        dropdown.Arrow:SetText("v")

        local function setText(text)
            dropdown.Value:SetText(text)
        end

        dropdown:SetScript("OnMouseDown", function(self)
            if not getOptions or #getOptions() == 0 then
                return
            end
            OpenList(self, getOptions(), getSelected(), function(value)
                onSelect(value)
                setText(getText())
            end)
        end)

        setText(getText())
        table.insert(refreshers, function()
            setText(getText())
        end)

        y = y - 36
        return dropdown
    end

    AddSection("Profiles")

    local createType = "elite"
    local typeDropdown
    local activeDropdown

    typeDropdown = AddDropdown(
        "Controller type",
        function()
            return {
                { value = "elite", label = "Xbox Elite" },
                { value = "standard", label = "Xbox Standard" },
            }
        end,
        function()
            return createType
        end,
        function(value)
            createType = value
        end,
        function()
            return createType == "standard" and "Xbox Standard" or "Xbox Elite"
        end
    )

    AddButton(
        "Create new profile",
        "Create",
        function()
            local profile = CreateProfile(createType)
            if profile then
                Print("Created profile: " .. profile.name .. ". Pick it in 'Active profile' to use it.")
            else
                Print("Failed to create profile.")
            end
        end,
        "Creates a new, fully unbound " .. (createType == "standard" and "Xbox Standard" or "Xbox Elite") .. " profile. The A/B/X/Y buttons stay on the game's hard-coded defaults; all other buttons are unbound until you assign them."
    )

    activeDropdown = AddDropdown(
        "Active profile",
        function()
            local options = {}
            for _, item in ipairs(GetProfileList()) do
                options[#options + 1] = { value = item.id, label = item.name }
            end
            return options
        end,
        function()
            local active = GetActiveProfile()
            return active and active.id or nil
        end,
        function(id)
            SwitchProfile(id)
        end,
        function()
            local active = GetActiveProfile()
            return active and active.name or "None"
        end
    )

    -- One shared target for copy and delete: every profile except the active
    -- one. Copy overwrites the target's data but keeps its name; the target
    -- keeps its own controller type.
    local targetId
    local function GetTargetProfile()
        local active = GetActiveProfile()
        local list = GetProfileList()
        if targetId then
            for _, item in ipairs(list) do
                if item.id == targetId and (not active or item.id ~= active.id) then
                    return item
                end
            end
        end
        for _, item in ipairs(list) do
            if not active or item.id ~= active.id then
                return item
            end
        end
        return nil
    end

    AddDropdown(
        "Target profile",
        function()
            local active = GetActiveProfile()
            local options = {}
            for _, item in ipairs(GetProfileList()) do
                if not active or item.id ~= active.id then
                    options[#options + 1] = { value = item.id, label = item.name }
                end
            end
            return options
        end,
        function()
            local target = GetTargetProfile()
            return target and target.id or nil
        end,
        function(id)
            targetId = id
        end,
        function()
            local target = GetTargetProfile()
            return target and target.name or "None"
        end
    )

    AddButton(
        "Copy current profile into target",
        "Copy",
        function()
            local target = GetTargetProfile()
            if not target then
                Print("No other profile to copy into. Create one first.")
                return
            end
            local ok, newName = CopyProfileInto(target.id)
            if ok then
                Print("Copied the active profile into " .. tostring(newName) .. ".")
            else
                Print("Copy failed. The active profile cannot be its own target.")
            end
            if ns.RefreshSettingsKeyRows then
                ns.RefreshSettingsKeyRows()
            end
        end,
        "Overwrites the target profile's buttons and paddles with a copy of the active profile. The target keeps its own name and controller type, so a Standard target drops the Elite back paddles. The reserved base X/Y/A/B buttons are never copied."
    )

    AddButton(
        "Delete target profile",
        "Delete",
        function()
            local target = GetTargetProfile()
            if not target then
                Print("No other profile to delete.")
                return
            end
            if DeleteProfile(target.id) then
                Print("Deleted profile: " .. target.name)
                targetId = nil
            else
                Print("Cannot delete the active profile or the last profile.")
            end
            if ns.RefreshSettingsKeyRows then
                ns.RefreshSettingsKeyRows()
            end
        end,
        "Deletes the target profile. The active profile and the last remaining profile cannot be deleted."
    )

    AddSection("Layout")

    AddCheckbox(
        "unlocked",
        "Unlock panels outside Edit Mode",
        "Normally ArinController unlocks automatically while WoW Edit Mode is open. Enable this to move the four panels independently without opening Edit Mode.",
        function(value)
            SetUnlocked(value)
        end
    )

    AddButton(
        "Panel positions",
        "Reset All",
        function()
            ResetPosition()
        end,
        "Moves all four paddle panels back to their default spots inside the native crossbar: each panel above the centre of the bar that uses the same trigger combination, LT + RT in the middle of the cross."
    )

    AddCheckbox(
        "gamepadOnly",
        "Only show in gamepad mode",
        "Hides the paddle panels while the interface is in mouse and keyboard mode. They stay visible while unlocked or in Edit Mode.",
        function()
            UpdatePanelVisibility()
        end
    )

    -- Captured so the whole section can hide while a Standard profile is
    -- active: a standard controller has no back paddles to assign.
    local paddleHeader = AddSection("Paddle inputs")
    local paddleControls = { paddleHeader }

    for paddleIndex = 1, PADDLE_COUNT do
        local button, text = AddButton(
            "Paddle P" .. paddleIndex,
            function()
                return GetKeyDisplayName(GetPaddleKey(paddleIndex))
            end,
            function()
                StartKeyCapture(paddleIndex, false)
            end,
            "Shows the input that triggers this paddle. Click it, then press the paddle to assign a new one."
        )
        paddleControls[#paddleControls + 1] = button
        paddleControls[#paddleControls + 1] = text
    end

    local assignAllButton, assignAllText = AddButton(
        "Assign all four in order",
        "Assign P1-P4",
        function()
            StartKeyCapture(1, true)
        end,
        "Prompts for P1, P2, P3, and P4 one after another."
    )
    paddleControls[#paddleControls + 1] = assignAllButton
    paddleControls[#paddleControls + 1] = assignAllText

    local guideButton, guideText = AddButton(
        "How to set up the paddles",
        "Setup guide",
        function()
            ToggleGuideFrame()
        end,
        "Step-by-step instructions for the Xbox Accessories app, plus a live readout of what WoW receives when you press a paddle."
    )
    paddleControls[#paddleControls + 1] = guideButton
    paddleControls[#paddleControls + 1] = guideText

    table.insert(refreshers, function()
        local active = GetActiveProfile()
        local hide = active ~= nil and active.controllerType == "standard"
        for _, control in ipairs(paddleControls) do
            if hide then
                control:Hide()
            else
                control:Show()
            end
        end
    end)

    AddSection("Paddle HUD")

    AddSlider(
        "hudScale",
        "HUD scale",
        0.65, 1.50, 0.05,
        "Scales all four ArinController panels. 1.00 matches the size of the native crossbar slots."
    )

    AddSlider(
        "inactiveOpacity",
        "Inactive panel opacity",
        0.10, 1.0, 0.05,
        "Fades the three unfocused panels. The native crossbar does not fade unfocused bars, so 1.00 is the default."
    )

    AddCheckbox(
        "highlightActivePanel",
        "Highlight focused panel",
        "Draws the native crossbar focus highlight behind the BASE, LT, RT, or LT + RT panel that is currently active. Also respects the game's own action bar highlight setting.",
        function()
            ApplyAppearance()
        end
    )

    AddSlider(
        "highlightStrength",
        "Focus highlight strength",
        0.0, 1.0, 0.05,
        "Adjusts the strength of the focus highlight. 1.00 matches the native crossbar."
    )

    AddCheckbox(
        "showPanelLabels",
        "Show LT / RT modifier icons",
        "Adds LT, RT, and LT + RT controller prompts below the paddle panels. Off by default because the native crossbar already shows those prompts next to the default panel positions.",
        function()
            ApplyAppearance()
        end
    )

    AddCheckbox(
        "showPaddleBadges",
        "Show paddle prompts on the focused panel",
        "Shows the small P1-P4 glyph on assigned actions of the focused panel, like the native button prompts. Also respects the game's own action bar button prompt setting.",
        function()
            ApplyAppearance()
        end
    )

    AddSection("Diagnostics")

    AddButton(
        "Gamepad integration",
        "View Diagnostics",
        function()
            ShowDiagnosticsFrame()
        end,
        "Shows native storage, LT/RT detection, and native art status as plain text you can select and copy (Ctrl+C) into a bug report. Same as /arincontroller diag copy; /arincontroller diag prints it to chat."
    )

    content:SetHeight(-y + 10)

    local function RefreshControls()
        for _, refresh in ipairs(refreshers) do
            refresh()
        end
    end
    -- Deliberately not announced to the gamepad cursor (SmartNavigation). Once
    -- this page's controls are in its button list, closing Settings with the
    -- controller (B, or A on Close) hangs the client for the rest of the
    -- session. The controls are created at login and only reparented into the
    -- Settings window, so the cursor never picks them up on its own.
    panel:SetScript("OnShow", RefreshControls)

    -- Keeps the page in step with slash commands and press-to-assign while open.
    ns.RefreshSettingsKeyRows = function()
        if panel:IsVisible() then
            RefreshControls()
        end
    end

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end

local function OpenSettings()
    if not ns.settingsRegistered then
        RegisterSettings()
    end

    if ns.settingsCategory and Settings and type(Settings.OpenToCategory) == "function" then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
    else
        Print("The native Settings UI is not available yet.")
    end
end

ns.RegisterSettings = RegisterSettings
ns.OpenSettings = OpenSettings
