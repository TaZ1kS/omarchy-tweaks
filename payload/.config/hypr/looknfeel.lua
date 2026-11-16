-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- Slightly tighter spacing than Omarchy's defaults (gaps_in = 5, gaps_out = 10).
hl.config({
  general = {
    gaps_in = 3,
    gaps_out = 6,
  },
})

-- Frosted-glass blur behind translucent surfaces (used by the top bar).
-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- Rounding is shared with the Omarchy shell: Style.cornerRadius mirrors this
-- value, so panels, popups and the bar get the same rounded corners.
hl.config({
  decoration = {
    rounding = 4,
    blur = {
      enabled = true,
      size = 8,
      passes = 3,
      new_optimizations = true,
      ignore_opacity = true,
      noise = 0.02,
      popups = true,
    },
  },
})

-- Bibata Material Sunset cursor theme.
hl.env("XCURSOR_THEME", "Bibata-Material-Sunset")
hl.env("XCURSOR_SIZE", "20")
hl.env("HYPRCURSOR_THEME", "Bibata-Material-Sunset")
hl.env("HYPRCURSOR_SIZE", "20")

-- Blur whatever is behind the Omarchy bar.
hl.layer_rule({
  name = "omarchy-bar-blur",
  match = { namespace = "omarchy-bar" },
  blur = true,
  blur_popups = true,
})

-- Bar widget panels (audio, network, power, bluetooth, clock, weather, ...)
-- are full-screen overlay layer surfaces with the visible card drawn inside.
-- Blur the card and skip the transparent rest so only the panel frosts.
hl.layer_rule({
  name = "omarchy-panel-blur",
  match = { namespace = "omarchy-keyboard-panel" },
  blur = true,
  ignore_alpha = 0.2,
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Opt another application in to Omarchy's standard transparency.
-- Find its class with: hyprctl clients
-- o.transparent_window("my-app")
-- o.transparent_window("my-app", "0.9 0.85") -- Custom active/inactive opacity.

-- Frost only visible popup cards; transparent fullscreen dismiss areas are excluded.
hl.layer_rule({
  name = "omarchy-popup-cards-blur",
  match = { namespace = "omarchy-(menu|clipboard|emojis|reminders|polkit|notifications|osd|network-qr|dock-apps)" },
  blur = true,
  blur_popups = true,
  ignore_alpha = 0.2,
})
