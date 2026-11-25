import AppKit
import ApplicationServices
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SPUStandardUserDriverDelegate {
    private let defaults = UserDefaults.standard
    private let seeker = QuickLookSeeker()
    private lazy var updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)

    // We're a menu bar app with no Dock icon, so let Sparkle remind about
    // updates gently instead of popping a window over whatever you're doing.
    var supportsGentleScheduledUpdateReminders: Bool { true }
    private var tap: ArrowKeyTap!
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    private static let stepChoices: [Double] = [5, 10, 15, 30]
    private static let bigStepChoices: [Double] = [15, 30, 60, 120]

    private var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }
    private var step: Double {
        get { defaults.object(forKey: "step") as? Double ?? 5 }
        set { defaults.set(newValue, forKey: "step") }
    }
    private var bigStep: Double {
        get { defaults.object(forKey: "bigStep") as? Double ?? 30 }
        set { defaults.set(newValue, forKey: "bigStep") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = updater
        tap = ArrowKeyTap { [unowned self] direction, shift in
            guard enabled else { return false }
            let amount = shift ? bigStep : step
            return seeker.seek(by: direction == .left ? -amount : amount)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "goforward", accessibilityDescription: "QuickLook Seek")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !tap.start() {
            // Ask once; then keep checking until the user flips the switch.
            requestAccessibility()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                guard let self, self.tap.start() else { return }
                timer.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "QuickLook Seek", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if !tap.isRunning {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        let toggle = item("Seek with ← / →", #selector(toggleEnabled))
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(stepMenu("Step", choices: Self.stepChoices, current: step, action: #selector(setStep)))
        menu.addItem(stepMenu("Shift Step", choices: Self.bigStepChoices, current: bigStep, action: #selector(setBigStep)))
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("About QuickLook Seek", #selector(showAbout)))
        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                 keyEquivalent: "")
        updates.target = updater
        menu.addItem(updates)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func stepMenu(_ title: String, choices: [Double], current: Double, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(title): \(Int(current))s", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for seconds in choices {
            let choice = item("\(Int(seconds)) seconds", action)
            choice.representedObject = seconds
            choice.state = seconds == current ? .on : .off
            submenu.addItem(choice)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func toggleEnabled() { enabled.toggle() }

    @objc private func setStep(_ sender: NSMenuItem) {
        if let seconds = sender.representedObject as? Double { step = seconds }
    }

    @objc private func setBigStep(_ sender: NSMenuItem) {
        if let seconds = sender.representedObject as? Double { bigStep = seconds }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            alert.runModal()
        }
    }

    // MARK: - About

    // Set in Info.plist, so a fork changes them in one place.
    private static func infoURL(_ key: String) -> URL? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap(URL.init(string:))
    }

    @objc private func showAbout() {
        // Name, icon, version and copyright come from Info.plist; we add the
        // blurb and links. An accessory app has to activate itself, or the
        // panel opens behind whatever app is in front.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: aboutCredits()])
    }

    private func aboutCredits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: "Seek Quick Look videos with the arrow keys.", attributes: base)
        let links = [("Website", "QLSWebsiteURL"), ("Source code", "QLSSourceURL")]
            .compactMap { title, key in Self.infoURL(key).map { (title, $0) } }
        for (index, (title, url)) in links.enumerated() {
            credits.append(NSAttributedString(string: index == 0 ? "\n" : "  ·  ", attributes: base))
            credits.append(NSAttributedString(string: title, attributes: base.merging([.link: url]) { $1 }))
        }
        return credits
    }

    // MARK: - Accessibility

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// Diagnostic mode: `--probe [--seek <seconds>]` prints what the app sees in any
// open Quick Look window, then exits. Launch it through LaunchServices so the
// app's own Accessibility permission applies (not the terminal's):
//   open -n -W --stdout /dev/stdout "/Applications/QuickLook Seek.app" --args --probe
let arguments = CommandLine.arguments
if arguments.contains("--probe") {
    guard AXIsProcessTrusted() else {
        print("QuickLook Seek doesn't have Accessibility permission.")
        exit(1)
    }
    var delta: Double?
    if let index = arguments.firstIndex(of: "--seek"), index + 1 < arguments.count {
        delta = Double(arguments[index + 1])
    }
    let seeker = QuickLookSeeker()
    seeker.matchNames = !arguments.contains("--ignore-names")
    print(seeker.probe(seekBy: delta), terminator: "")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
