# dmgbuild settings for the release disk image's Finder layout. Packaging/dmg/make-layout.sh runs
# dmgbuild with them once and keeps only the resulting .DS_Store (Packaging/dmg/DS_Store); the
# release itself (scripts/make-dmg.sh) needs nothing but hdiutil. The .DS_Store names the volume,
# the background file and the two items, so these stay fixed in make-dmg.sh too.

volume_name = "Wallflower"
format = "UDRW"
filesystem = "HFS+"

# Only the names matter here: make-layout.sh passes an empty folder for the app.
files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
# The 1x and 2x PNGs combined into one TIFF; dmgbuild copies it to /.background.tiff.
background = defines["background"]

# Window frame on screen ((x, y), (width, height)): the size of background.png, no toolbar,
# sidebar, path bar, status bar or tab bar.
window_rect = ((200, 140), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
show_icon_preview = False
show_item_info = False
label_pos = "bottom"
icon_size = 128
text_size = 13

# Icon centres, matching make-background.swift.
icon_locations = {
    "Wallflower.app": (160, 180),
    "Applications": (480, 180),
}
