import CoreGraphics
import Foundation

/// A keyboard event tap that hands left/right arrow presses to a handler,
/// which decides whether to swallow them.
final class ArrowKeyTap {
    enum Direction { case left, right }

    /// Return true to swallow the key press, false to let it through.
    typealias Handler = (_ direction: Direction, _ shift: Bool) -> Bool

    private let handler: Handler
    private var port: CFMachPort?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Fails (returns false) until the app has Accessibility permission.
    @discardableResult
    func start() -> Bool {
        if port != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let tap = Unmanaged<ArrowKeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS turns a tap off if a callback is ever too slow; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let direction: Direction
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 123: direction = .left
        case 124: direction = .right
        default: return Unmanaged.passUnretained(event)
        }

        // Leave ⌘/⌥/⌃ combinations alone.
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) {
            return Unmanaged.passUnretained(event)
        }

        return handler(direction, flags.contains(.maskShift)) ? nil : Unmanaged.passUnretained(event)
    }
}
