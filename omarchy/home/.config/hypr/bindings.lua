-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Removed applications.
hl.unbind("SUPER + SHIFT + SLASH") -- 1Password
hl.unbind("SUPER + SHIFT + ALT + M") -- cliamp
hl.unbind("SUPER + SHIFT + G") -- Signal
hl.unbind("SUPER + SHIFT + W") -- Omawrite
hl.unbind("SUPER + SHIFT + C") -- HEY Calendar
hl.unbind("SUPER + SHIFT + E") -- HEY Email
hl.unbind("SUPER + SHIFT + ALT + E") -- HEY Compose
hl.unbind("SUPER + SHIFT + CTRL + G") -- Google Messages
hl.unbind("SUPER + SHIFT + P") -- Google Photos
hl.unbind("SUPER + SHIFT + S") -- Google Maps
hl.unbind("SUPER + SHIFT + ALT + G") -- WhatsApp
hl.unbind("SUPER + CTRL + Q") -- Omacalc
hl.unbind("XF86Calculator") -- Omacalc
hl.unbind("SUPER + CTRL + RETURN") -- Herdr
hl.unbind("SUPER + CTRL + K") -- Herdr keybindings
hl.unbind("SUPER + SHIFT + O") -- Obsidian

-- Installed applications.
o.bind("SUPER + SHIFT + S", "Slack", { launch = "zen-browser https://app.slack.com/client" })
hl.unbind("SUPER + SHIFT + M") -- Packaged Spotify launcher
o.bind("SUPER + SHIFT + M", "Spotify", { launch = "zen-browser https://open.spotify.com" })
o.bind("SUPER + CTRL + RETURN", "Hermes Desktop", { launch = "gtk-launch hermes" })

-- Route Omarchy's remaining web shortcuts through Zen instead of Chromium app mode.
hl.unbind("SUPER + SHIFT + A") -- ChatGPT
o.bind("SUPER + SHIFT + A", "ChatGPT", { launch = "zen-browser https://chatgpt.com" })
hl.unbind("SUPER + SHIFT + ALT + A") -- Grok
o.bind("SUPER + SHIFT + ALT + A", "Grok", { launch = "zen-browser https://grok.com" })
hl.unbind("SUPER + SHIFT + Y") -- YouTube
o.bind("SUPER + SHIFT + Y", "YouTube", { launch = "zen-browser https://youtube.com/" })
hl.unbind("SUPER + SHIFT + X") -- X
o.bind("SUPER + SHIFT + X", "X", { launch = "zen-browser https://x.com/" })
hl.unbind("SUPER + SHIFT + ALT + X") -- X Post
o.bind("SUPER + SHIFT + ALT + X", "X Post", { launch = "zen-browser https://x.com/compose/post" })

-- macOS-style application shortcuts. Send explicit synthetic modifiers so the
-- physically held SUPER key is not forwarded to the focused application.
local function send_shortcut_once(mods, key)
  return function()
    local down = { mods = mods or "", key = key, state = "down" }
    local up = { mods = mods or "", key = key, state = "up" }

    hl.dispatch(hl.dsp.send_key_state(down))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state(up))
    end, { timeout = 50, type = "oneshot" })
  end
end

local function active_window_has_tag(name)
  local window = hl.get_active_window()
  if not window then
    return false
  end

  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == name then
      return true
    end
  end

  return false
end

local function active_window_is_terminal()
  return active_window_has_tag("terminal")
end

local function active_window_is_browser()
  local window = hl.get_active_window()
  local class = window and (window.class or ""):lower() or ""
  return active_window_has_tag("firefox-based-browser")
    or active_window_has_tag("chromium-based-browser")
    or class == "zen"
end

local function application_shortcut(default_mods, default_key, terminal_mods, terminal_key)
  return function()
    if terminal_mods and active_window_is_terminal() then
      send_shortcut_once(terminal_mods, terminal_key)()
    else
      send_shortcut_once(default_mods, default_key)()
    end
  end
end

-- Move Hyprland navigation away from SUPER so applications can use it.
hl.unbind("SUPER + LEFT") -- Previously: focus left window
hl.unbind("SUPER + RIGHT") -- Previously: focus right window
hl.unbind("SUPER + UP") -- Previously: focus above window
hl.unbind("SUPER + DOWN") -- Previously: focus below window
o.bind("ALT + SHIFT + LEFT", "Focus left window", hl.dsp.focus({ direction = "l" }))
o.bind("ALT + SHIFT + RIGHT", "Focus right window", hl.dsp.focus({ direction = "r" }))
o.bind("ALT + SHIFT + UP", "Focus above window", hl.dsp.focus({ direction = "u" }))
o.bind("ALT + SHIFT + DOWN", "Focus below window", hl.dsp.focus({ direction = "d" }))

hl.unbind("SUPER + SHIFT + LEFT") -- Previously: swap window left
hl.unbind("SUPER + SHIFT + RIGHT") -- Previously: swap window right
hl.unbind("SUPER + SHIFT + UP") -- Previously: swap window up
hl.unbind("SUPER + SHIFT + DOWN") -- Previously: swap window down
o.bind("CTRL + ALT + SHIFT + LEFT", "Swap window left", hl.dsp.window.swap({ direction = "l" }))
o.bind("CTRL + ALT + SHIFT + RIGHT", "Swap window right", hl.dsp.window.swap({ direction = "r" }))
o.bind("CTRL + ALT + SHIFT + UP", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
o.bind("CTRL + ALT + SHIFT + DOWN", "Swap window down", hl.dsp.window.swap({ direction = "d" }))

-- Preserve displaced compositor actions on explicit management chords.
hl.unbind("SUPER + W") -- Previously: close window
hl.unbind("SUPER + Q") -- Previously: close window
hl.unbind("SUPER + T") -- Previously: toggle floating
hl.unbind("SUPER + F") -- Previously: fullscreen
hl.unbind("SUPER + ALT + F") -- Previously: full width
hl.unbind("SUPER + CTRL + F") -- Previously: tiled full screen
hl.unbind("SUPER + P") -- Previously: pseudo window
hl.unbind("SUPER + O") -- Previously: pop window out
hl.unbind("SUPER + L") -- Previously: workspace layout
hl.unbind("SUPER + S") -- Scratchpad remains on SUPER+grave
hl.unbind("SUPER + G") -- Previously: toggle window grouping
o.bind("SUPER + ALT + W", "Force close window", hl.dsp.window.close())
o.bind("SUPER + ALT + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
o.bind("SUPER + CTRL + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
o.bind("SUPER + CTRL + SHIFT + F", "Tiled full screen", "omarchy-hyprland-window-tiled-fullscreen-toggle")
o.bind("SUPER + CTRL + ALT + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))
o.bind("SUPER + ALT + P", "Pseudo window", hl.dsp.window.pseudo())
o.bind("SUPER + ALT + O", "Pop window out", "omarchy-hyprland-window-pop")
o.bind("SUPER + ALT + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
o.bind("SUPER + CTRL + G", "Toggle window grouping", hl.dsp.group.toggle())

-- Browser history takes precedence for plain horizontal arrows. Everywhere
-- else they move to line boundaries; vertical arrows move to document bounds.
o.bind("SUPER + LEFT", "Back / beginning of line", function()
  if active_window_is_browser() then
    send_shortcut_once("ALT", "LEFT")()
  else
    send_shortcut_once(nil, "HOME")()
  end
end)
o.bind("SUPER + RIGHT", "Forward / end of line", function()
  if active_window_is_browser() then
    send_shortcut_once("ALT", "RIGHT")()
  else
    send_shortcut_once(nil, "END")()
  end
end)
o.bind("SUPER + UP", "Beginning of document", send_shortcut_once("CTRL", "HOME"))
o.bind("SUPER + DOWN", "End of document", send_shortcut_once("CTRL", "END"))
o.bind("SUPER + SHIFT + LEFT", "Select to beginning of line", send_shortcut_once("SHIFT", "HOME"))
o.bind("SUPER + SHIFT + RIGHT", "Select to end of line", send_shortcut_once("SHIFT", "END"))
o.bind("SUPER + SHIFT + UP", "Select to beginning of document", send_shortcut_once("CTRL SHIFT", "HOME"))
o.bind("SUPER + SHIFT + DOWN", "Select to end of document", send_shortcut_once("CTRL SHIFT", "END"))

-- Common Command-key equivalents. Ghostty needs its terminal-specific
-- Ctrl+Shift tab/window chords; normal applications use the Linux Ctrl chord.
o.bind("SUPER + A", "Select all", send_shortcut_once("CTRL", "A"))
o.bind("SUPER + F", "Find", send_shortcut_once("CTRL", "F"))
o.bind("SUPER + G", "Find next", send_shortcut_once("CTRL", "G"))
o.bind("SUPER + SHIFT + G", "Find previous", send_shortcut_once("CTRL SHIFT", "G"))
o.bind("SUPER + L", "Focus location or line", send_shortcut_once("CTRL", "L"))
o.bind("SUPER + N", "New window", application_shortcut("CTRL", "N", "CTRL SHIFT", "N"))
o.bind("SUPER + O", "Open", send_shortcut_once("CTRL", "O"))
o.bind("SUPER + P", "Print", send_shortcut_once("CTRL", "P"))
o.bind("SUPER + R", "Reload", send_shortcut_once("CTRL", "R"))
o.bind("SUPER + SHIFT + R", "Hard reload", send_shortcut_once("CTRL SHIFT", "R"))
o.bind("SUPER + S", "Save", send_shortcut_once("CTRL", "S"))
o.bind("SUPER + T", "New tab", application_shortcut("CTRL", "T", "CTRL SHIFT", "T"))
o.bind("SUPER + SHIFT + T", "Reopen closed tab", send_shortcut_once("CTRL SHIFT", "T"))
o.bind("SUPER + W", "Close tab or window", application_shortcut("CTRL", "W", "CTRL SHIFT", "W"))
o.bind("SUPER + SHIFT + W", "Close application window", send_shortcut_once("CTRL SHIFT", "W"))
o.bind("SUPER + Q", "Quit application", application_shortcut("CTRL", "Q", "CTRL SHIFT", "Q"))
o.bind("SUPER + Z", "Undo", send_shortcut_once("CTRL", "Z"))
o.bind("SUPER + SHIFT + Z", "Redo", send_shortcut_once("CTRL SHIFT", "Z"))

-- Use the physical microphone key as push-to-talk dictation.
hl.unbind("XF86AudioMicMute") -- Previously: mute microphone
o.bind("XF86AudioMicMute", "Start dictation (push-to-talk)", "voxtype record start")
o.bind("XF86AudioMicMute", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")
