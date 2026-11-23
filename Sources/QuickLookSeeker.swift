import AppKit
import ApplicationServices
import os

let log = Logger(subsystem: "com.quicklookseek.QuickLookSeek", category: "seek")

/// Finds the video timeline in an open Quick Look panel and moves it.
///
/// Quick Look's panel appears in its host app's accessibility tree as a window
/// with subrole "Quick Look". When it's previewing audio/video it contains an
/// AXSlider described as "timeline" whose value is the playback position in
/// seconds; writing that value seeks.
final class QuickLookSeeker {
    // While a key is held down the slider's reported value can lag behind the
    // value we just wrote, so keep stepping from our last target for a moment.
    private var lastSlider: AXUIElement?
    private var lastTarget: Double = 0
    private var lastAt: TimeInterval = 0

    /// Returns true if a Quick Look timeline was found and moved.
    func seek(by delta: Double) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // We're called from inside the keyboard event tap; never block it for long.
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        guard let window = quickLookWindow(in: axApp) else {
            log.debug("no Quick Look window in \(app.bundleIdentifier ?? "?", privacy: .public)")
            return false
        }
        guard let slider = timeline(in: window, depth: 0) else {
            log.debug("Quick Look window has no timeline")
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime
        let base: Double
        if let last = lastSlider, CFEqual(last, slider), now - lastAt < 0.4 {
            base = lastTarget
        } else if let current: Double = attribute(slider, kAXValueAttribute) {
            base = current
        } else {
            return false
        }

        let lo: Double = attribute(slider, kAXMinValueAttribute) ?? 0
        let hi: Double = attribute(slider, kAXMaxValueAttribute) ?? .greatestFiniteMagnitude
        let target = min(hi, max(lo, base + delta))

        let result = AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: target))
        log.debug("seek \(base, privacy: .public) -> \(target, privacy: .public), AXError \(result.rawValue, privacy: .public)")
        lastSlider = slider
        lastTarget = target
        lastAt = now
        return true
    }

    private func quickLookWindow(in app: AXUIElement) -> AXUIElement? {
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        return windows.first { (attribute($0, kAXSubroleAttribute) as String?) == "Quick Look" }
    }

    private func timeline(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 6 { return nil }
        if (attribute(element, kAXRoleAttribute) as String?) == kAXSliderRole,
           (attribute(element, kAXDescriptionAttribute) as String?) == "timeline" {
            return element
        }
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
        for child in children {
            if let found = timeline(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
