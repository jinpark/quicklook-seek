import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let seeker = QuickLookSeeker()
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
