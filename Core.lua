-- Shared constants, state and helpers. Loaded first: the other files take
-- what they need from the addon namespace (ns); see the end of each file.
local ADDON_NAME, ns = ...

local PANEL_COUNT = 4
local PADDLE_COUNT = 4
local MEDIA_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

-- Slot metrics mirror Blizzard_GamepadActionBars/ActionBarStyles.lua so the
-- paddle slots match the circle (face button) slots of the native crossbar.
-- Bars that are not focused are "collapsed"; the focused bar is "expanded".
local LAYOUT = {
    BUTTON_SIZE_COLLAPSED = 32,
    BUTTON_SIZE_EXPANDED = 40,
    BUTTON_PRESSED_SIZE_OFFSET = 4,
    SHADOW_DISTANCE_COLLAPSED = 4,
    SHADOW_DISTANCE_EXPANDED = 13,
    GRID_SPACING_COLLAPSED = 46,
    GRID_SPACING_EXPANDED = 56,
    GRID_CENTER_Y = 12,
    PROMPT_ICON_SIZE = 15,
    EMPTY_GLYPH_RATIO = 0.62,
    FOCUS_FADE_DURATION = 0.33,
    FOCUS_SHADOW_MIN_ALPHA = 0.4,
    FOCUS_BACKGROUND_ALPHA = 0.375,
    FOCUS_BACKGROUND_WIDTH = 190,
    FOCUS_BACKGROUND_HEIGHT = 176,
    MODIFIER_ICON_Y = -54,
    PANEL_WIDTH = 136,
    PANEL_HEIGHT = 152,
}

-- Native crossbar art (Blizzard_GamepadActionBars). Every atlas has a fallback
-- so the addon keeps working on builds that rename or remove one of them.
local ATLAS = {
    border = "gamepad-actionbar-circleslot-border-normal",
    borderPressed = "gamepad-actionbar-circleslot-border-pressed",
    borderHover = "gamepad-actionbar-circleslot-border-hover",
    shadow = "gamepad-actionbar-circleslot-dropshadow",
    shadowFocus = "gamepad-actionbar-focus-bg-circ",
    focusBackground = "gamepad-actionbar-focus-bg-section",
    editGlow = "gamepad-actionbar-fx-controls-behind",
    circleMask = "CircleMask",
}

-- Paddle glyphs are the addon's own Media\P1-P4 textures: the native
-- Gamepad_Gen_Paddle atlases are plain "P1" text, the addon draws each paddle's
-- shape in the same button style.

local NATIVE_CVAR_SCALING = "GamepadShowActionBarScaling"
local NATIVE_CVAR_HIGHLIGHT = "GamepadShowActionBarHighlight"
local NATIVE_CVAR_PROMPTS = "GamepadShowActionBarButtonPrompts"

local PANELS = {
    { key = "BASE", label = "BASE", lt = false, rt = false },
    { key = "LT", label = "LT", lt = true, rt = false },
    { key = "RT", label = "RT", lt = false, rt = true },
    { key = "BOTH", label = "LT + RT", lt = true, rt = true },
}

-- Inputs a paddle can be assigned to. On Windows the Elite Series 2 does not
-- report its paddles to games; WoW only sees whatever the Xbox Accessories
-- app (or Steam Input / reWASD) maps a paddle to. Only inputs the native
-- gamepad UI never uses are offered, so a paddle can never steal a button.
local PADDLE_KEY_OPTIONS = {
    { value = "PADPADDLE1", label = "Paddle P1 (native)", note = "Only for controllers that report paddles to WoW. The Elite Series 2 on Windows does not." },
    { value = "PADPADDLE2", label = "Paddle P2 (native)", note = "Only for controllers that report paddles to WoW. The Elite Series 2 on Windows does not." },
    { value = "PADPADDLE3", label = "Paddle P3 (native)", note = "Only for controllers that report paddles to WoW. The Elite Series 2 on Windows does not." },
    { value = "PADPADDLE4", label = "Paddle P4 (native)", note = "Only for controllers that report paddles to WoW. The Elite Series 2 on Windows does not." },
    { value = "PADSOCIAL", label = "Share button", note = "Unused by the native gamepad UI. Map a paddle to Share in Xbox Accessories if the app offers it for your controller." },
    { value = "PAD5", label = "Extra face button 5", note = "Unused by the native gamepad UI. Only some controllers or remapping tools can send it." },
    { value = "PAD6", label = "Extra face button 6", note = "Unused by the native gamepad UI. Only some controllers or remapping tools can send it." },
}
for fkey = 13, 24 do
    PADDLE_KEY_OPTIONS[#PADDLE_KEY_OPTIONS + 1] = {
        value = "F" .. fkey,
        label = "Keyboard F" .. fkey,
        note = "For Steam Input or reWASD sending the paddle as a keyboard key. Nothing in WoW uses F13-F24.",
    }
end
-- Physical keyboard keys that WoW leaves unbound by default. The Xbox
-- Accessories app can map a paddle to a keyboard key you press, so these are
-- the practical choices without extra software. Bound keys are refused.
local PHYSICAL_KEY_OPTIONS = {
    { value = "NUMPAD0", label = "Keyboard Numpad 0" }, { value = "NUMPAD1", label = "Keyboard Numpad 1" },
    { value = "NUMPAD2", label = "Keyboard Numpad 2" }, { value = "NUMPAD3", label = "Keyboard Numpad 3" },
    { value = "NUMPAD4", label = "Keyboard Numpad 4" }, { value = "NUMPAD5", label = "Keyboard Numpad 5" },
    { value = "NUMPAD6", label = "Keyboard Numpad 6" }, { value = "NUMPAD7", label = "Keyboard Numpad 7" },
    { value = "NUMPAD8", label = "Keyboard Numpad 8" }, { value = "NUMPAD9", label = "Keyboard Numpad 9" },
    { value = "NUMPADDECIMAL", label = "Keyboard Numpad ." }, { value = "NUMPADDIVIDE", label = "Keyboard Numpad /" },
    { value = "NUMPADMULTIPLY", label = "Keyboard Numpad *" },
    { value = "SCROLLLOCK", label = "Keyboard Scroll Lock" }, { value = "PAUSE", label = "Keyboard Pause" },
    { value = "F6", label = "Keyboard F6" }, { value = "F7", label = "Keyboard F7" }, { value = "F8", label = "Keyboard F8" },
    { value = "F9", label = "Keyboard F9" }, { value = "F10", label = "Keyboard F10" },
    { value = "F11", label = "Keyboard F11" }, { value = "F12", label = "Keyboard F12" },
    { value = "PAGEUP", label = "Keyboard Page Up" }, { value = "PAGEDOWN", label = "Keyboard Page Down" },
}
for _, option in ipairs(PHYSICAL_KEY_OPTIONS) do
    option.note = "A real key the Xbox Accessories app can map a paddle to. Accepted only while nothing in WoW is bound to it."
    PADDLE_KEY_OPTIONS[#PADDLE_KEY_OPTIONS + 1] = option
end
PADDLE_KEY_OPTIONS[#PADDLE_KEY_OPTIONS + 1] = { value = "NONE", label = "Not assigned", note = "This paddle slot is shown but never triggered." }

-- Controller inputs the native Forever gamepad UI relies on. A paddle that
-- arrives as one of these is being mirrored by the controller profile.
local NATIVE_RESERVED_KEYS = {
    PAD1 = "A button", PAD2 = "B button", PAD3 = "X button", PAD4 = "Y button",
    PADDUP = "D-pad up", PADDDOWN = "D-pad down", PADDLEFT = "D-pad left", PADDRIGHT = "D-pad right",
    PADLSHOULDER = "Left bumper (LB)", PADRSHOULDER = "Right bumper (RB)",
    PADLTRIGGER = "Left trigger (LT)", PADRTRIGGER = "Right trigger (RT)",
    PADLSTICK = "Left stick click", PADRSTICK = "Right stick click",
    PADLSTICKUP = "Left stick up", PADLSTICKDOWN = "Left stick down", PADLSTICKLEFT = "Left stick left", PADLSTICKRIGHT = "Left stick right",
    PADRSTICKUP = "Right stick up", PADRSTICKDOWN = "Right stick down", PADRSTICKLEFT = "Right stick left", PADRSTICKRIGHT = "Right stick right",
    PADBACK = "View button", PADFORWARD = "Menu button", PADSYSTEM = "Xbox button",
}

local addon = CreateFrame("Frame")
local secureDriver = CreateFrame("Frame", "ArinControllerSecureDriver", UIParent, "SecureHandlerStateTemplate")
local panelFrames = {}
local buttons = {}
-- Native crossbar focus routing, filled in by FocusRouting.lua.
local focusRouting = { enabled = false, routers = {} }
local missingAtlases = {}

-- State that several files change. It lives on the namespace so every file
-- sees the current value; the files alias the tables and functions above
-- instead, because those are never replaced.
ns.editModeActive = false
ns.pendingSecureRefresh = false
ns.pendingAppearanceRefresh = false
ns.nativeStorageEnabled = false
ns.nativeStorageSlots = {}
ns.nativeStorageStatus = "not initialized"
ns.ltButtonIndex = nil
ns.rtButtonIndex = nil
ns.nativeHookStatus = "not attempted"
ns.lastBoundPanel = 1
ns.securePanelDriverRegistered = false
ns.settingsCategory = nil
ns.settingsRegistered = false
ns.editModeCallbacksRegistered = false
ns.nativeModifierCallbackRegistered = false
ns.visualDetectionMethod = "not initialized"
ns.inputWatcher = nil

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd8ffArinController|r: " .. tostring(message))
end

local function GetMedia(name)
    return MEDIA_PATH .. name
end

local function GetPaddleTexture(index)
    return GetMedia("P" .. index)
end

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local ok, a, b, c, d = pcall(func, ...)
    if not ok then
        return nil
    end
    return a, b, c, d
end

-- Forever hands addons "secret" numbers and booleans for some combat data
-- (cooldowns, usability, range). They can be passed straight to widgets such
-- as Cooldown:SetCooldown or FontString:SetText, but comparing them, doing
-- arithmetic on them, or using them as a condition raises a Lua error.
local function IsSecret(value)
    if type(issecretvalue) == "function" then
        return issecretvalue(value) == true
    end
    -- Older clients have no predicate; probe with the operations a secret
    -- value refuses. Nothing here touches the value outside the pcall.
    local ok = pcall(function()
        return value == nil or not value
    end)
    return not ok
end

-- Sets or clears a cooldown the way Blizzard_ActionBar/ActionButton.lua does:
-- "active" is a plain boolean decided by the client, and the timing values are
-- forwarded untouched so they may be secret. SetCooldown is the only thing
-- allowed to look at them, so a rejected call simply clears the swipe.
local function ApplyCooldown(cooldown, active, startTime, duration, modRate)
    if IsSecret(active) then
        active = true
    end
    if active then
        local ok = pcall(cooldown.SetCooldown, cooldown, startTime, duration, modRate)
        if ok then
            return
        end
    end
    if cooldown.Clear then
        cooldown:Clear()
    else
        cooldown:SetCooldown(0, 0)
    end
end

-- Turns a legacy (startTime, duration, enable) triple into the "active" flag
-- used by ApplyCooldown. Secret values cannot be inspected, so they are
-- handed to SetCooldown as-is; a zero duration renders as no cooldown.
local function LegacyCooldownActive(startTime, duration, enable)
    if IsSecret(enable) or IsSecret(duration) or IsSecret(startTime) then
        return true
    end
    if startTime == nil or duration == nil then
        return false
    end
    if enable == false or enable == 0 then
        return false
    end
    return duration > 0
end

local function AtlasExists(name)
    if type(name) ~= "string" or not C_Texture or type(C_Texture.GetAtlasInfo) ~= "function" then
        return false
    end
    return SafeCall(C_Texture.GetAtlasInfo, name) ~= nil
end

-- Applies a native atlas when the client has it, otherwise the bundled TGA.
-- Returns true when the native art is in use. Textures without any usable art
-- are flagged so the layout code never shows them.
local function ApplyArt(texture, atlas, fallbackFile)
    if AtlasExists(atlas) then
        texture:SetAtlas(atlas)
        texture.artAvailable = true
        return true
    end

    if atlas and not missingAtlases[atlas] then
        missingAtlases[atlas] = true
        missingAtlases.count = (missingAtlases.count or 0) + 1
    end

    if fallbackFile then
        texture:SetTexture(fallbackFile)
        texture.artAvailable = true
    else
        texture:SetTexture(nil)
        texture.artAvailable = false
    end
    return false
end

local function GetNativeCVarBool(name, default)
    local value
    if C_CVar and type(C_CVar.GetCVar) == "function" then
        value = SafeCall(C_CVar.GetCVar, name)
    elseif type(GetCVar) == "function" then
        value = SafeCall(GetCVar, name)
    end

    if value == nil then
        return default
    end
    return value == "1" or value == 1 or value == true
end

local function IsEditable()
    return (ArinControllerDB and ArinControllerDB.unlocked == true) or ns.editModeActive
end

-- Returns the binding key a paddle listens for, or nil when unassigned.
local function GetPaddleKey(paddleIndex)
    local key = ArinControllerDB and ArinControllerDB.paddleKeys and ArinControllerDB.paddleKeys["P" .. paddleIndex]
    if type(key) ~= "string" then
        return nil
    end
    key = key:upper()
    if key == "" or key == "NONE" or NATIVE_RESERVED_KEYS[key] then
        return nil
    end
    return key
end

local function GetKeyDisplayName(key)
    if not key or key == "" or key:upper() == "NONE" then
        return "Not assigned"
    end
    key = key:upper()
    for _, option in ipairs(PADDLE_KEY_OPTIONS) do
        if option.value == key then
            return option.label
        end
    end
    if NATIVE_RESERVED_KEYS[key] then
        return NATIVE_RESERVED_KEYS[key]
    end
    return "Keyboard " .. key
end

local function GetKeyNote(key)
    key = key and key:upper() or ""
    for _, option in ipairs(PADDLE_KEY_OPTIONS) do
        if option.value == key then
            return option.note
        end
    end
    if NATIVE_RESERVED_KEYS[key] then
        return "Used by the native gamepad UI; paddles cannot take it over."
    end
    return nil
end

-- Returns true when a key may drive a paddle, otherwise false and a reason.
-- Allowed: the native paddle keys, Share, extra face buttons, F13-F24, and
-- keyboard keys that currently have no binding at all.
local function IsPaddleKeyAllowed(key)
    key = key and key:upper() or ""
    if key == "" or key == "NONE" then
        return true
    end
    if NATIVE_RESERVED_KEYS[key] then
        return false, string.format(
            "%s is used by the native gamepad UI, so it cannot drive a paddle. The controller is sending this paddle as %s: in Xbox Accessories map the paddle to a keyboard key WoW does not use (F9-F12 for example) or to Share.",
            NATIVE_RESERVED_KEYS[key], NATIVE_RESERVED_KEYS[key]
        )
    end
    for _, option in ipairs(PADDLE_KEY_OPTIONS) do
        if option.value == key and (key:match("^PAD") or key:match("^F1[3-9]$") or key:match("^F2[0-4]$")) then
            return true
        end
    end
    if key:match("^PAD") then
        return false, key .. " is a controller input the addon does not know; only Share, extra face buttons, and the native paddle keys are allowed."
    end

    -- Look at the regular binding only; the addon's own override bindings
    -- (CLICK ArinControllerButton...) must not block reassigning a paddle.
    local action = type(GetBindingAction) == "function" and GetBindingAction(key, false) or nil
    if action and action:match("^CLICK ArinController") then
        action = nil
    end
    if action and action ~= "" then
        local actionName = action
        if type(GetBindingName) == "function" then
            actionName = GetBindingName(action) or action
        end
        return false, string.format(
            "Keyboard key %s is already bound to %s. Map the paddle to an unused key such as F9-F12 instead.",
            key, tostring(actionName)
        )
    end
    return true
end

ns.PANEL_COUNT = PANEL_COUNT
ns.PADDLE_COUNT = PADDLE_COUNT
ns.LAYOUT = LAYOUT
ns.ATLAS = ATLAS
ns.NATIVE_CVAR_SCALING = NATIVE_CVAR_SCALING
ns.NATIVE_CVAR_HIGHLIGHT = NATIVE_CVAR_HIGHLIGHT
ns.NATIVE_CVAR_PROMPTS = NATIVE_CVAR_PROMPTS
ns.PANELS = PANELS
ns.addon = addon
ns.secureDriver = secureDriver
ns.panelFrames = panelFrames
ns.buttons = buttons
ns.focusRouting = focusRouting
ns.missingAtlases = missingAtlases
ns.Print = Print
ns.GetMedia = GetMedia
ns.GetPaddleTexture = GetPaddleTexture
ns.SafeCall = SafeCall
ns.IsSecret = IsSecret
ns.ApplyCooldown = ApplyCooldown
ns.LegacyCooldownActive = LegacyCooldownActive
ns.AtlasExists = AtlasExists
ns.ApplyArt = ApplyArt
ns.GetNativeCVarBool = GetNativeCVarBool
ns.IsEditable = IsEditable
ns.GetPaddleKey = GetPaddleKey
ns.GetKeyDisplayName = GetKeyDisplayName
ns.GetKeyNote = GetKeyNote
ns.IsPaddleKeyAllowed = IsPaddleKeyAllowed
