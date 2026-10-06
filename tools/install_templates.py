"""Install only the Windows x86_64 export templates from the official .tpz
into %APPDATA%/Godot/export_templates/<version>/ (saves ~1 GB of disk)."""
import os
import sys
import zipfile

tpz = sys.argv[1]
appdata = os.environ["APPDATA"]
with zipfile.ZipFile(tpz) as z:
    version = z.read("templates/version.txt").decode().strip()
    dst = os.path.join(appdata, "Godot", "export_templates", version)
    os.makedirs(dst, exist_ok=True)
    wanted = ["version.txt", "windows_release_x86_64.exe", "windows_debug_x86_64.exe",
              "windows_release_x86_64_console.exe", "windows_debug_x86_64_console.exe"]
    for name in wanted:
        src = "templates/" + name
        if src in z.namelist():
            with z.open(src) as fi, open(os.path.join(dst, name), "wb") as fo:
                fo.write(fi.read())
            print("installed", name)
print("->", dst)
