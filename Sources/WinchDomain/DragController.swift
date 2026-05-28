import Foundation
import CoreGraphics

public final class DragController {

    private enum State {
        case idle
        case tracking(
            window: WindowHandle,
            originCursor: CGPoint,
            originWindow: CGPoint,
            currentSnapZone: SnapZone?,
            snapVisibleFrame: CGRect?
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
        guard case let .tracking(window, originCursor, originWindow, prevZone, prevFrame) = state else {
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
                state = .tracking(
                    window: window,
                    originCursor: current,
                    originWindow: newOrigin,
                    currentSnapZone: prevZone,
                    snapVisibleFrame: prevFrame
                )
                updateSnapZoneIfChanged(cursor: current, prevZone: prevZone, prevFrame: prevFrame, window: window)
                return
            }
        }

        let newPos = CGPoint(
            x: originWindow.x + (current.x - originCursor.x),
            y: originWindow.y + (current.y - originCursor.y)
        )
        windowController.setPosition(of: window, to: newPos)

        updateSnapZoneIfChanged(cursor: current, prevZone: prevZone, prevFrame: prevFrame, window: window)
    }

    // MARK: - private

    private func tryEnterTracking() {
        guard let window = windowController.frontmostWindow() else { return }
        guard let frame = windowController.frame(of: window) else { return }
        state = .tracking(
            window: window,
            originCursor: cursorLocator.location,
            originWindow: frame.origin,
            currentSnapZone: nil,
            snapVisibleFrame: nil
        )
    }

    private func transitionToIdle() {
        if case .tracking(_, _, _, let zone, _) = state, zone != nil {
            onSnapZoneChanged?(nil)
        }
        state = .idle
    }

    private func commitSnapIfNeededAndExit() {
        if case let .tracking(window, _, _, snapZone, snapVisibleFrame) = state {
            if isSnapEnabled,
               let zone = snapZone,
               let visibleFrame = snapVisibleFrame {
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

    private func updateSnapZoneIfChanged(cursor: CGPoint, prevZone: SnapZone?, prevFrame: CGRect?, window: WindowHandle) {
        guard isSnapEnabled else { return }
        let visibleFrame = screenInfoProvider.visibleFrame(containing: cursor)
        let newZone: SnapZone?
        if let vf = visibleFrame {
            newZone = SnapZoneCalculator.zone(forCursor: cursor, in: vf)
        } else {
            newZone = nil
        }
        // Fire if zone OR frame changed.
        let frameChanged = visibleFrame != prevFrame
        let zoneChanged = newZone != prevZone
        if !zoneChanged && !frameChanged { return }

        let target: SnapTarget?
        if let z = newZone, let vf = visibleFrame {
            target = SnapTarget(zone: z, frame: SnapZoneCalculator.target(for: z, in: vf))
        } else {
            target = nil
        }

        if case let .tracking(w, oc, ow, _, _) = state {
            state = .tracking(window: w, originCursor: oc, originWindow: ow,
                              currentSnapZone: newZone, snapVisibleFrame: visibleFrame)
        }
        onSnapZoneChanged?(target)
    }
}
