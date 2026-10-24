# Settings for dmgbuild: the drag-to-Applications window of Nightforge's DMG. Run from the repo root:
#   dmgbuild -s scripts/dmg-settings.py -D app=build/Nightforge.app Nightforge Nightforge.dmg
# The background (Resources/dmg/background.png and @2x) is drawn by scripts/render-brand.swift;
# the icon positions here match the arrow and name tags painted on it.

import os.path

app = defines.get("app", "build/Nightforge.app")  # noqa: F821 (provided by dmgbuild)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")

background = "Resources/dmg/background.png"  # dmgbuild picks up background@2x.png next to it
window_rect = ((200, 120), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (170, 190),
    "Applications": (490, 190),
}
