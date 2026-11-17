from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
version = (root / "Sources/FlickerGuard/Resources/Version.txt").read_text().strip()
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit("Invalid application version")

build = ["swift", "build", "--configuration", "release", "-debug-info-format", "none", *sys.argv[1:]]
subprocess.run(build, cwd=root, check=True)
binary_directory = Path(subprocess.check_output([*build, "--show-bin-path"], cwd=root, text=True).strip())
app = root / ".build/FlickerGuard.app"
contents = app / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
(contents / "Resources").mkdir(parents=True, exist_ok=True)
# Replace the inode so rebuilding cannot truncate a running executable.
staged_binary = contents / "MacOS/FlickerGuard.next"
shutil.copy2(binary_directory / "FlickerGuard", staged_binary)
staged_binary.replace(contents / "MacOS/FlickerGuard")
resource_bundle = "FlickerGuard_FlickerGuard.bundle"
shutil.copytree(binary_directory / resource_bundle, contents / "Resources" / resource_bundle, dirs_exist_ok=True)
shutil.copy2(root / "LICENSE", contents / "Resources/LICENSE")
info = {
    "CFBundleIdentifier": "com.tcrouzet.FlickerGuard",
    "CFBundleName": "FlickerGuard",
    "CFBundleExecutable": "FlickerGuard",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": version,
    "CFBundleDevelopmentRegion": "en",
    "CFBundleLocalizations": ["en", "fr"],
    "LSMinimumSystemVersion": "27.0",
    "LSUIElement": True,
    "NSPrincipalClass": "NSApplication",
}
with (contents / "Info.plist").open("wb") as stream:
    plistlib.dump(info, stream)
for language in info["CFBundleLocalizations"]:
    assert (contents / "Resources" / resource_bundle / "Contents/Resources" / f"{language}.lproj/Localizable.strings").is_file()
assert (contents / "Resources" / resource_bundle / "Contents/Resources/Version.txt").read_text().strip() == version
subprocess.run(["codesign", "--force", "--sign", "-", "--identifier", info["CFBundleIdentifier"], str(app)], check=True)
subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
print(app)
