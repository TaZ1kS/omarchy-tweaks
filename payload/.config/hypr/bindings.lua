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

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")

-- Clipboard history: SUPER + V (was: universal paste).
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")

-- Emoji picker: SUPER + PERIOD.
o.bind("SUPER + PERIOD", "Emojis", "omarchy-shell shell toggle omarchy.emojis")

-- Screenshot: SUPER + SHIFT + S (was: Google Maps).
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")

-- GridCraft: SUPER + G (was: Toggle window grouping).
hl.unbind("SUPER + G")
o.bind("SUPER + G", "GridCraft", "gridcraft")

-- Recall: one panel for every window (all workspaces), recently touched files
-- and clipboard history. Type to filter, Enter to jump.
o.bind("SUPER + SHIFT + H", "Recall", "recall")

-- Telegram (materialgram): SUPER + T (was: Toggle floating/tiling).
hl.unbind("SUPER + T")
o.bind("SUPER + T", "Telegram", { launch = "materialgram", focus = "materialgram" })

-- Discord (Vesktop, system scale): SUPER + D.
o.bind("SUPER + D", "Discord", { launch = "vesktop", focus = "vesktop" })

-- Lenovo Yoga: enable/disable screen auto-rotation with tablet mode.
o.bind(
  "switch:on:Lenovo Yoga Tablet Mode Control switch",
  "Tablet mode: auto-rotate on",
  "yoga-autorotate tablet on",
  { locked = true }
)
o.bind(
  "switch:off:Lenovo Yoga Tablet Mode Control switch",
  "Tablet mode: auto-rotate off",
  "yoga-autorotate tablet off",
  { locked = true }
)

-- Phone as an extra screen: SUPER ALT + P toggles `phone-screen`, which runs
-- wayvnc on HDMI-A-2 (LG 17") over `adb reverse` — no WiFi, USB only.
-- The high-quality path is separate: Sunshine (systemd --user service) streams
-- the same output to Moonlight over USB tethering.
o.bind("SUPER + ALT + P", "Phone screen (VNC)", "phone-screen toggle")

-- Logitech MX Master 3: the side (thumb) wheel steps through the focused
-- monitor's workspace slots, exactly like SUPER + 1..0. The outer slots do not
-- wrap: at slot 1 scrolling back does nothing, at slot 10 scrolling forward
-- does nothing.
--
-- A short flick must not switch workspaces. The wheel only starts stepping
-- after roughly 400 ms of continuous scrolling; until then the event is
-- swallowed. Once armed, each further notch (throttled to one per
-- binds:scroll_event_delay, 0.35 s in hyprland.lua) steps one slot.
--
-- Hyprland's cursor:warp_on_change_workspace would otherwise teleport the
-- pointer to the centre of the window on the target workspace. The option is
-- read synchronously inside the dispatcher, so turn the warp off for this
-- change only and restore it afterwards. Keyboard workspace switches keep it.
function o.thumb_wheel_step(delta)
  local workspace = hl.get_active_workspace()
  if not workspace or workspace.id < 1 then
    return
  end

  local slots = o.workspaces.slots or 10
  local slot = ((workspace.id - 1) % slots) + 1
  local target = slot + delta
  if target < 1 or target > slots then
    return
  end

  local warp = hl.get_config("cursor:warp_on_change_workspace") or 1
  hl.config({ cursor = { warp_on_change_workspace = 0 } })
  o.workspaces.focus(target)()
  hl.config({ cursor = { warp_on_change_workspace = warp } })
end

local HOLD_MS = 400
-- Must stay comfortably above binds:scroll_event_delay (350 ms), otherwise a
-- continuous spin looks like separate gestures between two throttled notches.
local IDLE_MS = 600

local gesture = { active = false, armed = false, held = false, direction = 0, events = 0 }
local hold_timer, idle_timer

local function end_gesture()
  gesture.active = false
  gesture.armed = false
  gesture.held = false
  gesture.direction = 0
  gesture.events = 0
  if hold_timer then hold_timer:set_enabled(false) end
  if idle_timer then idle_timer:set_enabled(false) end
  -- A fired one-shot timer cannot be re-armed, so drop them and create fresh
  -- ones for the next gesture.
  hold_timer, idle_timer = nil, nil
end

local function hold_elapsed()
  gesture.held = true
  if gesture.active and not gesture.armed and gesture.events >= 2 then
    gesture.armed = true
    o.thumb_wheel_step(gesture.direction)
  end
end

-- The bind entry point. Exposed on `o` so it can also be replayed/inspected
-- from `hyprctl eval`.
function o.thumb_wheel_event(delta)
  if gesture.active and delta ~= gesture.direction then
    end_gesture()
  end

  if not gesture.active then
    gesture.active = true
    gesture.armed = false
    gesture.held = false
    gesture.direction = delta
    gesture.events = 1
    hold_timer = hl.timer(hold_elapsed, { timeout = HOLD_MS, type = "oneshot" })
    idle_timer = hl.timer(end_gesture, { timeout = IDLE_MS, type = "oneshot" })
    return
  end

  gesture.events = gesture.events + 1
  if gesture.armed then
    o.thumb_wheel_step(gesture.direction)
  elseif gesture.held then
    gesture.armed = true
    o.thumb_wheel_step(gesture.direction)
  end

  if idle_timer then
    idle_timer:set_timeout(IDLE_MS)
  end
end

local function thumb_wheel_bind(delta)
  local run = function()
    o.thumb_wheel_event(delta)
  end
  -- Let the keybindings menu replay it as `hyprctl dispatch <expression>`.
  o.bind_expressions[run] = "o.thumb_wheel_step(" .. delta .. ")"
  return run
end

o.bind("mouse_right", "Next workspace (mouse thumb wheel)", thumb_wheel_bind(1))
o.bind("mouse_left", "Previous workspace (mouse thumb wheel)", thumb_wheel_bind(-1))
