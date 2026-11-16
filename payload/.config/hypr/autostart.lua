-- Extra autostart processes.
-- o.launch_on_start("my-service")
o.exec_on_start("hyprctl setcursor Bibata-Material-Sunset 20")

-- Lenovo Yoga: rotate the screen automatically in tablet mode.
o.exec_on_start("yoga-autorotate daemon")

-- Create headless output for phone screen (ensures it exists on login)
o.exec_on_start("~/.local/bin/setup-headless.sh")