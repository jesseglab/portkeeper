"""Finder layout; actual draggable app and Applications shortcut, not painted buttons."""
from pathlib import Path

root = Path(defines["root"]).resolve()
application = str(Path(defines["app"]).resolve())
appname = Path(application).name
files = [application]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
compression_level = 9
background = str(root / "Assets/Installer/background.tiff")
window_rect = ((200, 160), (720, 512))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
icon_size = 104
text_size = 14
label_pos = "bottom"
# Keep artwork outside the viewport even when Finder is set to show hidden files.
icon_locations = {appname: (204, 258), "Applications": (516, 258), ".background.tiff": (1100, 900)}
hide = [".background.tiff"]
