import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap

source = Path(__file__).resolve().parent.parent / "release.sh"
workflow = source.parent / ".github/workflows/release.yml"
publish_script = textwrap.dedent(workflow.read_text().split("      - name: Publish app\n", 1)[1].split("        run: |\n", 1)[1])
fake_command = r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["RELEASE_CHECK_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "python3":
    if args == ["scripts/check-release.py"]:
        sys.exit(0)
    os.execv(sys.executable, [sys.executable, *args])
if name == "gh":
    if args[:2] == ["repo", "view"]:
        print(os.environ.get("RELEASE_CHECK_REPO", "tcrouzet/FlickerGuard"))
    elif args[:2] == ["release", "create"]:
        assert pathlib.Path(args[3]).is_file(), "App archive missing"
        sys.exit(int(os.environ.get("RELEASE_CHECK_PUBLISH_EXIT", "0")))
    else:
        sys.exit("Unexpected GitHub command")
elif name == "xcrun":
    print("/nonexistent/bin/swiftc")
elif name == "swift":
    sys.exit(int(os.environ.get("RELEASE_CHECK_TEST_EXIT", "0")))
elif name == "git":
    if args == ["branch", "--show-current"]:
        print(os.environ.get("RELEASE_CHECK_BRANCH", "main"))
    elif args[:1] == ["fetch"]:
        sys.exit(int(os.environ.get("RELEASE_CHECK_FETCH_EXIT", "0")))
    elif args[:1] == ["show-ref"]:
        sys.exit(0 if args[-1] == os.environ.get("RELEASE_CHECK_TAG") else 1)
    elif args[:1] == ["diff"]:
        sys.exit(1)
    elif args == ["push", "-u", "origin", "main"]:
        sys.exit(int(os.environ.get("RELEASE_CHECK_PUSH_EXIT", "0")))
    elif args[:2] == ["push", "origin"]:
        sys.exit(int(os.environ.get("RELEASE_CHECK_TAG_PUSH_EXIT", "0")))
'''

cases = [
    ({}, True, "0.3.4"),
    ({"RELEASE_CHECK_TAG": "refs/tags/0.3.4"}, True, "0.3.5"),
    ({"RELEASE_CHECK_BRANCH": "feature"}, False, "0.3.4"),
    ({"RELEASE_CHECK_REPO": "elsewhere/project"}, False, "0.3.4"),
    ({"RELEASE_CHECK_TEST_EXIT": "1"}, False, "0.3.4"),
    ({"RELEASE_CHECK_PUSH_EXIT": "1"}, False, "0.3.4"),
    ({"RELEASE_CHECK_TAG_PUSH_EXIT": "1"}, False, "0.3.4"),
    ({"RELEASE_CHECK_FETCH_EXIT": "1"}, False, "0.3.4"),
    ({"RELEASE_CHECK_VERSION": "invalid"}, False, "invalid"),
]
for settings, success, version in cases:
    with tempfile.TemporaryDirectory(prefix="FlickerGuard release check ") as folder:
        root = Path(folder)
        shutil.copy2(source, root / "release.sh")
        version_file = root / "Sources/FlickerGuard/Resources/Version.txt"
        version_file.parent.mkdir(parents=True)
        version_file.write_text(settings.get("RELEASE_CHECK_VERSION", "0.3.4") + "\n")
        commands = root / "bin"
        commands.mkdir()
        for name in ["gh", "git", "swift", "xcrun", "python3"]:
            executable = commands / name
            executable.write_text(f"#!{sys.executable}\n" + fake_command)
            executable.chmod(0o755)
        log = root / "commands.jsonl"
        environment = {**os.environ, "PATH": f"{commands}:/usr/bin:/bin", "RELEASE_CHECK_LOG": str(log), **settings}
        result = subprocess.run(["bash", str(root / "release.sh")], cwd="/", env=environment, capture_output=True, text=True)
        assert (result.returncode == 0) == success, (settings, result.stdout, result.stderr)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        writes = [call for call in calls if call[:2] in [["git", "commit"], ["git", "push"], ["git", "tag"]]]
        assert [call for call in calls if call[0] == "gh"] == [["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]]
        if success:
            assert writes == [["git", "commit", "-m", f"Release {version}"], ["git", "push", "-u", "origin", "main"], ["git", "tag", version], ["git", "push", "origin", version]], writes
            assert "handed to GitHub Actions" in result.stdout
            assert "Download after the workflow succeeds" in result.stdout
            assert f"/releases/download/{version}/FlickerGuard.app.zip" in result.stdout
        else:
            assert "handed to GitHub Actions" not in result.stdout
            if "RELEASE_CHECK_PUSH_EXIT" in settings:
                assert writes[-1] == ["git", "push", "-u", "origin", "main"], writes
                assert not any(call[:2] == ["git", "tag"] for call in calls), writes
            elif "RELEASE_CHECK_TAG_PUSH_EXIT" in settings:
                assert writes[-1] == ["git", "push", "origin", version], writes
            else:
                assert writes == [], writes
        assert version_file.read_text().strip() == version

publish_cases = [({}, True), ({"RELEASE_CHECK_PUBLISH_EXIT": "1"}, False), ({"RELEASE_CHECK_MISSING_APP": "1"}, False)]
for settings, success in publish_cases:
    with tempfile.TemporaryDirectory(prefix="FlickerGuard publish check ") as folder:
        root = Path(folder)
        (root / ".build").mkdir()
        if "RELEASE_CHECK_MISSING_APP" not in settings:
            (root / ".build/FlickerGuard.app.zip").write_bytes(b"test archive")
        commands = root / "bin"
        commands.mkdir()
        executable = commands / "gh"
        executable.write_text(f"#!{sys.executable}\n" + fake_command)
        executable.chmod(0o755)
        log = root / "commands.jsonl"
        environment = {**os.environ, "PATH": f"{commands}:/usr/bin:/bin", "RELEASE_CHECK_LOG": str(log), "RELEASE_TAG": "0.3.4", **settings}
        result = subprocess.run(["bash", "-c", publish_script], cwd=root, env=environment, capture_output=True, text=True)
        assert (result.returncode == 0) == success, (settings, result.stdout, result.stderr)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        assert calls == [["gh", "release", "create", "0.3.4", ".build/FlickerGuard.app.zip", "--verify-tag", "--latest", "--title", "FlickerGuard 0.3.4", "--notes-file", ".build/release-notes.md"]], calls
        notes = (root / ".build/release-notes.md").read_text()
        assert notes.startswith("[Download FlickerGuard.app.zip](https://github.com/tcrouzet/FlickerGuard/releases/download/0.3.4/FlickerGuard.app.zip)")
print(f"Release checks: {len(cases) + len(publish_cases)} scenarios passed (no network or repository writes).")
