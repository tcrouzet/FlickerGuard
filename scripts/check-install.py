import json
import os
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess
import sys
import tempfile
import time

source = Path(__file__).resolve().parent.parent / "install.sh"
fake_command = r'''
import json, os, pathlib, shutil, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["INSTALL_CHECK_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "curl":
    assert "https://github.com/yilmazonline/PWMFixer/releases/latest/download/PWMFixer.app.zip" in args
    assert args[args.index("--proto") + 1] == "=https"
    assert args[args.index("--proto-redir") + 1] == "=https"
    if os.environ["INSTALL_CHECK_CASE"] == "download failure":
        sys.exit(22)
    shutil.copyfile(os.environ["INSTALL_CHECK_ARCHIVE"], args[args.index("--output") + 1])
elif name == "mv":
    if os.environ["INSTALL_CHECK_CASE"] == "replacement failure" and args[0].endswith("/unpacked/PWMFixer.app"):
        sys.exit(1)
    os.execv("/bin/mv", ["mv", *args])
elif name == "open":
    assert args == [os.environ["INSTALL_CHECK_DESTINATION"]]
    assert pathlib.Path(args[0], "Contents/MacOS/PWMFixer").is_file()
    assert subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", os.environ["INSTALL_CHECK_PROCESS"]], capture_output=True).returncode == 1
elif name == "pgrep":
    sys.exit(2)
elif name == "tccutil":
    assert args == ["reset", "Accessibility", "com.yilmazonline.PWMFixer"]
    assert subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", os.environ["INSTALL_CHECK_PROCESS"]], capture_output=True).returncode == 1
    destination = pathlib.Path(os.environ["INSTALL_CHECK_DESTINATION"])
    assert not destination.exists() or (destination / "old-marker").is_file()
    sys.exit(1 if os.environ["INSTALL_CHECK_CASE"] == "reset failure" else 0)
'''

cases = ["first install", "running update", "download failure", "invalid archive",
         "invalid signature", "wrong identifier", "quit refused", "replacement failure", "process lookup failure", "reset failure"]
for case in cases:
    with tempfile.TemporaryDirectory(prefix="PWMFixer install check ") as folder:
        root = Path(folder)
        applications = root / "Applications"
        applications.mkdir()
        destination = applications / "PWMFixer.app"
        if case != "first install":
            destination.mkdir()
            (destination / "old-marker").write_text("previous version")
        app = root / "fixture/PWMFixer.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Resources").mkdir()
        binary = app / "Contents/MacOS/PWMFixer"
        shutil.copyfile("/usr/bin/true", binary)
        binary.chmod(0o755)
        with (app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "other.application" if case == "wrong identifier" else "com.yilmazonline.PWMFixer",
                          "CFBundleExecutable": "PWMFixer", "CFBundlePackageType": "APPL",
                          "CFBundleShortVersionString": "9.8.7"}, stream)
        resource = app / "Contents/Resources/value.txt"
        resource.write_text("original resource")
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        if case == "invalid signature":
            resource.write_text("tampered resource")
        archive = root / "release.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)
        if case == "invalid archive":
            archive.write_bytes(b"invalid zip")
        commands = root / "bin"
        commands.mkdir()
        for name in ["curl", "mv", "open", "tccutil"] + (["pgrep"] if case == "process lookup failure" else []):
            executable = commands / name
            executable.write_text(f"#!{sys.executable}\n" + fake_command)
            executable.chmod(0o755)
        process_name = "FGI" + secrets.token_hex(4)
        script = source.read_text().replace("/Applications/", f"{applications}/")
        script = script.replace('-x PWMFixer', f'-x {process_name}')
        installer = root / "install.sh"
        installer.write_text(script)
        log = root / "commands.jsonl"
        environment = {**os.environ, "PATH": f"{commands}:/usr/bin:/bin:/usr/sbin:/sbin",
                       "INSTALL_CHECK_LOG": str(log), "INSTALL_CHECK_ARCHIVE": str(archive),
                       "INSTALL_CHECK_CASE": case, "INSTALL_CHECK_DESTINATION": str(destination),
                       "INSTALL_CHECK_PROCESS": process_name}
        process = None
        try:
            if case != "first install":
                sleeper = root / process_name
                shutil.copyfile("/bin/sleep", sleeper)
                sleeper.chmod(0o755)
                subprocess.run(["codesign", "--force", "--sign", "-", str(sleeper)], check=True, capture_output=True)
                process = subprocess.Popen(["bash", "-c", 'trap "" TERM; exec "$1" 60', "--", str(sleeper)]
                                           if case == "quit refused" else [str(sleeper), "60"])
                for _ in range(100):
                    if subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", process_name], capture_output=True).returncode == 0:
                        break
                    time.sleep(0.01)
                else:
                    raise AssertionError("Test process did not start")
            result = subprocess.run(["bash", str(installer)], cwd="/", env=environment, capture_output=True, text=True, timeout=25)
            success = case in ["first install", "running update"]
            assert (result.returncode == 0) == success, (case, result.stdout, result.stderr)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            assert bool([call for call in calls if call[0] == "open"]) == success, (case, calls)
            resets = [call for call in calls if call[0] == "tccutil"]
            should_reset = case in ["first install", "running update", "replacement failure", "reset failure"]
            assert resets == ([["tccutil", "reset", "Accessibility", "com.yilmazonline.PWMFixer"]] if should_reset else []), (case, resets)
            if success:
                assert calls.index(resets[0]) < next(index for index, call in enumerate(calls) if call[0] == "mv")
            if success:
                assert "9.8.7 installed" in result.stdout
                assert not (destination / "old-marker").exists()
                subprocess.run(["codesign", "--verify", "--strict", str(destination)], check=True, capture_output=True)
            else:
                assert (destination / "old-marker").read_text() == "previous version", case
            if process is not None:
                should_quit = case in ["running update", "replacement failure", "reset failure"]
                assert (process.poll() is not None) == should_quit, case
            assert not list(applications.glob(".PWMFixer-install.*")), case
        finally:
            if process is not None:
                if process.poll() is None:
                    process.kill()
                process.wait()
print(f"Install checks: {len(cases)} scenarios passed (temporary apps and processes only; no network).")
