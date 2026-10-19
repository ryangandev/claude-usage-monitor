import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu bar only; the Dock icon shows while the window is open
        app.run()
    }

    let monitor = Monitor()
    private var actions: AppActions!
    private var status: StatusController!
    private let alerts = Alerts()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.shared.applyAppearance()
        actions = AppActions(monitor: monitor)
        status = StatusController(monitor: monitor, actions: actions)
        monitor.onUpdate = { [weak self] s in
            self?.status.render()
            self?.alerts.check(Usage(s: s))
        }
        LoginItem.enableOnFirstLaunch()
        alerts.requestPermission()
        monitor.start()
        observeSettings()
        if CommandLine.arguments.contains("--open-dashboard") { actions.openDashboard() }
        // For checking the popover without a mouse: opens it pinned once the first state arrives.
        if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.status.show() }
            if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
                let dir = CommandLine.arguments[i + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.status.snapshot(to: dir) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { monitor.stop() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        actions.openDashboard()
        return false
    }

    /// Redraw the menu bar item when a setting it shows changes.
    private func observeSettings() {
        withObservationTracking {
            _ = Settings.shared.iconOnly
            _ = Settings.shared.isChinese
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.status.render()
                self?.observeSettings()
            }
        }
    }
}

/// What the menu and the popover can ask the app to do.
@MainActor
final class AppActions: NSObject, NSWindowDelegate {
    private let monitor: Monitor
    private var window: NSWindow?

    init(monitor: Monitor) { self.monitor = monitor }

    func openDashboard() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = L("Claude 用量", "Claude Usage")
            w.contentMinSize = NSSize(width: 960, height: 640)
            w.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: DashboardView(monitor: monitor, actions: self))
            host.sizingOptions = []  // the window keeps its size; the tabs fit themselves to it
            w.contentViewController = host
            w.setFrameAutosaveName("Dashboard")
            if !w.setFrameUsingName("Dashboard") { w.center() }
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func openDashboardAction() { openDashboard() }

    @objc func toggleIconOnly() { Settings.shared.iconOnly.toggle() }

    @objc func toggleLogin() { LoginItem.set(!LoginItem.enabled) }

    /// Asks for the weekly percentage shown on claude.ai, which calibrates every estimate after it.
    @objc func enterReading() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("录入官方读数", "Enter official reading")
        alert.informativeText = L("打开 claude.ai 的 设置 › 用量，把“每周”那一栏的百分比填在这里。之后的估算会从这个读数算起。",
                                  "Open Settings › Usage on claude.ai and enter the weekly percentage shown there. Estimates count on from this reading.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "26"
        alert.accessoryView = field
        alert.addButton(withTitle: L("保存", "Save"))
        alert.addButton(withTitle: L("取消", "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let pct = Double(text), (0...100).contains(pct) else {
            let bad = NSAlert()
            bad.messageText = L("要填 0 到 100 之间的数字", "Enter a number from 0 to 100")
            bad.runModal()
            return
        }
        Task {
            if await !monitor.addReading(pct) {
                let failed = NSAlert()
                failed.messageText = L("没存上，服务没有响应", "Not saved; the service is not responding")
                failed.runModal()
            }
        }
    }
}

/// Starting at login, through the system's login items.
@MainActor
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("login item: \(error.localizedDescription)")
        }
    }

    /// The app is meant to be always there, so it turns this on once; turning it off later sticks.
    static func enableOnFirstLaunch() {
        let key = "loginItemOffered"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }
}

/// One notification a week when the forecast first lands before the reset, and one each at 80% and 95%.
@MainActor
final class Alerts {
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(_ u: Usage) {
        let week = u.weekStart
        if let at = u.runsOutAt, u.weekly < 80 {
            send("early", week: week, title: L("这周的额度会提前用满", "This week's quota will run out early"),
                 body: L("按现在的速度 \(Fmt.dayTime(at)) 用满，比 \(Fmt.dayTime(u.weekEnd)) 重置早。",
                         "At this pace it is full by \(Fmt.dayTime(at)), before the \(Fmt.dayTime(u.weekEnd)) reset."))
        }
        for level in [80.0, 95.0] where u.weekly >= level {
            send("\(Int(level))", week: week, title: L("本周额度已用 \(Fmt.pct(u.weekly))", "Weekly quota at \(Fmt.pct(u.weekly))"),
                 body: L("\(Fmt.dayTime(u.weekEnd)) 重置。", "Resets \(Fmt.dayTime(u.weekEnd))."))
        }
    }

    private func send(_ key: String, week: Date, title: String, body: String) {
        guard !Settings.shared.alertSent(key, week: week) else { return }
        Settings.shared.markAlertSent(key, week: week)
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(key)-\(week.timeIntervalSince1970)", content: c, trigger: nil))
    }
}
