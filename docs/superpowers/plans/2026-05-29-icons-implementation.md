# Winch Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace text menu-bar indicators (`●W` / `⏸W` / `⚠W`) with state-specific SF Symbols, and replace the default macOS app icon with a blue-gradient squircle bearing a 4-directional arrow.

**Architecture:** Menu bar — pure code change in `MenuBarController.swift` using `NSImage(systemSymbolName:)` + `isTemplate=true`. App icon — Swift render script produces a 1024×1024 PNG, a shell wrapper resizes to 10 sizes via `sips` and packages with `iconutil` into `Resources/AppIcon.icns` (committed). `bundle-app.sh` copies the `.icns` into the `.app` bundle; `Info.plist` references it via `CFBundleIconFile`.

**Tech Stack:** Swift (AppKit `NSImage` SF Symbol API, render script via `swift filename.swift`), macOS toolchain (`sips`, `iconutil`), Bash, Make. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-29-icons-design.md`

---

## File Structure

```
winch/
  scripts/
    render-app-icon.swift          # NEW — emits 1024×1024 AppIcon-1024.png
    build-app-icon.sh              # NEW — orchestrates render + sips + iconutil
    bundle-app.sh                  # MODIFY — copy AppIcon.icns into .app bundle
  Resources/
    AppIcon.icns                   # NEW (committed artifact)
    Info.plist                     # MODIFY — add CFBundleIconFile
  Sources/Winch/UI/
    MenuBarController.swift        # MODIFY — SF Symbols instead of text
  Makefile                         # MODIFY — add `icon` PHONY target
  docs/superpowers/qa/
    manual-checklist.md            # MODIFY — add icon visibility checks
```

No source code changes outside `MenuBarController.swift`. No new Swift module targets.

---

### Task 1: Switch MenuBarController to SF Symbols

**Files:**
- Modify: `Sources/Winch/UI/MenuBarController.swift`

- [ ] **Step 1.1: Read the current file to confirm line ranges**

```bash
cat Sources/Winch/UI/MenuBarController.swift
```

Locate the `updateAppearance()` method (around lines 32–39 in the current implementation). It currently sets `button.title` to strings like `"●W"`, `"⏸W"`, `"⚠W"`.

- [ ] **Step 1.2: Replace updateAppearance() with SF Symbol logic**

In `Sources/Winch/UI/MenuBarController.swift`, replace the existing `updateAppearance()` method:

```swift
    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        let symbolName: String
        let accessibilityLabel: String
        switch status {
        case .active:
            symbolName = "arrow.up.and.down.and.arrow.left.and.right"
            accessibilityLabel = "활성"
        case .paused:
            symbolName = "pause.fill"
            accessibilityLabel = "일시정지"
        case .permissionMissing:
            symbolName = "exclamationmark.triangle.fill"
            accessibilityLabel = "권한 필요"
        }
        let image = NSImage(systemSymbolName: symbolName,
                            accessibilityDescription: accessibilityLabel)
        image?.isTemplate = true
        button.image = image
        button.title = ""
    }
```

- [ ] **Step 1.3: Remove the now-stale initial title assignment in init()**

Find this line in `override init()` (around line 21):

```swift
        statusItem.button?.title = "W"
```

Delete it. `rebuildMenu()` + `updateAppearance()` already cover initialization, and leaving the literal `"W"` causes a one-frame flash of text before the image renders.

- [ ] **Step 1.4: Build and run unit tests**

Run: `swift build`
Expected: PASS, no warnings.

Run: `swift test`
Expected: 18/18 pass (no domain logic changed).

- [ ] **Step 1.5: Commit**

```bash
git add Sources/Winch/UI/MenuBarController.swift
git -c commit.gpgsign=false commit -m "feat(ui): use SF Symbols for menu bar status icon"
```

---

### Task 2: Render-app-icon Swift script

**Files:**
- Create: `scripts/render-app-icon.swift`

- [ ] **Step 2.1: Create the render script**

`scripts/render-app-icon.swift`:

```swift
// Renders the canonical 1024×1024 Winch app icon to a path provided
// as the first command-line argument. Blue gradient squircle background
// with a centered 4-direction-arrow SF Symbol in white.

import AppKit

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: render-app-icon.swift <output-path>\n".data(using: .utf8)!)
    exit(2)
}
let outPath = CommandLine.arguments[1]

let size: CGFloat = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()

// macOS squircle approximation: corner radius ~22.4% of side length.
let radius: CGFloat = size * 0.224
let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                          xRadius: radius, yRadius: radius)

// Vertical gradient: lighter top → deeper bottom.
let top = NSColor(red: 0.31, green: 0.62, blue: 1.0, alpha: 1.0)     // #4F9EFF
let bottom = NSColor(red: 0.10, green: 0.36, blue: 0.85, alpha: 1.0) // #1A5CD9
let gradient = NSGradient(starting: top, ending: bottom)!
bgPath.addClip()
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

// SF Symbol foreground at ~60% canvas size, white.
let symbolPt = size * 0.60
let baseConfig = NSImage.SymbolConfiguration(pointSize: symbolPt, weight: .medium)
let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
let config = baseConfig.applying(colorConfig)

guard let symbol = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
                           accessibilityDescription: nil)?
                           .withSymbolConfiguration(config) else {
    FileHandle.standardError.write("symbol not found\n".data(using: .utf8)!)
    exit(1)
}
let s = symbol.size
symbol.draw(at: NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2),
            from: .zero, operation: .sourceOver, fraction: 1.0)

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let pngData = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("PNG encode failed\n".data(using: .utf8)!)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
```

- [ ] **Step 2.2: Smoke-test the render script in isolation**

```bash
mkdir -p .build
swift scripts/render-app-icon.swift .build/test-icon-1024.png
ls -la .build/test-icon-1024.png
```

Expected: outputs `Wrote .build/test-icon-1024.png`, file is ~150–300 KB PNG.

Optional visual check: `open .build/test-icon-1024.png`

- [ ] **Step 2.3: Commit (script only — no .icns yet)**

```bash
git add scripts/render-app-icon.swift
git -c commit.gpgsign=false commit -m "build: add Swift script to render 1024 app icon"
```

---

### Task 3: build-app-icon.sh and Makefile `icon` target

**Files:**
- Create: `scripts/build-app-icon.sh`
- Modify: `Makefile`

- [ ] **Step 3.1: Create the orchestration script**

`scripts/build-app-icon.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR=".build"
ICONSET="${BUILD_DIR}/AppIcon.iconset"
SOURCE_PNG="${BUILD_DIR}/AppIcon-1024.png"
OUTPUT="Resources/AppIcon.icns"

echo "Rendering source 1024 PNG..."
mkdir -p "$BUILD_DIR"
swift scripts/render-app-icon.swift "$SOURCE_PNG"

echo "Building iconset..."
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Apple's required filenames for iconutil:
sips -z 16   16   "$SOURCE_PNG" --out "$ICONSET/icon_16x16.png"        >/dev/null
sips -z 32   32   "$SOURCE_PNG" --out "$ICONSET/icon_16x16@2x.png"     >/dev/null
sips -z 32   32   "$SOURCE_PNG" --out "$ICONSET/icon_32x32.png"        >/dev/null
sips -z 64   64   "$SOURCE_PNG" --out "$ICONSET/icon_32x32@2x.png"     >/dev/null
sips -z 128  128  "$SOURCE_PNG" --out "$ICONSET/icon_128x128.png"      >/dev/null
sips -z 256  256  "$SOURCE_PNG" --out "$ICONSET/icon_128x128@2x.png"   >/dev/null
sips -z 256  256  "$SOURCE_PNG" --out "$ICONSET/icon_256x256.png"      >/dev/null
sips -z 512  512  "$SOURCE_PNG" --out "$ICONSET/icon_256x256@2x.png"   >/dev/null
sips -z 512  512  "$SOURCE_PNG" --out "$ICONSET/icon_512x512.png"      >/dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "$ICONSET/icon_512x512@2x.png"   >/dev/null

echo "Packaging .icns..."
mkdir -p Resources
iconutil --convert icns "$ICONSET" --output "$OUTPUT"

echo "Done: $OUTPUT"
```

Make executable:

```bash
chmod +x scripts/build-app-icon.sh
```

- [ ] **Step 3.2: Add `icon` target to Makefile**

Read the current Makefile (`cat Makefile`) and update `.PHONY` plus add an `icon` recipe.

Replace the `.PHONY` line:

```makefile
.PHONY: build test app dmg clean run
```

with:

```makefile
.PHONY: build test app dmg icon clean run
```

Then add the new recipe immediately after the `dmg` target (and before `run`):

```makefile
icon:
	./scripts/build-app-icon.sh
```

So the relevant section reads:

```makefile
dmg: app
	./scripts/make-dmg.sh

icon:
	./scripts/build-app-icon.sh

run: build
	swift run winch
```

`icon` deliberately has **no** prerequisites — it does not depend on `app`/`dmg` because the `.icns` is committed and downstream targets read it from `Resources/`.

- [ ] **Step 3.3: Generate the .icns**

```bash
make icon
```

Expected output ends with `Done: Resources/AppIcon.icns`. Verify:

```bash
ls -la Resources/AppIcon.icns
file Resources/AppIcon.icns
```

Expected: file exists, `file` output reports `Mac OS X icon`.

- [ ] **Step 3.4: Sanity-check the icon visually**

```bash
open Resources/AppIcon.icns
```

Expected: Preview opens, shows the blue squircle with white arrow at multiple sizes (Preview.app reads .icns multi-resolution).

Close Preview when done.

- [ ] **Step 3.5: Commit script, Makefile, and the generated .icns**

```bash
git add scripts/build-app-icon.sh Makefile Resources/AppIcon.icns
git -c commit.gpgsign=false commit -m "build: add app icon pipeline (make icon) and committed AppIcon.icns"
```

---

### Task 4: Wire icon into Info.plist and bundle script

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `scripts/bundle-app.sh`

- [ ] **Step 4.1: Add CFBundleIconFile to Info.plist**

Open `Resources/Info.plist`. Inside the top-level `<dict>`, add the following two lines immediately after the `</string>` that closes `CFBundleExecutable` (i.e., between `<key>CFBundleExecutable</key><string>winch</string>` and `<key>CFBundleShortVersionString</key>`):

```xml
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
```

After the edit, the relevant block should read (showing context):

```xml
    <key>CFBundleExecutable</key>
    <string>winch</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.1</string>
```

The value is `AppIcon` without `.icns` — macOS appends the extension automatically when looking up `CFBundleIconFile`.

- [ ] **Step 4.2: Verify the plist is still valid**

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleIconFile" Resources/Info.plist
```

Expected: `AppIcon`

- [ ] **Step 4.3: Update bundle-app.sh to copy the .icns**

Open `scripts/bundle-app.sh`. Find this block:

```bash
cp "${BUILD_DIR}/winch" "$APP_DIR/Contents/MacOS/winch"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
```

Add a third line immediately after, copying the icon:

```bash
cp "${BUILD_DIR}/winch" "$APP_DIR/Contents/MacOS/winch"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
```

The `Contents/Resources/` directory is already created earlier in the script (`mkdir -p "$APP_DIR/Contents/Resources"`).

- [ ] **Step 4.4: Build a fresh .app and verify the icon is inside**

```bash
make app
ls -la .build/release/Winch.app/Contents/Resources/
```

Expected: `AppIcon.icns` is present in the bundle's Resources directory.

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleIconFile" .build/release/Winch.app/Contents/Info.plist
```

Expected: `AppIcon`

- [ ] **Step 4.5: Visual verification in Finder**

```bash
open -R .build/release/Winch.app
```

In the Finder window that opens, the `Winch.app` icon should display as the blue squircle with the white arrow (Finder may take 1–2 seconds to refresh icon caches; if it shows the default Swift executable icon, run `killall Finder` to force a refresh).

- [ ] **Step 4.6: Commit**

```bash
git add Resources/Info.plist scripts/bundle-app.sh
git -c commit.gpgsign=false commit -m "build: reference AppIcon.icns from Info.plist and bundle script"
```

---

### Task 5: Update QA checklist with icon checks

**Files:**
- Modify: `docs/superpowers/qa/manual-checklist.md`

- [ ] **Step 5.1: Append an "아이콘 표시" section**

Open `docs/superpowers/qa/manual-checklist.md`. After the existing `## Exit` section, add a new section:

```markdown
## 아이콘 표시
- [ ] 메뉴바: 권한 부여 전 ⚠️ 삼각형 (`exclamationmark.triangle.fill`)
- [ ] 메뉴바: 권한 부여 후 4방향 화살표 (`arrow.up.and.down.and.arrow.left.and.right`)
- [ ] 메뉴바: Pause 클릭 시 일시정지 심볼 (`pause.fill`)
- [ ] 메뉴바: Resume 클릭 시 다시 4방향 화살표
- [ ] Finder Applications: 블루 그라데이션 + 흰 화살표 앱 아이콘 (텍스트 "exec" 아이콘 아님)
- [ ] About Winch 패널: 동일 앱 아이콘 표시
- [ ] 시스템 설정 → 개인정보 보호 → 손쉬운 사용 목록: Winch 항목 옆 동일 아이콘
```

- [ ] **Step 5.2: Commit**

```bash
git add docs/superpowers/qa/manual-checklist.md
git -c commit.gpgsign=false commit -m "docs: add icon visibility checks to manual QA"
```

---

### Task 6: End-to-end smoke verification

This is verification, not implementation. No commit at the end.

- [ ] **Step 6.1: Build the .app and the .dmg**

```bash
make dmg
```

Expected: `.build/release/Winch.app` is rebuilt, `.build/release/Winch-0.1.1.dmg` is created without errors.

- [ ] **Step 6.2: Confirm icon assets are present inside the bundle**

```bash
ls .build/release/Winch.app/Contents/Resources/
```

Expected: `AppIcon.icns` listed.

```bash
file .build/release/Winch.app/Contents/Resources/AppIcon.icns
```

Expected: `Mac OS X icon`.

- [ ] **Step 6.3: Confirm the menu bar SF Symbol logic compiles and runs cleanly**

```bash
swift test
```

Expected: 18/18 pass. (Visual menu bar verification is manual and covered by the QA checklist; do not launch the running app from inside the implementer subagent — leave that for the user's manual test.)

- [ ] **Step 6.4: Final git status check**

```bash
git status --short
```

Expected: clean (no uncommitted changes).

```bash
git log --oneline | head -6
```

Expected: 5 new commits on top of the spec commit (`2a08cc5`), in order:
- "docs: add icon visibility checks to manual QA"
- "build: reference AppIcon.icns from Info.plist and bundle script"
- "build: add app icon pipeline (make icon) and committed AppIcon.icns"
- "build: add Swift script to render 1024 app icon"
- "feat(ui): use SF Symbols for menu bar status icon"

---

## Out of scope (per spec)

- Dark-mode-specific app icon variant
- Animated / dynamic menu bar icon (pulse, etc.)
- Localized menu bar icon variants
- Notification badge overlays
- Asset Catalog (`.xcassets`) — we use direct `.icns` because SPM has limited xcassets support and this project has no Xcode project
