# Winch CI & Automated Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up GitHub Actions so `swift build` + `swift test` run automatically on every push/PR to `main`, and pushing a `v*` tag automatically builds the DMG and publishes a GitHub Release with auto-generated notes.

**Architecture:** Two separate workflow files under `.github/workflows/`. `ci.yml` runs build+test on push/PR with concurrency cancellation. `release.yml` triggers on `v*` tag push, validates that the tag version matches `Resources/Info.plist`'s `CFBundleShortVersionString`, runs tests, builds the DMG via the existing `make app` + `make dmg` targets, and publishes the release with `gh release create --generate-notes`.

**Tech Stack:** GitHub Actions, `macos-latest` runner (Apple Silicon), `swift build`/`swift test`, `gh` CLI (preinstalled on the runner), existing `Makefile`/`scripts/` from the repo. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-29-ci-release-design.md`

---

## File Structure

```
winch/
  .github/
    workflows/
      ci.yml              # push/PR → swift build + swift test
      release.yml         # v* tag → version check + test + DMG + gh release create
  README.md               # add a Release / CI badges section (small update)
```

No source code changes. No new scripts. The existing `scripts/bundle-app.sh` and `scripts/make-dmg.sh` are invoked via the existing `Makefile` targets `app` and `dmg`.

---

### Task 1: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1.1: Create CI workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  test:
    name: Build & Test
    runs-on: macos-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Swift build
        run: swift build

      - name: Swift test
        run: swift test
```

- [ ] **Step 1.2: Verify workflow YAML is syntactically valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo OK`
Expected: `OK` (no traceback).

(Pure-Python YAML check — we can't actually run the workflow locally. Real validation happens on the first push to GitHub.)

- [ ] **Step 1.3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add build+test workflow for push and PRs"
```

- [ ] **Step 1.4: Push and observe first CI run**

```bash
git push origin main
```

Wait for the workflow to complete on GitHub. Then run:

```bash
gh run list --workflow=ci.yml --limit 1
```

Expected: status `completed`, conclusion `success`. If `failure`, run `gh run view --log-failed` and fix before proceeding.

- [ ] **Step 1.5: Verify CI cancels stale runs on rapid follow-up pushes (optional smoke test)**

This is observable behavior, not strictly required to verify, but is the main reason we added the `concurrency` block. Skip if you don't want to spend the runner time:

1. Touch a comment-only change: `printf "\n" >> README.md && git add README.md && git -c commit.gpgsign=false commit -m "test: ci concurrency smoke (rollback next)"`
2. Push twice in quick succession (within ~20s):
   ```bash
   git push origin main && git push origin main --force-with-lease
   ```
3. Run `gh run list --workflow=ci.yml --limit 3` — the older run should show conclusion `cancelled`.
4. Roll back: `git reset --hard HEAD~1 && git push --force-with-lease origin main`

If you skip this step, just delete it from the checklist. No commit needed if skipped.

---

### Task 2: Release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 2.1: Create release workflow**

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

jobs:
  release:
    name: Build DMG & publish release
    runs-on: macos-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Verify tag matches Info.plist version
        run: |
          TAG_VERSION="${GITHUB_REF_NAME#v}"
          PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
          echo "Tag version:   $TAG_VERSION"
          echo "Plist version: $PLIST_VERSION"
          if [[ "$TAG_VERSION" != "$PLIST_VERSION" ]]; then
            echo "::error::Tag version ($TAG_VERSION) does not match Info.plist ($PLIST_VERSION)"
            exit 1
          fi
          echo "VERSION=$PLIST_VERSION" >> "$GITHUB_ENV"

      - name: Swift test
        run: swift test

      - name: Build app bundle
        run: make app

      - name: Build DMG
        run: make dmg

      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            ".build/release/Winch-${VERSION}.dmg" \
            --title "Winch ${VERSION}" \
            --generate-notes
```

- [ ] **Step 2.2: Verify workflow YAML is syntactically valid**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 2.3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow triggered on v* tags"
```

- [ ] **Step 2.4: Push the workflow to GitHub**

```bash
git push origin main
```

Wait for the CI workflow to pass on this commit before proceeding (so we're certain the repo is green before we exercise the release path).

```bash
gh run list --workflow=ci.yml --limit 1
```

Expected: conclusion `success`.

---

### Task 3: Smoke-test the release workflow with v0.1.1

We don't want to test the release workflow by tagging the existing `v0.1.0` (already published) or by going straight to `v0.2.0` without seeing it run. Cut a no-op `v0.1.1` patch release that bumps only the plist version. This validates the entire automation end-to-end.

**Files:**
- Modify: `Resources/Info.plist` (CFBundleShortVersionString: `0.1.0` → `0.1.1`)

- [ ] **Step 3.1: Bump version in Info.plist**

Edit `Resources/Info.plist`. Find the line under `<key>CFBundleShortVersionString</key>` and change `<string>0.1.0</string>` to `<string>0.1.1</string>`.

Verify:

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist
```

Expected output: `0.1.1`

- [ ] **Step 3.2: Verify DMG builds locally with the new version**

Run: `make dmg`
Expected: `Done: .build/release/Winch-0.1.1.dmg` printed in the final output.

```bash
ls .build/release/Winch-0.1.1.dmg
```

Expected: file exists.

- [ ] **Step 3.3: Commit version bump**

```bash
git add Resources/Info.plist
git commit -m "chore: bump version to 0.1.1"
git push origin main
```

Wait for the CI workflow to pass:

```bash
gh run list --workflow=ci.yml --limit 1
```

Expected: conclusion `success`.

- [ ] **Step 3.4: Tag and push**

```bash
git tag v0.1.1
git push origin v0.1.1
```

- [ ] **Step 3.5: Observe release workflow run**

```bash
gh run list --workflow=release.yml --limit 1
```

Repeat until the run finishes (it takes ~4-6 minutes). Final status should be `completed`, conclusion `success`.

If the run fails, capture the failing step's log:

```bash
gh run view --log-failed
```

Common failure modes and fixes:
- "Tag version does not match Info.plist" → you tagged before committing the plist bump, or used a different tag. Delete the tag (`git tag -d v0.1.1 && git push --delete origin v0.1.1`), fix, re-tag.
- `gh: command not found` → won't happen on `macos-latest`; gh is preinstalled. If it does, add an explicit install step.
- `swift test` failing → fix the test on `main` first, then re-tag.

- [ ] **Step 3.6: Verify the release on GitHub**

```bash
gh release view v0.1.1
```

Expected output includes:
- `title: Winch 0.1.1`
- `tag: v0.1.1`
- `asset: Winch-0.1.1.dmg`
- Auto-generated notes section listing the commits between `v0.1.0` and `v0.1.1` (at minimum the version bump commit and the two workflow commits).

Open in browser: `gh release view v0.1.1 --web`

Confirm visually:
- DMG asset is listed under "Assets"
- Notes are auto-generated and reasonable
- "Set as the latest release" badge shows on the release page

- [ ] **Step 3.7: Download and verify the published DMG**

```bash
mkdir -p "$CLAUDE_JOB_DIR/release-test" && cd "$CLAUDE_JOB_DIR/release-test"
gh release download v0.1.1 --repo primary924/winch
ls -la Winch-0.1.1.dmg
MOUNT=$(hdiutil attach -nobrowse -readonly Winch-0.1.1.dmg | tail -1 | awk '{print $NF}')
ls -la "$MOUNT"
hdiutil detach "$MOUNT" >/dev/null
```

(Replace `$CLAUDE_JOB_DIR` with `/tmp` if running outside a Claude session.)

Expected: DMG downloads, mounts cleanly, contains `Winch.app` and `Applications` symlink. Confirms the published artifact matches what `make dmg` produces locally.

---

### Task 4: Update README with CI badge and release flow

**Files:**
- Modify: `README.md` (add CI badge near the top; replace the manual `gh release create` workflow in "소스에서 빌드 (개발자)" with the new tag-push flow)

- [ ] **Step 4.1: Add CI badge near the top of README**

Open `README.md`. Insert the following line immediately after the `# Winch` heading, with a blank line separating it from the heading and from the description paragraph:

```markdown
[![CI](https://github.com/primary924/winch/actions/workflows/ci.yml/badge.svg)](https://github.com/primary924/winch/actions/workflows/ci.yml)
```

The top of the file should now read:

```markdown
# Winch

[![CI](https://github.com/primary924/winch/actions/workflows/ci.yml/badge.svg)](https://github.com/primary924/winch/actions/workflows/ci.yml)

macOS에서 윈도우 창의 타이틀바를 일일이 잡지 않고도 창을 옮길 수 있게 해주는 메뉴바 유틸리티입니다. ...
```

- [ ] **Step 4.2: Replace the developer release flow section**

Find the "소스에서 빌드 (개발자)" section in `README.md`. After the existing `make app` / `make dmg` / `make test` block, add a new "릴리즈 발행" subsection:

```markdown
### 릴리즈 발행

`v*` 태그를 push하면 GitHub Actions가 자동으로 DMG를 빌드해 GitHub Release를 발행합니다.

```bash
# 1. Resources/Info.plist의 CFBundleShortVersionString을 새 버전으로 수정 (예: 0.2.0)
# 2. 변경사항 커밋
git commit -am "chore: bump version to 0.2.0"
# 3. 태그 생성 및 push
git tag v0.2.0
git push && git push --tags
```

태그 버전(`0.2.0`)과 Info.plist의 버전이 일치해야 합니다. 불일치 시 워크플로가 실패합니다.

릴리즈 노트는 이전 태그 이후의 커밋 메시지에서 자동 생성됩니다.
```

- [ ] **Step 4.3: Commit and push**

```bash
git add README.md
git commit -m "docs: add CI badge and release workflow instructions"
git push origin main
```

Wait for CI to pass:

```bash
gh run list --workflow=ci.yml --limit 1
```

Expected: conclusion `success`.

- [ ] **Step 4.4: Verify the badge renders**

Open: `gh repo view --web`

Expected: README displays a green "CI passing" badge at the top, just under the title.

---

## Out of scope (per spec)

These are intentionally **not** in this plan:
- SwiftLint / SwiftFormat linting
- `.build/` caching between runs
- Multi-version Swift matrix testing
- Code coverage reporting
- Code signing / notarization automation
- Branch protection rules (configured via GitHub UI, not workflow files)
- SHA-256 checksum publishing on releases
