# Winch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar utility that moves the focused window when a user-configurable modifier key combination is held and the cursor moves.

**Architecture:** Swift Package Manager project producing a `WinchDomain` library (pure state machine + config) and a `winch` executable. The executable wires Platform adapters (`CGEventTap`, `AXUIElement`, Accessibility permission, `SMAppService` login item, `NSStatusItem`) to Domain logic. Domain is fully unit-tested with fake adapters; Platform is kept thin and verified by manual QA.

**Tech Stack:** Swift 5.9+, AppKit (`NSStatusItem`, `NSWorkspace`), SwiftUI (preferences window), `CGEventTap`, Accessibility API (`AXUIElement`), `SMAppService` (login item). macOS 13 Ventura minimum. XCTest. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-05-28-winch-design.md`

---

## File Structure

```
winch/
  Package.swift                                    # SPM manifest (library + executable + tests)
  Makefile                                         # build → .app bundle
  .gitignore                                       # excludes .build, *.app, .DS_Store
  Sources/
    WinchDomain/                                   # PURE — unit-tested
      HotkeyConfig.swift                           # modifier flag struct + exact matching
      DragController.swift                         # Idle/Tracking state machine
      Protocols.swift                              # WindowControlling, CursorLocating, WindowHandle
    Winch/                                         # APP — thin adapters + wiring
      main.swift                                   # entry point
      AppDelegate.swift                            # bootstrap, dependency wiring
      Platform/
        WindowController.swift                     # AXUIElement adapter
        SystemCursorLocator.swift                  # NSEvent.mouseLocation adapter
        PermissionManager.swift                    # AXIsProcessTrusted + recovery polling
        EventTap.swift                             # CGEventTap setup, callback bridge
        SettingsStore.swift                        # UserDefaults wrapper
        LoginItemManager.swift                     # SMAppService wrapper
      UI/
        MenuBarController.swift                    # NSStatusItem + menu
        PreferencesWindowController.swift          # SwiftUI hosting
        PreferencesView.swift                      # modifier toggles + login item toggle
  Tests/
    WinchDomainTests/
      HotkeyConfigTests.swift                      # exact match, superset, toggle keys
      DragControllerTests.swift                    # state transitions, position math
      Fakes.swift                                  # FakeWindowController, FakeCursorLocator
  Resources/
    Info.plist                                     # LSUIElement, bundle metadata
    Assets.xcassets/                               # placeholder for icons
  scripts/
    bundle-app.sh                                  # assemble Winch.app from swift build output
  docs/
    superpowers/
      specs/2026-05-28-winch-design.md             # already exists
      plans/2026-05-28-winch-implementation.md     # this file
      qa/manual-checklist.md                       # created in Task 14
```

**Boundary rationale:**
- Files in `WinchDomain/` import only `Foundation`/`CoreGraphics` and never touch OS frameworks. This is what makes them unit-testable from a SwiftPM package without AppKit.
- Files in `Sources/Winch/Platform/` are each a thin adapter wrapping exactly one OS API. None contain business logic.
- `AppDelegate` is the only place where Platform + Domain meet. Keep it as a wiring file with no logic.

---

### Task 1: Project setup

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/WinchDomain/.gitkeep`
- Create: `Sources/Winch/.gitkeep`
- Create: `Tests/WinchDomainTests/.gitkeep`

- [ ] **Step 1.1: Create Package.swift**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Winch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WinchDomain", targets: ["WinchDomain"]),
        .executable(name: "winch", targets: ["Winch"]),
    ],
    targets: [
        .target(
            name: "WinchDomain",
            path: "Sources/WinchDomain"
        ),
        .executableTarget(
            name: "Winch",
            dependencies: ["WinchDomain"],
            path: "Sources/Winch"
        ),
        .testTarget(
            name: "WinchDomainTests",
            dependencies: ["WinchDomain"],
            path: "Tests/WinchDomainTests"
        ),
    ]
)
```

- [ ] **Step 1.2: Create .gitignore**

```
.build/
.swiftpm/
*.xcodeproj
*.app
.DS_Store
DerivedData/
```

- [ ] **Step 1.3: Create placeholder source files so SPM resolves**

Each `.gitkeep` is an empty file. Create with:

```bash
touch Sources/WinchDomain/.gitkeep Sources/Winch/.gitkeep Tests/WinchDomainTests/.gitkeep
```

Replace `.gitkeep` in `Sources/Winch/` with an actual entry point so the executable target builds:

`Sources/Winch/main.swift`:

```swift
import Foundation

print("Winch placeholder")
```

(This file will be replaced in Task 12. Leaving the `.gitkeep` placeholders in the library and test directories is fine for now.)

- [ ] **Step 1.4: Verify build**

Run: `swift build`
Expected: builds successfully, produces `.build/debug/winch` executable.

Run: `swift test`
Expected: builds successfully, runs zero tests (no test files yet), exits 0.

- [ ] **Step 1.5: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "chore: initialize Swift Package Manager project"
```

---

### Task 2: HotkeyConfig (Domain, TDD)

**Files:**
- Create: `Sources/WinchDomain/HotkeyConfig.swift`
- Create: `Tests/WinchDomainTests/HotkeyConfigTests.swift`

- [ ] **Step 2.1: Write failing tests**

`Tests/WinchDomainTests/HotkeyConfigTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import WinchDomain

final class HotkeyConfigTests: XCTestCase {
    func testExactMatchSucceeds() {
        let config = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        XCTAssertTrue(config.matches([.maskControl, .maskAlternate]))
    }

    func testPartialFlagsFail() {
        let config = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        XCTAssertFalse(config.matches([.maskControl]))
    }

    func testSupersetFails() {
        // Ctrl+Option config must NOT match Ctrl+Option+Shift.
        let config = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        XCTAssertFalse(config.matches([.maskControl, .maskAlternate, .maskShift]))
    }

    func testCapsLockIgnoredInMatching() {
        // Toggle keys must not affect matching.
        let config = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        let flagsWithCaps: CGEventFlags = [.maskControl, .maskAlternate, .maskAlphaShift]
        XCTAssertTrue(config.matches(flagsWithCaps))
    }

    func testEmptyConfigNeverMatches() {
        // Defensive: an empty config (no modifiers selected) must not fire.
        let config = HotkeyConfig(modifierFlags: [])
        XCTAssertFalse(config.matches([]))
        XCTAssertFalse(config.matches([.maskControl]))
    }

    func testRawValueRoundTrip() {
        let original = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        let restored = HotkeyConfig(rawValue: original.rawValue)
        XCTAssertEqual(restored, original)
    }

    func testDefaultIsControlOption() {
        XCTAssertEqual(
            HotkeyConfig.default.modifierFlags,
            [.maskControl, .maskAlternate]
        )
    }
}
```

- [ ] **Step 2.2: Run tests to verify they fail**

Run: `swift test --filter HotkeyConfigTests`
Expected: FAIL — "cannot find 'HotkeyConfig' in scope".

- [ ] **Step 2.3: Implement HotkeyConfig**

`Sources/WinchDomain/HotkeyConfig.swift`:

```swift
import Foundation
import CoreGraphics

public struct HotkeyConfig: Equatable {
    public let modifierFlags: CGEventFlags

    public init(modifierFlags: CGEventFlags) {
        self.modifierFlags = modifierFlags
    }

    public static let `default` = HotkeyConfig(
        modifierFlags: [.maskControl, .maskAlternate]
    )

    // The subset of CGEventFlags bits we consider when matching.
    // Toggle states (Caps Lock, NumLock) and event-source bits are excluded
    // so they cannot accidentally invalidate a match.
    public static let meaningfulMask: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift,
        .maskSecondaryFn,
    ]

    public func matches(_ flags: CGEventFlags) -> Bool {
        guard !modifierFlags.isEmpty else { return false }
        let masked = flags.intersection(Self.meaningfulMask)
        return masked == modifierFlags
    }

    // Round-trips through UserDefaults via raw UInt64.
    public var rawValue: UInt64 { modifierFlags.rawValue }

    public init(rawValue: UInt64) {
        self.modifierFlags = CGEventFlags(rawValue: rawValue)
    }
}
```

- [ ] **Step 2.4: Run tests to verify they pass**

Run: `swift test --filter HotkeyConfigTests`
Expected: PASS — all 7 tests succeed.

- [ ] **Step 2.5: Commit**

```bash
git add Sources/WinchDomain/HotkeyConfig.swift Tests/WinchDomainTests/HotkeyConfigTests.swift
git commit -m "feat(domain): add HotkeyConfig with exact-match modifier logic"
```

---

### Task 3: Protocols + WindowHandle (Domain)

**Files:**
- Create: `Sources/WinchDomain/Protocols.swift`

No tests in this task — these are pure type declarations. They're exercised by `DragControllerTests` in Task 4.

- [ ] **Step 3.1: Create protocols file**

`Sources/WinchDomain/Protocols.swift`:

```swift
import Foundation
import CoreGraphics

// Marker protocol for an opaque window reference. The concrete Platform
// implementation wraps an AXUIElement; tests use a fake class.
// Reference semantics keep handles comparable by identity.
public protocol WindowHandle: AnyObject {}

public protocol WindowControlling {
    /// Returns a handle to the currently focused window of the frontmost app,
    /// or nil if no movable window is available (system UI, fullscreen, etc.).
    func frontmostWindow() -> WindowHandle?

    /// Reads the window's current top-left position in screen coordinates.
    /// Returns nil if the handle is invalid (window closed).
    func position(of window: WindowHandle) -> CGPoint?

    /// Sets the window's top-left position. Silently no-ops on failure
    /// (window closed mid-drag, etc.).
    func setPosition(of window: WindowHandle, to point: CGPoint)
}

public protocol CursorLocating {
    /// Current cursor position in screen coordinates.
    var location: CGPoint { get }
}
```

- [ ] **Step 3.2: Verify build**

Run: `swift build`
Expected: PASS, no errors.

- [ ] **Step 3.3: Commit**

```bash
git add Sources/WinchDomain/Protocols.swift
git commit -m "feat(domain): add WindowControlling and CursorLocating protocols"
```

---

### Task 4: DragController (Domain, TDD)

**Files:**
- Create: `Sources/WinchDomain/DragController.swift`
- Create: `Tests/WinchDomainTests/Fakes.swift`
- Create: `Tests/WinchDomainTests/DragControllerTests.swift`

- [ ] **Step 4.1: Create test fakes**

`Tests/WinchDomainTests/Fakes.swift`:

```swift
import Foundation
import CoreGraphics
@testable import WinchDomain

final class FakeWindowHandle: WindowHandle {
    let id: String
    init(_ id: String) { self.id = id }
}

final class FakeWindowController: WindowControlling {
    var stubFrontmostWindow: WindowHandle?
    var stubPositions: [ObjectIdentifier: CGPoint] = [:]
    var setPositionCalls: [(WindowHandle, CGPoint)] = []

    func frontmostWindow() -> WindowHandle? {
        stubFrontmostWindow
    }

    func position(of window: WindowHandle) -> CGPoint? {
        stubPositions[ObjectIdentifier(window)]
    }

    func setPosition(of window: WindowHandle, to point: CGPoint) {
        setPositionCalls.append((window, point))
    }
}

final class FakeCursorLocator: CursorLocating {
    var location: CGPoint = .zero
}
```

- [ ] **Step 4.2: Write failing tests**

`Tests/WinchDomainTests/DragControllerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import WinchDomain

final class DragControllerTests: XCTestCase {

    private func makeController(
        config: HotkeyConfig = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate]),
        windows: FakeWindowController = FakeWindowController(),
        cursor: FakeCursorLocator = FakeCursorLocator()
    ) -> (DragController, FakeWindowController, FakeCursorLocator) {
        let controller = DragController(
            hotkeyConfig: config,
            windowController: windows,
            cursorLocator: cursor
        )
        return (controller, windows, cursor)
    }

    func testStartsIdle() {
        let (controller, _, _) = makeController()
        XCTAssertTrue(controller.isIdle)
    }

    func testEntersTrackingOnHotkeyMatch() {
        let (controller, windows, cursor) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = CGPoint(x: 100, y: 200)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertFalse(controller.isIdle)
    }

    func testStaysIdleWhenNoFrontmostWindow() {
        let (controller, windows, _) = makeController()
        windows.stubFrontmostWindow = nil

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testStaysIdleWhenWindowHasNoPosition() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        // No stubPositions entry → position(of:) returns nil

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testMouseMovedUpdatesWindowPosition() {
        let (controller, windows, cursor) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = CGPoint(x: 100, y: 200)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 80, y: 70)
        controller.handleMouseMoved()

        XCTAssertEqual(windows.setPositionCalls.count, 1)
        // origin window (100, 200) + delta (30, 20) = (130, 220)
        XCTAssertEqual(windows.setPositionCalls[0].1, CGPoint(x: 130, y: 220))
    }

    func testMultipleMouseMovesAllRelativeToOriginNotCumulative() {
        // Regression guard: ensure we use absolute offset from snapshot,
        // not accumulated deltas.
        let (controller, windows, cursor) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = CGPoint(x: 0, y: 0)
        cursor.location = CGPoint(x: 0, y: 0)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        cursor.location = CGPoint(x: 10, y: 10)
        controller.handleMouseMoved()
        cursor.location = CGPoint(x: 20, y: 20)
        controller.handleMouseMoved()
        cursor.location = CGPoint(x: 30, y: 30)
        controller.handleMouseMoved()

        XCTAssertEqual(windows.setPositionCalls.map { $0.1 }, [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 20, y: 20),
            CGPoint(x: 30, y: 30),
        ])
    }

    func testTransitionsToIdleOnHotkeyRelease() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = .zero

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertFalse(controller.isIdle)

        controller.handleFlagsChanged([])
        XCTAssertTrue(controller.isIdle)
    }

    func testMouseMovedIgnoredWhenIdle() {
        let (controller, windows, _) = makeController()
        controller.handleMouseMoved()
        XCTAssertEqual(windows.setPositionCalls.count, 0)
    }

    func testPausedDoesNotEnterTracking() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = .zero
        controller.isPaused = true

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testPausedDuringDragForcesIdle() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = .zero

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertFalse(controller.isIdle)

        controller.isPaused = true
        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testHotkeyConfigCanBeReplacedAtRuntime() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = .zero

        controller.hotkeyConfig = HotkeyConfig(modifierFlags: [.maskCommand])
        controller.handleFlagsChanged([.maskCommand])

        XCTAssertFalse(controller.isIdle)
    }
}
```

- [ ] **Step 4.3: Run tests to verify they fail**

Run: `swift test --filter DragControllerTests`
Expected: FAIL — "cannot find 'DragController' in scope".

- [ ] **Step 4.4: Implement DragController**

`Sources/WinchDomain/DragController.swift`:

```swift
import Foundation
import CoreGraphics

public final class DragController {
    private enum State {
        case idle
        case tracking(window: WindowHandle, originCursor: CGPoint, originWindow: CGPoint)
    }

    private var state: State = .idle
    public var hotkeyConfig: HotkeyConfig
    public var isPaused: Bool = false

    private let windowController: WindowControlling
    private let cursorLocator: CursorLocating

    public init(
        hotkeyConfig: HotkeyConfig,
        windowController: WindowControlling,
        cursorLocator: CursorLocating
    ) {
        self.hotkeyConfig = hotkeyConfig
        self.windowController = windowController
        self.cursorLocator = cursorLocator
    }

    public var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    public func handleFlagsChanged(_ flags: CGEventFlags) {
        if isPaused {
            state = .idle
            return
        }

        if hotkeyConfig.matches(flags) {
            if case .idle = state {
                tryEnterTracking()
            }
            // Already tracking — keep the existing snapshot.
        } else {
            state = .idle
        }
    }

    public func handleMouseMoved() {
        if isPaused { return }
        guard case let .tracking(window, originCursor, originWindow) = state else {
            return
        }
        let current = cursorLocator.location
        let newPos = CGPoint(
            x: originWindow.x + (current.x - originCursor.x),
            y: originWindow.y + (current.y - originCursor.y)
        )
        windowController.setPosition(of: window, to: newPos)
    }

    private func tryEnterTracking() {
        guard let window = windowController.frontmostWindow() else { return }
        guard let originWindow = windowController.position(of: window) else { return }
        state = .tracking(
            window: window,
            originCursor: cursorLocator.location,
            originWindow: originWindow
        )
    }
}
```

- [ ] **Step 4.5: Run tests to verify they pass**

Run: `swift test --filter DragControllerTests`
Expected: PASS — all 11 tests succeed.

- [ ] **Step 4.6: Commit**

```bash
git add Sources/WinchDomain/DragController.swift Tests/WinchDomainTests/Fakes.swift Tests/WinchDomainTests/DragControllerTests.swift
git commit -m "feat(domain): add DragController state machine with full test coverage"
```

---

### Task 5: WindowController (Platform — AXUIElement adapter)

**Files:**
- Create: `Sources/Winch/Platform/WindowController.swift`

No unit tests — this is a thin adapter over `AXUIElement`. It will be exercised by manual QA in Task 14. The interface contract is enforced by Domain tests.

- [ ] **Step 5.1: Implement WindowController**

`Sources/Winch/Platform/WindowController.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import WinchDomain

/// Wraps an AXUIElement reference as an opaque WindowHandle.
final class AXWindow: WindowHandle {
    let element: AXUIElement
    init(_ element: AXUIElement) {
        self.element = element
    }
}

final class WindowController: WindowControlling {

    func frontmostWindow() -> WindowHandle? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focused
        )
        guard result == .success, let focused = focused else { return nil }
        let windowElement = focused as! AXUIElement  // AX attribute is always AXUIElement when result is .success

        // Reject windows we cannot move (system UI, fullscreen panels).
        var movable: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            windowElement,
            "AXMovable" as CFString,  // kAXMovableAttribute (not in headers on all SDK versions)
            &movable
        ) == .success, let movableBool = movable as? Bool, !movableBool {
            return nil
        }

        return AXWindow(windowElement)
    }

    func position(of window: WindowHandle) -> CGPoint? {
        guard let window = window as? AXWindow else { return nil }
        var positionValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        guard result == .success, let value = positionValue else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    func setPosition(of window: WindowHandle, to point: CGPoint) {
        guard let window = window as? AXWindow else { return }
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return }
        // Silently ignore failure: window may have closed mid-drag.
        _ = AXUIElementSetAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            value
        )
    }
}
```

- [ ] **Step 5.2: Verify build**

Run: `swift build`
Expected: PASS, no errors.

- [ ] **Step 5.3: Commit**

```bash
git add Sources/Winch/Platform/WindowController.swift
git commit -m "feat(platform): add WindowController backed by AXUIElement"
```

---

### Task 6: SystemCursorLocator (Platform)

**Files:**
- Create: `Sources/Winch/Platform/SystemCursorLocator.swift`

- [ ] **Step 6.1: Implement SystemCursorLocator**

`Sources/Winch/Platform/SystemCursorLocator.swift`:

```swift
import AppKit
import CoreGraphics
import WinchDomain

final class SystemCursorLocator: CursorLocating {
    var location: CGPoint {
        // NSEvent.mouseLocation is in bottom-left origin (AppKit screen coords).
        // AXUIElement positions are in top-left origin (Quartz screen coords).
        // Convert by flipping against the primary display height.
        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return mouse }
        return CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
    }
}
```

- [ ] **Step 6.2: Verify build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 6.3: Commit**

```bash
git add Sources/Winch/Platform/SystemCursorLocator.swift
git commit -m "feat(platform): add SystemCursorLocator with AppKit→Quartz coord flip"
```

---

### Task 7: PermissionManager (Platform)

**Files:**
- Create: `Sources/Winch/Platform/PermissionManager.swift`

- [ ] **Step 7.1: Implement PermissionManager**

`Sources/Winch/Platform/PermissionManager.swift`:

```swift
import AppKit
import ApplicationServices
import Foundation

final class PermissionManager {

    /// Called whenever the Accessibility trust status changes.
    var onStatusChange: ((Bool) -> Void)?

    private var pollTimer: Timer?
    private var lastKnownTrusted: Bool

    init() {
        self.lastKnownTrusted = AXIsProcessTrusted()
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user via the system "App wants to control your computer" dialog.
    func requestWithPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Starts polling every 1 second to detect permission grant or revocation.
    /// Calls `onStatusChange` on every transition.
    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = AXIsProcessTrusted()
            if current != self.lastKnownTrusted {
                self.lastKnownTrusted = current
                self.onStatusChange?(current)
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
```

- [ ] **Step 7.2: Verify build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 7.3: Commit**

```bash
git add Sources/Winch/Platform/PermissionManager.swift
git commit -m "feat(platform): add PermissionManager with 1s polling for trust changes"
```

---

### Task 8: EventTap (Platform)

**Files:**
- Create: `Sources/Winch/Platform/EventTap.swift`

- [ ] **Step 8.1: Implement EventTap**

`Sources/Winch/Platform/EventTap.swift`:

```swift
import AppKit
import CoreGraphics
import Foundation

final class EventTap {

    enum Event {
        case flagsChanged(CGEventFlags)
        case mouseMoved
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callback: ((Event) -> Void)?

    /// Installs a passive CGEventTap that observes flagsChanged + mouseMoved.
    /// Events are NOT consumed — they pass through to the rest of the system.
    /// Returns false if the tap could not be created (typically: no Accessibility permission).
    @discardableResult
    func install(callback: @escaping (Event) -> Void) -> Bool {
        uninstall()
        self.callback = callback

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: EventTap.tapCallback,
            userInfo: context
        ) else {
            self.callback = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func uninstall() {
        if let tap, let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        runLoopSource = nil
        callback = nil
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let me = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

        switch type {
        case .flagsChanged:
            me.callback?(.flagsChanged(event.flags))
        case .mouseMoved:
            me.callback?(.mouseMoved)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = me.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
```

- [ ] **Step 8.2: Verify build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 8.3: Commit**

```bash
git add Sources/Winch/Platform/EventTap.swift
git commit -m "feat(platform): add CGEventTap wrapper with auto re-enable on disable"
```

---

### Task 9: SettingsStore (Platform)

**Files:**
- Create: `Sources/Winch/Platform/SettingsStore.swift`

- [ ] **Step 9.1: Implement SettingsStore**

`Sources/Winch/Platform/SettingsStore.swift`:

```swift
import Foundation
import CoreGraphics
import WinchDomain

final class SettingsStore {

    private let defaults: UserDefaults

    private enum Key {
        static let hotkeyModifierFlags = "hotkey.modifierFlags"
        static let appPaused = "app.paused"
        static let launchAtLogin = "app.launchAtLogin"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hotkeyConfig: HotkeyConfig {
        get {
            if defaults.object(forKey: Key.hotkeyModifierFlags) == nil {
                return .default
            }
            let raw = UInt64(bitPattern: Int64(defaults.integer(forKey: Key.hotkeyModifierFlags)))
            let config = HotkeyConfig(rawValue: raw)
            // Defensive: an empty config saved by an older build → reset to default.
            return config.modifierFlags.isEmpty ? .default : config
        }
        set {
            defaults.set(Int64(bitPattern: newValue.rawValue), forKey: Key.hotkeyModifierFlags)
        }
    }

    var isPaused: Bool {
        get { defaults.bool(forKey: Key.appPaused) }
        set { defaults.set(newValue, forKey: Key.appPaused) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }
}
```

- [ ] **Step 9.2: Verify build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 9.3: Commit**

```bash
git add Sources/Winch/Platform/SettingsStore.swift
git commit -m "feat(platform): add SettingsStore UserDefaults wrapper"
```

---

### Task 10: LoginItemManager (Platform)

**Files:**
- Create: `Sources/Winch/Platform/LoginItemManager.swift`

- [ ] **Step 10.1: Implement LoginItemManager**

`Sources/Winch/Platform/LoginItemManager.swift`:

```swift
import Foundation
import ServiceManagement

final class LoginItemManager {

    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers the main app to launch at login. Throws on failure
    /// (e.g., the bundle is not signed or the user denied the operation).
    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
```

- [ ] **Step 10.2: Verify build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 10.3: Commit**

```bash
git add Sources/Winch/Platform/LoginItemManager.swift
git commit -m "feat(platform): add LoginItemManager via SMAppService"
```

---

### Task 11: MenuBarController (UI)

**Files:**
- Create: `Sources/Winch/UI/MenuBarController.swift`

- [ ] **Step 11.1: Implement MenuBarController**

`Sources/Winch/UI/MenuBarController.swift`:

```swift
import AppKit

final class MenuBarController: NSObject {

    enum Status {
        case active
        case paused
        case permissionMissing
    }

    var onTogglePause: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private(set) var status: Status = .active

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "W"
        rebuildMenu()
        updateAppearance()
    }

    func setStatus(_ status: Status) {
        self.status = status
        rebuildMenu()
        updateAppearance()
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        switch status {
        case .active:            button.title = "●W"
        case .paused:            button.title = "⏸W"
        case .permissionMissing: button.title = "⚠W"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        switch status {
        case .active:
            menu.addItem(disabled("Winch is active"))
        case .paused:
            menu.addItem(disabled("Winch is paused"))
        case .permissionMissing:
            menu.addItem(disabled("Accessibility permission required"))
        }
        menu.addItem(.separator())

        let pauseTitle = (status == .paused) ? "Resume" : "Pause"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        if status == .permissionMissing { pauseItem.isEnabled = false }
        menu.addItem(pauseItem)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Winch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func togglePause() { onTogglePause?() }
    @objc private func openPreferences() { onOpenPreferences?() }
    @objc private func quit() { onQuit?() }
}
```

- [ ] **Step 11.2: Verify build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 11.3: Commit**

```bash
git add Sources/Winch/UI/MenuBarController.swift
git commit -m "feat(ui): add MenuBarController with status-aware menu"
```

---

### Task 12: PreferencesView + PreferencesWindowController (UI)

**Files:**
- Create: `Sources/Winch/UI/PreferencesView.swift`
- Create: `Sources/Winch/UI/PreferencesWindowController.swift`

- [ ] **Step 12.1: Implement PreferencesView**

`Sources/Winch/UI/PreferencesView.swift`:

```swift
import SwiftUI
import Combine
import CoreGraphics
import WinchDomain

struct PreferencesView: View {

    @ObservedObject var model: PreferencesModel

    var body: some View {
        Form {
            Section("Trigger") {
                Toggle("⌘ Command", isOn: $model.command)
                Toggle("⌥ Option",  isOn: $model.option)
                Toggle("⌃ Control", isOn: $model.control)
                Toggle("⇧ Shift",   isOn: $model.shift)
                Toggle("fn Function", isOn: $model.fn)
                if model.isEmpty {
                    Text("At least one modifier is required.")
                        .foregroundColor(.red)
                        .font(.caption)
                } else {
                    Text("Hold \(model.previewSymbols) and move the cursor to drag the focused window.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Startup") {
                Toggle("Launch Winch at login", isOn: $model.launchAtLogin)
            }

            if !model.isAccessibilityTrusted {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Accessibility permission is required for Winch to move windows.")
                            .font(.caption)
                        Spacer()
                        Button("Open System Settings") { model.openSystemSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}

@MainActor
final class PreferencesModel: ObservableObject {

    @Published var command: Bool { didSet { publishHotkey() } }
    @Published var option: Bool  { didSet { publishHotkey() } }
    @Published var control: Bool { didSet { publishHotkey() } }
    @Published var shift: Bool   { didSet { publishHotkey() } }
    @Published var fn: Bool      { didSet { publishHotkey() } }
    @Published var launchAtLogin: Bool { didSet { onLaunchAtLoginChange?(launchAtLogin) } }
    @Published var isAccessibilityTrusted: Bool

    var onHotkeyChange: ((HotkeyConfig) -> Void)?
    var onLaunchAtLoginChange: ((Bool) -> Void)?
    var onOpenSystemSettings: (() -> Void)?

    init(
        initial: HotkeyConfig,
        launchAtLogin: Bool,
        isAccessibilityTrusted: Bool
    ) {
        self.command = initial.modifierFlags.contains(.maskCommand)
        self.option  = initial.modifierFlags.contains(.maskAlternate)
        self.control = initial.modifierFlags.contains(.maskControl)
        self.shift   = initial.modifierFlags.contains(.maskShift)
        self.fn      = initial.modifierFlags.contains(.maskSecondaryFn)
        self.launchAtLogin = launchAtLogin
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }

    var isEmpty: Bool {
        currentFlags.isEmpty
    }

    var previewSymbols: String {
        var s = ""
        if control { s += "⌃" }
        if option  { s += "⌥" }
        if shift   { s += "⇧" }
        if command { s += "⌘" }
        if fn      { s += "fn" }
        return s.isEmpty ? "—" : s
    }

    private var currentFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option  { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        if shift   { flags.insert(.maskShift) }
        if fn      { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func publishHotkey() {
        guard !currentFlags.isEmpty else { return }
        onHotkeyChange?(HotkeyConfig(modifierFlags: currentFlags))
    }

    func openSystemSettings() {
        onOpenSystemSettings?()
    }
}
```

- [ ] **Step 12.2: Implement PreferencesWindowController**

`Sources/Winch/UI/PreferencesWindowController.swift`:

```swift
import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {

    convenience init(rootView: PreferencesView) {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Winch Preferences"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 320))
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 12.3: Verify build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 12.4: Commit**

```bash
git add Sources/Winch/UI/PreferencesView.swift Sources/Winch/UI/PreferencesWindowController.swift
git commit -m "feat(ui): add SwiftUI preferences window with modifier toggles"
```

---

### Task 13: AppDelegate + main.swift (Wire everything)

**Files:**
- Modify: `Sources/Winch/main.swift`
- Create: `Sources/Winch/AppDelegate.swift`

- [ ] **Step 13.1: Replace main.swift entry point**

Overwrite `Sources/Winch/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // No Dock icon (LSUIElement equivalent at runtime)
app.run()
```

- [ ] **Step 13.2: Implement AppDelegate**

`Sources/Winch/AppDelegate.swift`:

```swift
import AppKit
import WinchDomain

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBar: MenuBarController!
    private var permissions: PermissionManager!
    private var eventTap: EventTap!
    private var dragController: DragController!
    private var windowController: WindowController!
    private var cursorLocator: SystemCursorLocator!
    private var settings: SettingsStore!
    private var loginItem: LoginItemManager!
    private var preferencesWindow: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings        = SettingsStore()
        windowController = WindowController()
        cursorLocator   = SystemCursorLocator()
        loginItem       = LoginItemManager()
        permissions     = PermissionManager()
        eventTap        = EventTap()
        menuBar         = MenuBarController()

        dragController = DragController(
            hotkeyConfig: settings.hotkeyConfig,
            windowController: windowController,
            cursorLocator: cursorLocator
        )
        dragController.isPaused = settings.isPaused

        wireMenuBar()
        wirePermissions()

        if permissions.isTrusted {
            installEventTap()
            updateStatus()
        } else {
            menuBar.setStatus(.permissionMissing)
            permissions.requestWithPrompt()
        }
        permissions.startPolling()
    }

    private func wireMenuBar() {
        menuBar.onTogglePause = { [weak self] in
            guard let self else { return }
            self.dragController.isPaused.toggle()
            self.settings.isPaused = self.dragController.isPaused
            self.updateStatus()
        }
        menuBar.onOpenPreferences = { [weak self] in
            self?.openPreferences()
        }
        menuBar.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func wirePermissions() {
        permissions.onStatusChange = { [weak self] trusted in
            guard let self else { return }
            if trusted {
                self.installEventTap()
            } else {
                self.eventTap.uninstall()
            }
            self.updateStatus()
            // Update an open preferences window, if any.
            self.openPreferencesModelIfShowing()?.isAccessibilityTrusted = trusted
        }
    }

    private func installEventTap() {
        let installed = eventTap.install { [weak self] event in
            guard let self else { return }
            switch event {
            case .flagsChanged(let flags):
                self.dragController.handleFlagsChanged(flags)
            case .mouseMoved:
                self.dragController.handleMouseMoved()
            }
        }
        if !installed {
            menuBar.setStatus(.permissionMissing)
        }
    }

    private func updateStatus() {
        if !permissions.isTrusted {
            menuBar.setStatus(.permissionMissing)
        } else if dragController.isPaused {
            menuBar.setStatus(.paused)
        } else {
            menuBar.setStatus(.active)
        }
    }

    private func openPreferences() {
        if preferencesWindow == nil {
            let model = PreferencesModel(
                initial: settings.hotkeyConfig,
                launchAtLogin: loginItem.isRegistered,
                isAccessibilityTrusted: permissions.isTrusted
            )
            model.onHotkeyChange = { [weak self] config in
                self?.settings.hotkeyConfig = config
                self?.dragController.hotkeyConfig = config
            }
            model.onLaunchAtLoginChange = { [weak self] enabled in
                guard let self else { return }
                do {
                    if enabled { try self.loginItem.register() }
                    else       { try self.loginItem.unregister() }
                    self.settings.launchAtLogin = enabled
                } catch {
                    NSLog("Login item update failed: \(error)")
                }
            }
            model.onOpenSystemSettings = { [weak self] in
                self?.permissions.openSystemSettings()
            }
            preferencesWindow = PreferencesWindowController(
                rootView: PreferencesView(model: model)
            )
        }
        preferencesWindow?.show()
    }

    private func openPreferencesModelIfShowing() -> PreferencesModel? {
        guard let window = preferencesWindow?.window,
              window.isVisible,
              let hosting = window.contentViewController as? NSHostingController<PreferencesView>
        else { return nil }
        return hosting.rootView.model
    }
}
```

- [ ] **Step 13.3: Verify build and run**

Run: `swift build`
Expected: PASS.

Run: `swift run winch`
Expected: A menu bar item appears with title `●W` (or `⚠W` if Accessibility isn't granted). The system prompts for Accessibility permission on first run.

- [ ] **Step 13.4: Smoke test (manual)**

1. Grant Accessibility permission in System Settings → Privacy & Security → Accessibility for the running `winch` process.
2. Open any movable window (e.g., Finder).
3. Hold `Ctrl + Option` and move the cursor.
4. Confirm the window follows the cursor.
5. Release modifiers; window stays at the new position.
6. Quit via menu bar → "Quit Winch".

- [ ] **Step 13.5: Commit**

```bash
git add Sources/Winch/main.swift Sources/Winch/AppDelegate.swift
git commit -m "feat: wire AppDelegate, EventTap, DragController into running app"
```

---

### Task 14: .app bundle assembly script

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/bundle-app.sh`
- Create: `Makefile`

- [ ] **Step 14.1: Create Info.plist**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Winch</string>
    <key>CFBundleDisplayName</key>
    <string>Winch</string>
    <key>CFBundleIdentifier</key>
    <string>com.hyakoo.winch</string>
    <key>CFBundleExecutable</key>
    <string>winch</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 hyakoo</string>
</dict>
</plist>
```

- [ ] **Step 14.2: Create bundle script**

`scripts/bundle-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-release}"
APP_NAME="Winch.app"
BUILD_DIR=".build/${CONFIG}"
APP_DIR="${BUILD_DIR}/${APP_NAME}"

echo "Building winch ($CONFIG)..."
swift build -c "$CONFIG"

echo "Assembling ${APP_NAME}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "${BUILD_DIR}/winch" "$APP_DIR/Contents/MacOS/winch"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

echo "Done: ${APP_DIR}"
```

Make executable:

```bash
chmod +x scripts/bundle-app.sh
```

- [ ] **Step 14.3: Create Makefile**

`Makefile`:

```makefile
.PHONY: build test app clean run

build:
	swift build

test:
	swift test

app:
	./scripts/bundle-app.sh

run: build
	swift run winch

clean:
	rm -rf .build
```

- [ ] **Step 14.4: Verify bundle assembly**

Run: `make app`
Expected: produces `.build/release/Winch.app`. Open it: `open .build/release/Winch.app`.

Verify:
- No Dock icon appears (LSUIElement working).
- Menu bar item appears.
- App responds to permission grant and modifier-drag.

- [ ] **Step 14.5: Commit**

```bash
git add Resources/Info.plist scripts/bundle-app.sh Makefile
git commit -m "build: add Info.plist and .app bundle assembly script"
```

---

### Task 15: Manual QA checklist

**Files:**
- Create: `docs/superpowers/qa/manual-checklist.md`

- [ ] **Step 15.1: Write QA checklist**

`docs/superpowers/qa/manual-checklist.md`:

```markdown
# Winch Manual QA Checklist

Run before each release. Build via `make app` and launch `.build/release/Winch.app`.

## Permission flow
- [ ] Fresh launch with no Accessibility permission → menu bar shows ⚠W, system prompt appears
- [ ] Grant permission → within ~1s, menu bar transitions to ●W, drag begins working
- [ ] Revoke permission in System Settings → within ~1s, menu bar transitions to ⚠W, drag stops working

## Basic drag
- [ ] Open Finder window, focus it, hold Ctrl+Option, move cursor → window follows
- [ ] Release modifiers mid-drag → window stops following, stays at last position
- [ ] Re-press modifiers without moving cursor → drag re-engages with new snapshot

## Hotkey configuration
- [ ] Open Preferences, toggle off Ctrl, on Cmd → new combo Cmd+Option becomes active immediately
- [ ] Uncheck all modifiers → red "At least one modifier is required" appears, drag stops
- [ ] Recheck modifiers → drag resumes

## Pause / resume
- [ ] Menu bar → "Pause" → status changes to ⏸W, modifier+drag does nothing
- [ ] Menu bar → "Resume" → status changes to ●W, drag works again
- [ ] Pause state persists across app restart

## Login item
- [ ] Toggle "Launch at login" on, restart Mac → Winch starts automatically
- [ ] Toggle off, restart Mac → Winch does not start

## Edge cases
- [ ] Hold hotkey over fullscreen window → no drag, no crash
- [ ] Hold hotkey over Dock / menu bar / desktop with no focused window → no crash
- [ ] Drag a window from primary display onto secondary display → crosses cleanly
- [ ] Drag window beyond screen edge → allowed, no clamping
- [ ] System sleep → wake → drag still works (EventTap re-enabled)
- [ ] Switch focused app mid-drag (e.g., Cmd+Tab while holding hotkey) → original window keeps moving until hotkey release

## Exit
- [ ] Menu bar → "Quit Winch" → app exits cleanly, menu bar item disappears
```

- [ ] **Step 15.2: Commit**

```bash
git add docs/superpowers/qa/manual-checklist.md
git commit -m "docs: add manual QA checklist for releases"
```

---

## Out of scope (per spec)

These are intentionally **not** in this plan:
- Window resize / edge-snap / tiling
- Keyboard shortcuts for instant window placement (Win+arrow style)
- Sparkle auto-update integration
- Localization
- App Store submission
- Crash reporting
- Code signing / notarization automation (manual `codesign` + `notarytool` documented separately at release time)
