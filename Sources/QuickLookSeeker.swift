import AppKit
import ApplicationServices
import os

let log = Logger(subsystem: "net.jinpark.quicklookseek", category: "seek")

/// Finds the video timeline in an open Quick Look panel and moves it.
///
/// Quick Look's panel appears in its host app's accessibility tree as its own
/// window. When it's previewing audio/video it contains a timeline AXSlider
/// whose value is the playback position in seconds; writing that value seeks.
final class QuickLookSeeker {
    /// Match the English "Quick Look" subrole and "timeline" description.
    /// Turned off by `--probe --ignore-names` to exercise the
    /// language-independent fallbacks against a real panel.
    var matchNames = true

    /// Diagnostic for `--probe`: describes every open Quick Look window, which
    /// slider would be used as the timeline, and (if `seekBy` is set) the
    /// result of seeking it.
    func probe(seekBy delta: Double?) -> String {
        var out = ""
        for app in NSWorkspace.shared.runningApplications {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            guard let window = quickLookWindow(in: axApp) else { continue }
            out += "== \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"), pid \(app.processIdentifier))\n"
            dump(window, depth: 1, into: &out)
            guard let slider = timeline(in: window) else {
                out += "-> no timeline slider found\n"
                continue
            }
            let before: Double = attribute(slider, kAXValueAttribute) ?? .nan
            let desc: String = attribute(slider, kAXDescriptionAttribute) ?? ""
            let max: Double = attribute(slider, kAXMaxValueAttribute) ?? .nan
            out += "-> timeline: description=\"\(desc)\" value=\(before) max=\(max)\n"
            if let delta {
                let result = AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString,
                                                          NSNumber(value: before + delta))
                Thread.sleep(forTimeInterval: 0.3)
                let after: Double = attribute(slider, kAXValueAttribute) ?? .nan
                out += "-> seek by \(delta): AXError \(result.rawValue), value \(before) -> \(after)\n"
            }
        }
        return out.isEmpty ? "no Quick Look window found\n" : out
    }

    private func dump(_ element: AXUIElement, depth: Int, into out: inout String) {
        if depth > 8 { return }
        var parts: [String] = []
        for name in [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                     kAXIdentifierAttribute, kAXMaxValueAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
                  let value else { continue }
            let text = "\(value)"
            if !text.isEmpty { parts.append("\(name.dropFirst(2))=\(text.prefix(60))") }
        }
        out += String(repeating: "  ", count: depth) + parts.joined(separator: " ") + "\n"
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
        for child in children { dump(child, depth: depth + 1, into: &out) }
    }

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
        guard let slider = timeline(in: window) else {
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

    /// The Quick Look panel: subrole "Quick Look", or (in case that string is
    /// ever localized) a window whose controls carry Quick Look's own
    /// identifiers, e.g. "QLControlOpen" / "QLAXMusicPreview". Identifiers are
    /// never localized.
    private func quickLookWindow(in app: AXUIElement) -> AXUIElement? {
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        return windows.first { window in
            if matchNames, (attribute(window, kAXSubroleAttribute) as String?) == "Quick Look" { return true }
            let children: [AXUIElement] = attribute(window, kAXChildrenAttribute) ?? []
            return children.contains { (attribute($0, kAXIdentifierAttribute) as String?)?.hasPrefix("QL") == true }
        }
    }

    /// The playback slider. Its accessibility description is "timeline" in
    /// English but localized elsewhere, so fall back to the slider with the
    /// largest range: the timeline's maximum is the duration in seconds,
    /// while the volume slider's is 1.
    private func timeline(in window: AXUIElement) -> AXUIElement? {
        var sliders: [AXUIElement] = []
        collectSliders(in: window, depth: 0, into: &sliders)
        if matchNames, let named = sliders.first(where: { (attribute($0, kAXDescriptionAttribute) as String?) == "timeline" }) {
            return named
        }
        let ranged = sliders.compactMap { slider -> (AXUIElement, Double)? in
            guard let max: Double = attribute(slider, kAXMaxValueAttribute), max > 1 else { return nil }
            return (slider, max)
        }
        return ranged.max { $0.1 < $1.1 }?.0
    }

    private func collectSliders(in element: AXUIElement, depth: Int, into sliders: inout [AXUIElement]) {
        if depth > 6 { return }
        if (attribute(element, kAXRoleAttribute) as String?) == kAXSliderRole {
            sliders.append(element)
            return
        }
        let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
        for child in children { collectSliders(in: child, depth: depth + 1, into: &sliders) }
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
