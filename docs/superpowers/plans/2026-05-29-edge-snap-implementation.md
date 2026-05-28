# Edge Snap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 3-zone edge snap (left/right halves + top fullscreen) to the existing window-drag gesture, with a translucent preview overlay during hover and automatic restore of pre-snap size on re-drag.

**Architecture:** Extend `DragController`'s `Tracking` state with `currentSnapZone` and a `preSnapFrames` map. Add a pure Domain calculator (`SnapZoneCalculator`) for zone detection and target geometry. Add Platform adapters: `ScreenInfoProvider` (NSScreen visible frame), `WindowController.frame/setFrame` (replace position-only API). Add a UI component (`SnapPreviewWindow`) — a borderless translucent NSWindow rendering the target rectangle, driven by an `onSnapZoneChanged` callback from `DragController` via `AppDelegate`.

**Tech Stack:** Swift, AppKit (`NSWindow`, `NSScreen`, `NSColor.controlAccentColor`), Accessibility API (`kAXSizeAttribute`), XCTest. No new external dependencies.

**Spec:** `docs/superpowers/specs/2026-05-29-edge-snap-design.md`

---

## File Structure

```
winch/
  Sources/
    WinchDomain/
      Protocols.swift                # MODIFY — add ScreenInfoProviding, SnapPreviewing; change WindowControlling (position→frame, add setFrame)
      SnapTarget.swift               # NEW — enum SnapZone, struct SnapTarget
      SnapZoneCalculator.swift       # NEW — pure functions
      DragController.swift           # MODIFY — extended state, snap logic, restore logic
    Winch/
      AppDelegate.swift              # MODIFY — wire screenInfoProvider, SnapPreviewWindow, snap toggle
      Platform/
        WindowController.swift       # MODIFY — frame(of:), setFrame(of:to:); remove position(of:)
        ScreenInfoProvider.swift     # NEW — NSScreen.visibleFrame containing point, coord flip
        SettingsStore.swift          # MODIFY — isSnapEnabled (snap.enabled key, default true)
      UI/
        SnapPreviewWindow.swift      # NEW — borderless translucent NSWindow + custom NSView
        PreferencesView.swift        # MODIFY — Edge Snap section + toggle, model property + callback
  Tests/
    WinchDomainTests/
      SnapZoneCalculatorTests.swift  # NEW — zone detection + target geometry
      DragControllerTests.swift      # MODIFY — snap entry/exit, commit, restore, isSnapEnabled=false
      Fakes.swift                    # MODIFY — FakeScreenInfoProvider; FakeWindowController frame/setFrame
  docs/superpowers/qa/
    manual-checklist.md              # MODIFY — add snap QA items
```

The plan is ordered so Domain types and pure calculators land first (TDD-friendly), then `WindowControlling` migrates, then `DragController` extends, then Platform/UI wire-up.

---

### Task 1: SnapTarget types (Domain)

**Files:**
- Create: `Sources/WinchDomain/SnapTarget.swift`

No tests in this task — these are pure type declarations. Exercised by `SnapZoneCalculatorTests` (Task 2) and `DragControllerTests` (Task 6).

- [ ] **Step 1.1: Create SnapTarget.swift**

`Sources/WinchDomain/SnapTarget.swift`:

```swift
import CoreGraphics

public enum SnapZone: Equatable {
    case left
    case right
    case top
}

public struct SnapTarget: Equatable {
    public let zone: SnapZone
    public let frame: CGRect

    public init(zone: SnapZone, frame: CGRect) {
        self.zone = zone
        self.frame = frame
    }
}
```

- [ ] **Step 1.2: Verify build**

Run: `swift build`
Expected: PASS, no errors.

Run: `swift test`
Expected: 18/18 still passing.

- [ ] **Step 1.3: Commit**

```bash
git add Sources/WinchDomain/SnapTarget.swift
git -c commit.gpgsign=false commit -m "feat(domain): add SnapZone and SnapTarget types"
```

---

### Task 2: SnapZoneCalculator (Domain, TDD)

**Files:**
- Create: `Sources/WinchDomain/SnapZoneCalculator.swift`
- Create: `Tests/WinchDomainTests/SnapZoneCalculatorTests.swift`

- [ ] **Step 2.1: Write failing tests**

`Tests/WinchDomainTests/SnapZoneCalculatorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import WinchDomain

final class SnapZoneCalculatorTests: XCTestCase {

    // Standard 1440x900 screen, origin at (0, 0), top-left.
    private let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    // MARK: zone(forCursor:in:)

    func testReturnsNilInCenter() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 720, y: 450), in: frame)
        XCTAssertNil(z)
    }

    func testReturnsTopForCursorAtTopEdge() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 720, y: 2), in: frame)
        XCTAssertEqual(z, .top)
    }

    func testReturnsTopAtExactlyThreshold() {
        // Threshold is 8; cursor at y=7 is INSIDE (< minY + 8).
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 720, y: 7), in: frame)
        XCTAssertEqual(z, .top)
    }

    func testReturnsNilJustBelowTopThreshold() {
        // y=8 is NOT < 0 + 8 → outside top zone.
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 720, y: 8), in: frame)
        XCTAssertNil(z)
    }

    func testReturnsLeftForCursorAtLeftEdge() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 2, y: 450), in: frame)
        XCTAssertEqual(z, .left)
    }

    func testReturnsRightForCursorAtRightEdge() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 1438, y: 450), in: frame)
        XCTAssertEqual(z, .right)
    }

    func testTopWinsOverLeftAtTopLeftCorner() {
        // Cursor in corner where both top AND left thresholds are met.
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 2, y: 2), in: frame)
        XCTAssertEqual(z, .top)
    }

    func testTopWinsOverRightAtTopRightCorner() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 1438, y: 2), in: frame)
        XCTAssertEqual(z, .top)
    }

    func testReturnsNilWhenCursorOutsideFrameLeft() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: -10, y: 450), in: frame)
        // Cursor left of minX → x < minX + 8 still true → .left
        // This is intentional: the threshold treats anything <= minX+8 as "left zone",
        // including negative x. The caller is responsible for picking the right screen.
        XCTAssertEqual(z, .left)
    }

    // MARK: target(for:in:)

    func testTargetForTopIsFullVisibleFrame() {
        let t = SnapZoneCalculator.target(for: .top, in: frame)
        XCTAssertEqual(t, frame)
    }

    func testTargetForLeftIsLeftHalf() {
        let t = SnapZoneCalculator.target(for: .left, in: frame)
        XCTAssertEqual(t, CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    func testTargetForRightIsRightHalf() {
        let t = SnapZoneCalculator.target(for: .right, in: frame)
        XCTAssertEqual(t, CGRect(x: 720, y: 0, width: 720, height: 900))
    }

    func testTargetForLeftRespectsNonZeroOrigin() {
        // Simulate a secondary screen with origin (1440, 100) and size (1280, 800).
        let secondary = CGRect(x: 1440, y: 100, width: 1280, height: 800)
        let t = SnapZoneCalculator.target(for: .left, in: secondary)
        XCTAssertEqual(t, CGRect(x: 1440, y: 100, width: 640, height: 800))
    }

    func testTargetForRightRespectsNonZeroOrigin() {
        let secondary = CGRect(x: 1440, y: 100, width: 1280, height: 800)
        let t = SnapZoneCalculator.target(for: .right, in: secondary)
        XCTAssertEqual(t, CGRect(x: 2080, y: 100, width: 640, height: 800))
    }

    func testEdgeThresholdIsEight() {
        XCTAssertEqual(SnapZoneCalculator.edgeThreshold, 8)
    }
}
```

- [ ] **Step 2.2: Run tests to verify they fail**

Run: `swift test --filter SnapZoneCalculatorTests`
Expected: FAIL — "cannot find 'SnapZoneCalculator' in scope".

- [ ] **Step 2.3: Implement SnapZoneCalculator**

`Sources/WinchDomain/SnapZoneCalculator.swift`:

```swift
import CoreGraphics

public enum SnapZoneCalculator {
    public static let edgeThreshold: CGFloat = 8

    /// Returns the snap zone the cursor is currently in, or nil if outside any zone.
    /// Top zone owns the corners — left/right are only matched when not in top.
    public static func zone(forCursor cursor: CGPoint, in visibleFrame: CGRect) -> SnapZone? {
        if cursor.y < visibleFrame.minY + edgeThreshold { return .top }
        if cursor.x < visibleFrame.minX + edgeThreshold { return .left }
        if cursor.x > visibleFrame.maxX - edgeThreshold { return .right }
        return nil
    }

    /// Returns the window frame to apply when committing the given snap zone.
    public static func target(for zone: SnapZone, in visibleFrame: CGRect) -> CGRect {
        switch zone {
        case .top:
            return visibleFrame
        case .left:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .right:
            return CGRect(
                x: visibleFrame.minX + visibleFrame.width / 2,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        }
    }
}
```

- [ ] **Step 2.4: Run tests to verify they pass**

Run: `swift test --filter SnapZoneCalculatorTests`
Expected: PASS — all 14 tests succeed.

- [ ] **Step 2.5: Commit**

```bash
git add Sources/WinchDomain/SnapZoneCalculator.swift Tests/WinchDomainTests/SnapZoneCalculatorTests.swift
git -c commit.gpgsign=false commit -m "feat(domain): add SnapZoneCalculator with zone and target functions"
```

---

### Task 3: Domain protocols — ScreenInfoProviding, SnapPreviewing, WindowControlling migration

**Files:**
- Modify: `Sources/WinchDomain/Protocols.swift`

This task changes the `WindowControlling` protocol shape (`position` → `frame`, plus `setFrame`). It will break compilation of `WindowController` and the existing `DragController` until Tasks 4 and 5 catch up. We will work through that breakage step by step.

- [ ] **Step 3.1: Replace Protocols.swift**

Overwrite `Sources/WinchDomain/Protocols.swift`:

```swift
import CoreGraphics

// Marker protocol for an opaque window reference. The concrete Platform
// implementation wraps an AXUIElement; tests use a fake class.
// Reference semantics keep handles comparable by identity.
public protocol WindowHandle: AnyObject {}

public protocol WindowControlling {
    /// Returns a handle to the currently focused window of the frontmost app,
    /// or nil if no movable window is available (system UI, fullscreen, etc.).
    func frontmostWindow() -> WindowHandle?

    /// Reads the window's current frame (position + size) in screen coordinates
    /// with top-left origin. Returns nil if the handle is invalid.
    func frame(of window: WindowHandle) -> CGRect?

    /// Sets the window's top-left position. Silently no-ops on failure.
    func setPosition(of window: WindowHandle, to point: CGPoint)

    /// Sets the window's full frame (position + size). Used for snap commit and
    /// pre-snap restoration. Silently no-ops on failure.
    func setFrame(of window: WindowHandle, to frame: CGRect)
}

public protocol CursorLocating {
    /// Current cursor position in top-left screen coordinates.
    var location: CGPoint { get }
}

public protocol ScreenInfoProviding {
    /// Returns the visible frame (excludes menu bar and Dock) of the screen
    /// containing the given point, in top-left screen coordinates.
    /// Returns nil if the point is not on any connected screen.
    func visibleFrame(containing point: CGPoint) -> CGRect?
}

public protocol SnapPreviewing {
    /// Shows the snap preview overlay at the given frame (top-left coords).
    func show(at frame: CGRect)

    /// Hides the snap preview overlay.
    func hide()
}
```

- [ ] **Step 3.2: Note expected build breakage**

At this point, `swift build` will fail because:
- `Sources/Winch/Platform/WindowController.swift` still implements `position(of:)` not `frame(of:)`.
- `Sources/WinchDomain/DragController.swift` still calls `position(of:)`.
- `Tests/WinchDomainTests/Fakes.swift`'s `FakeWindowController` still implements the old protocol.

We will not commit until Task 4 and Task 5 restore green build. Do NOT commit this task standalone. Keep the changes in your working tree and proceed directly to Task 4.

---

### Task 4: WindowController migration (Platform)

**Files:**
- Modify: `Sources/Winch/Platform/WindowController.swift`

- [ ] **Step 4.1: Replace WindowController.swift**

Overwrite `Sources/Winch/Platform/WindowController.swift`:

```swift
import AppKit
import ApplicationServices
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
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let windowElement = focused as! AXUIElement

        // Reject windows we cannot move (system UI, fullscreen panels).
        var movable: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            windowElement,
            "AXMovable" as CFString,
            &movable
        ) == .success, let movableBool = movable as? Bool, !movableBool {
            return nil
        }

        return AXWindow(windowElement)
    }

    func frame(of window: WindowHandle) -> CGRect? {
        guard let window = window as? AXWindow else { return nil }
        guard let origin = readPoint(window.element, attribute: kAXPositionAttribute) else { return nil }
        guard let size = readSize(window.element, attribute: kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    func setPosition(of window: WindowHandle, to point: CGPoint) {
        guard let window = window as? AXWindow else { return }
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        _ = AXUIElementSetAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            value
        )
    }

    func setFrame(of window: WindowHandle, to frame: CGRect) {
        guard let window = window as? AXWindow else { return }
        var origin = frame.origin
        var size = frame.size
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            _ = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            _ = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    // MARK: - private helpers

    private func readPoint(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let v = value,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let axValue = v as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func readSize(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let v = value,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let axValue = v as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
```

- [ ] **Step 4.2: Build check (will still fail — DragController next)**

Run: `swift build` — expect failure with errors in `DragController.swift` referring to `position(of:)`. That's expected; Task 5 fixes it.

DO NOT commit yet. Keep moving to Task 5.

---

### Task 5: DragController extension (Domain, TDD)

**Files:**
- Modify: `Sources/WinchDomain/DragController.swift`
- Modify: `Tests/WinchDomainTests/Fakes.swift`
- Modify: `Tests/WinchDomainTests/DragControllerTests.swift`

- [ ] **Step 5.1: Update Fakes.swift to match new protocols**

Overwrite `Tests/WinchDomainTests/Fakes.swift`:

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
    var stubFrames: [ObjectIdentifier: CGRect] = [:]
    var setPositionCalls: [(WindowHandle, CGPoint)] = []
    var setFrameCalls: [(WindowHandle, CGRect)] = []

    func frontmostWindow() -> WindowHandle? {
        stubFrontmostWindow
    }

    func frame(of window: WindowHandle) -> CGRect? {
        stubFrames[ObjectIdentifier(window)]
    }

    func setPosition(of window: WindowHandle, to point: CGPoint) {
        setPositionCalls.append((window, point))
        // Mirror into stubFrames so subsequent frame(of:) reflects the move.
        if let existing = stubFrames[ObjectIdentifier(window)] {
            stubFrames[ObjectIdentifier(window)] = CGRect(origin: point, size: existing.size)
        }
    }

    func setFrame(of window: WindowHandle, to frame: CGRect) {
        setFrameCalls.append((window, frame))
        stubFrames[ObjectIdentifier(window)] = frame
    }
}

final class FakeCursorLocator: CursorLocating {
    var location: CGPoint = .zero
}

final class FakeScreenInfoProvider: ScreenInfoProviding {
    var stubVisibleFrame: CGRect? = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func visibleFrame(containing point: CGPoint) -> CGRect? {
        stubVisibleFrame
    }
}
```

- [ ] **Step 5.2: Update existing DragControllerTests to match new initializer and remove obsolete stubs**

Overwrite `Tests/WinchDomainTests/DragControllerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import WinchDomain

final class DragControllerTests: XCTestCase {

    private func makeController(
        config: HotkeyConfig = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate]),
        windows: FakeWindowController = FakeWindowController(),
        cursor: FakeCursorLocator = FakeCursorLocator(),
        screens: FakeScreenInfoProvider = FakeScreenInfoProvider()
    ) -> (DragController, FakeWindowController, FakeCursorLocator, FakeScreenInfoProvider) {
        let controller = DragController(
            hotkeyConfig: config,
            windowController: windows,
            cursorLocator: cursor,
            screenInfoProvider: screens
        )
        return (controller, windows, cursor, screens)
    }

    // MARK: existing behaviors (carried over)

    func testStartsIdle() {
        let (controller, _, _, _) = makeController()
        XCTAssertTrue(controller.isIdle)
    }

    func testEntersTrackingOnHotkeyMatch() {
        let (controller, windows, cursor, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 200, width: 500, height: 400)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertFalse(controller.isIdle)
    }

    func testStaysIdleWhenNoFrontmostWindow() {
        let (controller, windows, _, _) = makeController()
        windows.stubFrontmostWindow = nil

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testStaysIdleWhenWindowHasNoFrame() {
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        // No stubFrames entry → frame(of:) returns nil

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testMouseMovedUpdatesWindowPosition() {
        let (controller, windows, cursor, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 200, width: 500, height: 400)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 80, y: 70)
        controller.handleMouseMoved()

        XCTAssertEqual(windows.setPositionCalls.count, 1)
        XCTAssertEqual(windows.setPositionCalls[0].1, CGPoint(x: 130, y: 220))
    }

    func testMultipleMouseMovesAllRelativeToOriginNotCumulative() {
        // Regression guard: absolute offset from snapshot, not accumulated deltas.
        let (controller, windows, cursor, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 0, y: 0, width: 500, height: 400)
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
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 0, y: 0, width: 100, height: 100)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertFalse(controller.isIdle)
        controller.handleFlagsChanged([])
        XCTAssertTrue(controller.isIdle)
    }

    func testMouseMovedIgnoredWhenIdle() {
        let (controller, windows, _, _) = makeController()
        controller.handleMouseMoved()
        XCTAssertEqual(windows.setPositionCalls.count, 0)
    }

    func testPausedDoesNotEnterTracking() {
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = .zero
        controller.isPaused = true

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertTrue(controller.isIdle)
    }

    func testPausedDuringDragForcesIdle() {
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = .zero

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertFalse(controller.isIdle)

        controller.isPaused = true
        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertTrue(controller.isIdle)
    }

    func testHotkeyConfigCanBeReplacedAtRuntime() {
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = .zero

        controller.hotkeyConfig = HotkeyConfig(modifierFlags: [.maskCommand])
        controller.handleFlagsChanged([.maskCommand])

        XCTAssertFalse(controller.isIdle)
    }

    // MARK: new snap behaviors

    func testSnapZoneCallbackFiresOnEnteringLeftZone() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        var fired: [SnapTarget?] = []
        controller.onSnapZoneChanged = { fired.append($0) }

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        // Move cursor into left zone.
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()

        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first??.zone, .left)
        XCTAssertEqual(fired.first??.frame, CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    func testSnapZoneCallbackFiresWithNilOnLeavingZone() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        var fired: [SnapTarget?] = []
        controller.onSnapZoneChanged = { fired.append($0) }

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()
        cursor.location = CGPoint(x: 720, y: 450)
        controller.handleMouseMoved()

        XCTAssertEqual(fired.count, 2)
        XCTAssertEqual(fired[0]?.zone, .left)
        XCTAssertNil(fired[1])
    }

    func testSnapDoesNotFireWhenIsSnapEnabledIsFalse() {
        let (controller, windows, cursor, screens) = makeController()
        controller.isSnapEnabled = false
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        var fired: [SnapTarget?] = []
        controller.onSnapZoneChanged = { fired.append($0) }

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()

        XCTAssertEqual(fired.count, 0)
    }

    func testHotkeyReleaseCommitsSnapWhenInZone() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()
        controller.handleFlagsChanged([])  // release

        // setFrame called with left-half target
        XCTAssertEqual(windows.setFrameCalls.count, 1)
        XCTAssertEqual(windows.setFrameCalls[0].1, CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    func testHotkeyReleaseDoesNothingWhenNotInZone() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 720, y: 450)
        controller.handleMouseMoved()
        controller.handleFlagsChanged([])

        XCTAssertEqual(windows.setFrameCalls.count, 0)
    }

    func testSnappedWindowRestoresOnReDrag() {
        // Setup: window starts at (100, 100, 400x300), gets snapped left.
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        let originalFrame = CGRect(x: 100, y: 100, width: 400, height: 300)
        windows.stubFrames[ObjectIdentifier(window)] = originalFrame
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 200, y: 200)

        // First drag: cursor goes to left zone, modifier released → commit snap.
        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()
        controller.handleFlagsChanged([])

        // Window is now at left-half. setFrameCalls[0] = the snap.
        XCTAssertEqual(windows.setFrameCalls.count, 1)
        XCTAssertEqual(windows.setFrameCalls[0].1, CGRect(x: 0, y: 0, width: 720, height: 900))

        // Second drag: re-press modifier, move cursor enough to trigger restore.
        cursor.location = CGPoint(x: 200, y: 50)
        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        // First move below threshold — no restore yet.
        cursor.location = CGPoint(x: 202, y: 51)
        controller.handleMouseMoved()
        XCTAssertEqual(windows.setFrameCalls.count, 1, "restore should not trigger below threshold")
        // Now move above threshold (delta > 5).
        cursor.location = CGPoint(x: 220, y: 80)
        controller.handleMouseMoved()
        XCTAssertEqual(windows.setFrameCalls.count, 2, "restore should trigger above threshold")
        // The restored frame uses original size (400x300), centered on cursor.x, top 14pt above cursor.y.
        let restored = windows.setFrameCalls[1].1
        XCTAssertEqual(restored.size, originalFrame.size)
        XCTAssertEqual(restored.origin.x, 220 - 200, accuracy: 0.001)  // cursor.x - width/2
        XCTAssertEqual(restored.origin.y, 80 - 14, accuracy: 0.001)    // cursor.y - 14
    }

    func testIsSnapEnabledFalseSkipsCommit() {
        let (controller, windows, cursor, screens) = makeController()
        controller.isSnapEnabled = false
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 3, y: 450)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        controller.handleMouseMoved()
        controller.handleFlagsChanged([])

        XCTAssertEqual(windows.setFrameCalls.count, 0)
    }
}
```

- [ ] **Step 5.3: Run tests to verify they fail**

Run: `swift test --filter DragControllerTests`
Expected: FAIL — initializer signature mismatch ("missing argument for parameter 'screenInfoProvider'"), and new test methods reference symbols that don't exist on the type yet.

- [ ] **Step 5.4: Rewrite DragController.swift**

Overwrite `Sources/WinchDomain/DragController.swift`:

```swift
import Foundation
import CoreGraphics

public final class DragController {

    private enum State {
        case idle
        case tracking(
            window: WindowHandle,
            originCursor: CGPoint,
            originWindow: CGPoint,
            currentSnapZone: SnapZone?
        )
    }

    private var state: State = .idle

    public var hotkeyConfig: HotkeyConfig
    public var isPaused: Bool = false
    public var isSnapEnabled: Bool = true
    public var onSnapZoneChanged: ((SnapTarget?) -> Void)?

    private let windowController: WindowControlling
    private let cursorLocator: CursorLocating
    private let screenInfoProvider: ScreenInfoProviding

    private var preSnapFrames: [ObjectIdentifier: CGRect] = [:]

    private static let restoreThreshold: CGFloat = 5
    private static let restoreTitleBarOffset: CGFloat = 14

    public init(
        hotkeyConfig: HotkeyConfig,
        windowController: WindowControlling,
        cursorLocator: CursorLocating,
        screenInfoProvider: ScreenInfoProviding
    ) {
        self.hotkeyConfig = hotkeyConfig
        self.windowController = windowController
        self.cursorLocator = cursorLocator
        self.screenInfoProvider = screenInfoProvider
    }

    public var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    public func handleFlagsChanged(_ flags: CGEventFlags) {
        if isPaused {
            transitionToIdle()
            return
        }

        if hotkeyConfig.matches(flags) {
            if case .idle = state {
                tryEnterTracking()
            }
        } else {
            commitSnapIfNeededAndExit()
        }
    }

    public func handleMouseMoved() {
        if isPaused { return }
        guard case let .tracking(window, originCursor, originWindow, prevZone) = state else {
            return
        }

        let current = cursorLocator.location

        // Pre-snap restoration takes precedence: if this window has a stored
        // pre-snap frame AND the cursor has moved past the restore threshold,
        // restore the original size positioned around the cursor.
        let id = ObjectIdentifier(window)
        if let preSnapFrame = preSnapFrames[id] {
            let dx = current.x - originCursor.x
            let dy = current.y - originCursor.y
            if abs(dx) > Self.restoreThreshold || abs(dy) > Self.restoreThreshold {
                let newOrigin = CGPoint(
                    x: current.x - preSnapFrame.width / 2,
                    y: current.y - Self.restoreTitleBarOffset
                )
                let newFrame = CGRect(origin: newOrigin, size: preSnapFrame.size)
                windowController.setFrame(of: window, to: newFrame)
                preSnapFrames.removeValue(forKey: id)
                // Reset anchors so further deltas are measured from this restored state.
                state = .tracking(
                    window: window,
                    originCursor: current,
                    originWindow: newOrigin,
                    currentSnapZone: prevZone
                )
                updateSnapZoneIfChanged(cursor: current, prevZone: prevZone, window: window)
                return
            }
        }

        // Normal move (cheap setPosition).
        let newPos = CGPoint(
            x: originWindow.x + (current.x - originCursor.x),
            y: originWindow.y + (current.y - originCursor.y)
        )
        windowController.setPosition(of: window, to: newPos)

        updateSnapZoneIfChanged(cursor: current, prevZone: prevZone, window: window)
    }

    // MARK: - private

    private func tryEnterTracking() {
        guard let window = windowController.frontmostWindow() else { return }
        guard let frame = windowController.frame(of: window) else { return }
        state = .tracking(
            window: window,
            originCursor: cursorLocator.location,
            originWindow: frame.origin,
            currentSnapZone: nil
        )
    }

    private func transitionToIdle() {
        // If we were previewing a zone but are bailing out (e.g., paused),
        // notify so any UI overlay is hidden.
        if case .tracking(_, _, _, let zone) = state, zone != nil {
            onSnapZoneChanged?(nil)
        }
        state = .idle
    }

    private func commitSnapIfNeededAndExit() {
        if case let .tracking(window, _, _, snapZone) = state {
            if isSnapEnabled,
               let zone = snapZone,
               let visibleFrame = screenInfoProvider.visibleFrame(containing: cursorLocator.location) {
                if let currentFrame = windowController.frame(of: window) {
                    preSnapFrames[ObjectIdentifier(window)] = currentFrame
                }
                let target = SnapZoneCalculator.target(for: zone, in: visibleFrame)
                windowController.setFrame(of: window, to: target)
            }
            if snapZone != nil {
                onSnapZoneChanged?(nil)
            }
        }
        state = .idle
    }

    private func updateSnapZoneIfChanged(cursor: CGPoint, prevZone: SnapZone?, window: WindowHandle) {
        guard isSnapEnabled else { return }
        let newZone: SnapZone?
        let target: SnapTarget?
        if let visibleFrame = screenInfoProvider.visibleFrame(containing: cursor) {
            newZone = SnapZoneCalculator.zone(forCursor: cursor, in: visibleFrame)
            target = newZone.map { SnapTarget(zone: $0, frame: SnapZoneCalculator.target(for: $0, in: visibleFrame)) }
        } else {
            newZone = nil
            target = nil
        }
        if newZone != prevZone {
            if case let .tracking(w, oc, ow, _) = state {
                state = .tracking(window: w, originCursor: oc, originWindow: ow, currentSnapZone: newZone)
            }
            onSnapZoneChanged?(target)
        }
    }
}
```

- [ ] **Step 5.5: Run tests**

Run: `swift test`
Expected: All previously-passing tests still pass (7 HotkeyConfig + the old DragController tests, now re-keyed onto frame/setFrame), plus the new snap tests pass. Target count: 7 + 14 (SnapZoneCalculator) + however many DragController tests this file contains (count after edit; should be 16 with the new ones included).

If any test fails, debug — the most common pitfall is the cursor delta on restore being measured from the wrong origin (use the original `originCursor`, not a value updated mid-call).

- [ ] **Step 5.6: Commit the protocol migration + Domain extension together**

This is one large logical commit because protocols, WindowController, DragController, and fakes/tests are interlocked:

```bash
git add Sources/WinchDomain/Protocols.swift \
        Sources/Winch/Platform/WindowController.swift \
        Sources/WinchDomain/DragController.swift \
        Tests/WinchDomainTests/Fakes.swift \
        Tests/WinchDomainTests/DragControllerTests.swift
git -c commit.gpgsign=false commit -m "feat(domain): extend DragController with snap zones, preview callback, and pre-snap restore"
```

---

### Task 6: ScreenInfoProvider (Platform)

**Files:**
- Create: `Sources/Winch/Platform/ScreenInfoProvider.swift`

- [ ] **Step 6.1: Create ScreenInfoProvider**

`Sources/Winch/Platform/ScreenInfoProvider.swift`:

```swift
import AppKit
import WinchDomain

final class ScreenInfoProvider: ScreenInfoProviding {

    /// Returns the visible frame (excludes menu bar and Dock) of the screen
    /// containing the given point, converted to top-left origin to match the
    /// rest of the codebase. Returns nil if the point is not on any screen.
    func visibleFrame(containing point: CGPoint) -> CGRect? {
        // AppKit screen coordinates are bottom-left origin; the rest of the
        // codebase uses top-left origin (matching AXUIElement positions).
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryHeight = primary.frame.height
        let appKitPoint = NSPoint(x: point.x, y: primaryHeight - point.y)

        for screen in NSScreen.screens where screen.frame.contains(appKitPoint) {
            let visible = screen.visibleFrame
            // Convert visible frame back to top-left origin.
            let topLeft = CGRect(
                x: visible.origin.x,
                y: primaryHeight - visible.origin.y - visible.height,
                width: visible.width,
                height: visible.height
            )
            return topLeft
        }
        return nil
    }
}
```

- [ ] **Step 6.2: Verify build**

Run: `swift build`
Expected: PASS.

Run: `swift test`
Expected: same count as after Task 5, still all passing.

- [ ] **Step 6.3: Commit**

```bash
git add Sources/Winch/Platform/ScreenInfoProvider.swift
git -c commit.gpgsign=false commit -m "feat(platform): add ScreenInfoProvider with AppKit→top-left conversion"
```

---

### Task 7: SnapPreviewWindow (UI)

**Files:**
- Create: `Sources/Winch/UI/SnapPreviewWindow.swift`

- [ ] **Step 7.1: Create SnapPreviewWindow**

`Sources/Winch/UI/SnapPreviewWindow.swift`:

```swift
import AppKit
import WinchDomain

final class SnapPreviewWindow: SnapPreviewing {

    private let window: NSWindow
    private let contentView: SnapPreviewView

    init() {
        let initialRect = NSRect.zero
        window = NSWindow(
            contentRect: initialRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false
        contentView = SnapPreviewView()
        window.contentView = contentView
    }

    func show(at frame: CGRect) {
        let appKitFrame = SnapPreviewWindow.convertToAppKit(frame)
        window.setFrame(appKitFrame, display: true)
        window.orderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    private static func convertToAppKit(_ topLeftFrame: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first else { return topLeftFrame }
        let h = primary.frame.height
        return NSRect(
            x: topLeftFrame.origin.x,
            y: h - topLeftFrame.origin.y - topLeftFrame.height,
            width: topLeftFrame.width,
            height: topLeftFrame.height
        )
    }
}

final class SnapPreviewView: NSView {
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
```

- [ ] **Step 7.2: Verify build**

Run: `swift build`
Expected: PASS.

Run: `swift test`
Expected: same count, all passing.

- [ ] **Step 7.3: Commit**

```bash
git add Sources/Winch/UI/SnapPreviewWindow.swift
git -c commit.gpgsign=false commit -m "feat(ui): add SnapPreviewWindow translucent overlay"
```

---

### Task 8: SettingsStore — snap.enabled

**Files:**
- Modify: `Sources/Winch/Platform/SettingsStore.swift`

- [ ] **Step 8.1: Add snap.enabled key and accessor**

Open `Sources/Winch/Platform/SettingsStore.swift`. In the private `enum Key` block, add the snap key:

```swift
    private enum Key {
        static let hotkeyModifierFlags = "hotkey.modifierFlags"
        static let appPaused = "app.paused"
        static let launchAtLogin = "app.launchAtLogin"
        static let snapEnabled = "snap.enabled"
    }
```

Then add the new accessor after `launchAtLogin`:

```swift
    var isSnapEnabled: Bool {
        get {
            if defaults.object(forKey: Key.snapEnabled) == nil { return true }
            return defaults.bool(forKey: Key.snapEnabled)
        }
        set { defaults.set(newValue, forKey: Key.snapEnabled) }
    }
```

The "no key set → return true" branch makes snap enabled by default for existing users without writing anything to UserDefaults until they explicitly toggle.

- [ ] **Step 8.2: Verify build**

Run: `swift build`
Expected: PASS.

Run: `swift test`
Expected: same count, all passing.

- [ ] **Step 8.3: Commit**

```bash
git add Sources/Winch/Platform/SettingsStore.swift
git -c commit.gpgsign=false commit -m "feat(platform): add isSnapEnabled to SettingsStore (default true)"
```

---

### Task 9: PreferencesView — Edge Snap toggle

**Files:**
- Modify: `Sources/Winch/UI/PreferencesView.swift`

- [ ] **Step 9.1: Add snapEnabled to PreferencesModel**

In `Sources/Winch/UI/PreferencesView.swift`, locate `PreferencesModel`. Add a new `@Published` property and a callback:

```swift
    @Published var snapEnabled: Bool {
        didSet {
            guard oldValue != snapEnabled else { return }
            onSnapEnabledChange?(snapEnabled)
        }
    }
```

(Place it after the existing `launchAtLogin` property.)

Add a callback property after `onLaunchAtLoginChange`:

```swift
    var onSnapEnabledChange: ((Bool) -> Void)?
```

Update the `init` signature and body:

```swift
    init(
        initial: HotkeyConfig,
        launchAtLogin: Bool,
        snapEnabled: Bool,
        isAccessibilityTrusted: Bool
    ) {
        self.command = initial.modifierFlags.contains(.maskCommand)
        self.option  = initial.modifierFlags.contains(.maskAlternate)
        self.control = initial.modifierFlags.contains(.maskControl)
        self.shift   = initial.modifierFlags.contains(.maskShift)
        self.fn      = initial.modifierFlags.contains(.maskSecondaryFn)
        self.launchAtLogin = launchAtLogin
        self.snapEnabled = snapEnabled
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }
```

- [ ] **Step 9.2: Add Edge Snap section to the view body**

In `PreferencesView.body`, after the `Section("Startup")` block, add:

```swift
            Section("Edge Snap") {
                Toggle("Enable edge snap", isOn: $model.snapEnabled)
                Text("Drag a window to the top, left, or right edge of the screen to snap it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
```

- [ ] **Step 9.3: Verify build**

Run: `swift build`
Expected: FAIL — `AppDelegate.openPreferences()` still calls the old `PreferencesModel(initial:launchAtLogin:isAccessibilityTrusted:)` initializer. Task 10 fixes this. Do not commit yet; proceed.

---

### Task 10: AppDelegate wiring

**Files:**
- Modify: `Sources/Winch/AppDelegate.swift`

- [ ] **Step 10.1: Add new instance properties**

In `Sources/Winch/AppDelegate.swift`, add to the existing private property block (alongside `screenInfoProvider`-less version):

```swift
    private var screenInfo: ScreenInfoProvider!
    private var snapPreview: SnapPreviewWindow!
```

- [ ] **Step 10.2: Wire in applicationDidFinishLaunching**

Find the block where dependencies are constructed. Replace the `dragController` construction and surrounding lines:

```swift
        settings        = SettingsStore()
        windowController = WindowController()
        cursorLocator   = SystemCursorLocator()
        loginItem       = LoginItemManager()
        permissions     = PermissionManager()
        eventTap        = EventTap()
        menuBar         = MenuBarController()
        screenInfo      = ScreenInfoProvider()
        snapPreview     = SnapPreviewWindow()

        dragController = DragController(
            hotkeyConfig: settings.hotkeyConfig,
            windowController: windowController,
            cursorLocator: cursorLocator,
            screenInfoProvider: screenInfo
        )
        dragController.isPaused = settings.isPaused
        dragController.isSnapEnabled = settings.isSnapEnabled
        dragController.onSnapZoneChanged = { [weak self] target in
            guard let self else { return }
            if let t = target {
                self.snapPreview.show(at: t.frame)
            } else {
                self.snapPreview.hide()
            }
        }
```

- [ ] **Step 10.3: Update openPreferences to pass snapEnabled and wire callback**

Find `openPreferences()` and the `PreferencesModel(...)` initialization. Replace with:

```swift
            let model = PreferencesModel(
                initial: settings.hotkeyConfig,
                launchAtLogin: loginItem.isRegistered,
                snapEnabled: settings.isSnapEnabled,
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
            model.onSnapEnabledChange = { [weak self] enabled in
                guard let self else { return }
                self.settings.isSnapEnabled = enabled
                self.dragController.isSnapEnabled = enabled
            }
            model.onOpenSystemSettings = { [weak self] in
                self?.permissions.openSystemSettings()
            }
```

(The new block is `model.onSnapEnabledChange = ...` — added between the login-item block and the `onOpenSystemSettings` block.)

- [ ] **Step 10.4: Update the menu-bar Launch-at-login handler that touches PreferencesModel**

If your AppDelegate has a block like `self.preferencesModel?.launchAtLogin = self.loginItem.isRegistered`, no change is needed — the model already has `launchAtLogin`.

- [ ] **Step 10.5: Verify build and run tests**

Run: `swift build`
Expected: PASS.

Run: `swift test`
Expected: all tests still passing.

- [ ] **Step 10.6: Commit Task 9 + Task 10 together (interlocked PreferencesModel signature change)**

```bash
git add Sources/Winch/UI/PreferencesView.swift Sources/Winch/AppDelegate.swift
git -c commit.gpgsign=false commit -m "feat(ui): add Edge Snap preference and wire SnapPreviewWindow"
```

---

### Task 11: Update QA checklist

**Files:**
- Modify: `docs/superpowers/qa/manual-checklist.md`

- [ ] **Step 11.1: Append snap QA section**

Open `docs/superpowers/qa/manual-checklist.md`. After the existing "## 아이콘 표시" section, append:

```markdown
## 가장자리 스냅
- [ ] 이동 중 왼쪽 가장자리 진입 → 반투명 미리보기(왼쪽 절반)
- [ ] 이동 중 오른쪽 가장자리 진입 → 반투명 미리보기(오른쪽 절반)
- [ ] 이동 중 위 가장자리 진입 → 반투명 미리보기(풀스크린)
- [ ] 가장자리에서 벗어남 → 미리보기 사라짐
- [ ] 모디파이어 해제 (가장자리 안에서) → 창이 해당 영역으로 스냅
- [ ] 스냅된 창 다시 Ctrl+Option 드래그 → 원래 크기로 복원, 커서 따라옴
- [ ] 멀티 모니터: 보조 모니터 가장자리에서도 스냅 동작
- [ ] 환경설정 "Enable edge snap" OFF → 가장자리 닿아도 미리보기/스냅 없음
- [ ] OFF→ON 토글 시 즉시 반영 (앱 재시작 없이)
```

- [ ] **Step 11.2: Commit**

```bash
git add docs/superpowers/qa/manual-checklist.md
git -c commit.gpgsign=false commit -m "docs: add edge snap manual QA checks"
```

---

### Task 12: End-to-end smoke verification

Verification only, no commits.

- [ ] **Step 12.1: Full build**

Run: `make app`
Expected: bundle assembled at `.build/release/Winch.app`.

- [ ] **Step 12.2: Full test suite**

Run: `swift test`
Expected: all tests pass. Expected count: 7 (HotkeyConfig) + 14 (SnapZoneCalculator) + 18 (DragController: 11 carried over + 7 new snap) = **39**.

- [ ] **Step 12.3: Confirm no source regressions**

```bash
git status --short
```

Expected: clean.

```bash
git log --oneline | head -12
```

Expected: the commits below in order (newest first):
- "docs: add edge snap manual QA checks"
- "feat(ui): add Edge Snap preference and wire SnapPreviewWindow"
- "feat(platform): add isSnapEnabled to SettingsStore (default true)"
- "feat(ui): add SnapPreviewWindow translucent overlay"
- "feat(platform): add ScreenInfoProvider with AppKit→top-left conversion"
- "feat(domain): extend DragController with snap zones, preview callback, and pre-snap restore"
- "feat(domain): add SnapZoneCalculator with zone and target functions"
- "feat(domain): add SnapZone and SnapTarget types"

(Followed by the design-spec commit and earlier history.)

- [ ] **Step 12.4: Hand off to user for manual QA**

Do NOT launch the app from inside the implementer subagent. The user will install the new `.app` bundle and step through the QA checklist (`docs/superpowers/qa/manual-checklist.md`) themselves.

---

## Out of scope (per spec)

- 4-zone or 7-zone snap (corners as quarter-screen targets)
- Bottom edge snap
- Resize gesture (separate modifier)
- Snap animation
- User-configurable hot zone threshold
- Per-monitor independent snap enable/disable
- Snap sound / haptic feedback
- Persistent pre-snap frames across app restart
