#!/bin/bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export GIT_TERMINAL_PROMPT=0

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
[[ "$REPO" == "tcrouzet/FlickerGuard" ]] || { printf 'Dépôt attendu : tcrouzet/FlickerGuard\n' >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { printf 'Lance release.sh depuis main.\n' >&2; exit 1; }
git fetch origin --tags

VERSION_FILE=Sources/FlickerGuard/Resources/Version.txt
CURRENT=$(python3 -c 'import pathlib, re; v = pathlib.Path("Sources/FlickerGuard/Resources/Version.txt").read_text().strip(); assert re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", v), "Version attendue : majeur.mineur.patch"; print(v)')
TAG="$CURRENT"
if git show-ref --verify --quiet "refs/tags/$CURRENT"; then
    PATCH_VERSION=${CURRENT##*.}
    TAG="${CURRENT%.*}.$((10#$PATCH_VERSION + 1))"
fi

export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
TEST_FLAGS=(--disable-sandbox --cache-path .build/cache --config-path .build/configuration --security-path .build/security)
TEST_PLUGIN="$(xcrun --find swiftc)"
TEST_PLUGIN="$(dirname -- "$TEST_PLUGIN")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TEST_PLUGIN" ]]; then
    TEST_FLAGS+=(-Xswiftc -load-plugin-library -Xswiftc "$TEST_PLUGIN")
fi
swift test "${TEST_FLAGS[@]}"
python3 scripts/check-release.py

printf '%s\n' "$TAG" > "$VERSION_FILE"
git add -- .gitignore .github Package.swift README.md Sources Tests scripts release.sh LICENSE
if ! git diff --cached --quiet; then
    git commit -m "Release $TAG"
fi
[[ -z "$(git status --porcelain)" ]] || { printf 'Arbre git non propre.\n' >&2; exit 1; }
git push -u origin main
git tag "$TAG"
git push origin "$TAG"
printf 'Release %s confiée à GitHub Actions : https://github.com/%s/actions\n' "$TAG" "$REPO"
