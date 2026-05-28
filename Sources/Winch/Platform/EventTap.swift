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
