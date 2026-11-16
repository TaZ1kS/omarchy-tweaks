-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Small monitors on the sides, big one in the center
-- HDMI-A-2 (small, left): 0x0
-- DP-2 (big, center): 1280x0
-- HDMI-A-1 (small, right): 2960x0 (1280+1680)
hl.monitor({ output = "HDMI-A-1", mode = "1280x1024@60.02", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-2", mode = "1680x1050@59.88", position = "1280x0", scale = 1 })
hl.monitor({ output = "HDMI-A-2", mode = "1280x1024@60.02", position = "2960x0", scale = 1 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- Headless output for phone screen: fixed name HEADLESS-1, 1200x540,
-- positioned centered below the central monitor (DP-2 at 1280x0, 1680x1050).
-- phone-screen keeps this in sync dynamically; this is the login-time default.
hl.monitor({ output = "HEADLESS-1", mode = "1200x540@60", position = "1520x1050", scale = 1.25, transform = 0 })
