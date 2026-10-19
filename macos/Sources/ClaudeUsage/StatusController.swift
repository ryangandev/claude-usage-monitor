import AppKit
import SwiftUI

/// The menu bar item: a ring and the weekly percentage, with the popover opening on hover.
///
/// Hovering 150 ms opens the popover and leaving both it and the item for 300 ms closes it.
/// A click pins it open until the next click or a click elsewhere.
@MainActor
final class StatusController: NSResponder, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let monitor: Monitor
    private let actions: AppActions
    private var pinned = false
    private var overButton = false
    private var overPopover = false
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?

    init(monitor: Monitor, actions: AppActions) {
        self.monitor = monitor
        self.actions = actions
        super.init()
        let button = item.button!
        button.target = self
        button.action = #selector(click(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeft
        button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                              owner: self, userInfo: ["zone": "button"]))
        let host = NSHostingController(rootView: PopoverView(monitor: monitor, openDashboard: { [weak self] in
            self?.close()
            actions.openDashboard()
        }, showMenu: { [weak self] view in
            guard let self else { return }
            self.menu().popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
        }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.animates = true
        popover.delegate = self
        host.view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                 owner: self, userInfo: ["zone": "popover"]))
        render()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Writes the item and the open popover to PNGs in `dir`, for checking them without a mouse.
    func snapshot(to dir: String) {
        func write(_ v: NSView, _ name: String) {
            guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name))
        }
        if let b = item.button { write(b, "item.png") }
        if let v = popover.contentViewController?.view.window?.contentView?.superview ?? popover.contentViewController?.view { write(v, "popover.png") }
    }

    // MARK: The item

    func render() {
        guard let button = item.button else { return }
        let u = monitor.usage
        let status = u?.status ?? .normal
        let ringColor: NSColor = switch (monitor.link, status) {
        case (.unreachable, _), (.starting, _): .tertiaryLabelColor
        case (_, .normal): .labelColor
        case (_, .early): Self.warn
        case (_, .almostFull), (_, .full): Self.danger
        }
        button.image = Self.ring(fraction: (u?.weekly ?? 0) / 100, color: ringColor)

        let title = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        func add(_ s: String, _ color: NSColor? = nil) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 0.5]
            if let color { attrs[.foregroundColor] = color }
            title.append(NSAttributedString(string: s, attributes: attrs))
        }
        if !Settings.shared.iconOnly {
            if monitor.link != .live || u == nil {
                add(" --", .secondaryLabelColor)
            } else if let u {
                switch status {
                case .full: add(" " + Fmt.dayTime(u.weekEnd), Self.danger)
                case .almostFull: add(" " + Fmt.pct(u.weekly), Self.danger)
                case .early:
                    add(" " + Fmt.pct(u.weekly))
                    if let at = u.runsOutAt { add(" · " + L("\(Fmt.weekday(at))满", "full \(Fmt.weekday(at))"), Self.warn) }
                case .normal: add(" " + Fmt.pct(u.weekly))
                }
                if u.fiveHourMatters && status != .full {
                    add(" · 5h " + Fmt.pct(u.fiveHour), u.fiveHour >= 90 ? Self.danger : nil)
                }
            }
        }
        button.attributedTitle = title
        button.setAccessibilityLabel(accessibilityText(u))
    }

    private func accessibilityText(_ u: Usage?) -> String {
        guard let u else { return L("Claude 用量，服务没响应", "Claude usage, not responding") }
        var s = L("本周额度 \(Fmt.pct(u.weekly))", "Weekly quota \(Fmt.pct(u.weekly))")
        if let at = u.runsOutAt { s += L("，按现在的速度\(Fmt.dayTime(at))用满", ", full by \(Fmt.dayTime(at)) at this pace") }
        return s
    }

    static let warn = NSColor(name: nil) { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: 0xF59E4B) : NSColor(hex: 0xC2610C)
    }
    static let danger = NSColor(name: nil) { a in
        a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: 0xFF6B6B) : NSColor(hex: 0xC62F2F)
    }

    /// A 14 pt ring filled clockwise from the top. It draws when shown, so label colors follow the menu bar.
    static func ring(fraction: Double, color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 15, height: 15), flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY), r: CGFloat = 5.5
            let track = NSBezierPath()
            track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.labelColor.withAlphaComponent(0.28).setStroke()
            track.stroke()
            let f = min(1, max(0, fraction))
            if f > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }
            return true
        }
        return img
    }

    // MARK: Hover and click

    override func mouseEntered(with event: NSEvent) {
        if zone(event) == "button" { overButton = true } else { overPopover = true }
        closeWork?.cancel()
        guard !popover.isShown else { return }
        let work = DispatchWorkItem { [weak self] in self?.show() }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        if zone(event) == "button" { overButton = false } else { overPopover = false }
        openWork?.cancel()
        guard popover.isShown, !pinned else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.overButton, !self.overPopover, !self.pinned else { return }
            self.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func zone(_ e: NSEvent) -> String? { e.trackingArea?.userInfo?["zone"] as? String }

    @objc private func click(_ sender: NSStatusBarButton) {
        openWork?.cancel()
        if NSApp.currentEvent?.type == .rightMouseUp {
            close()
            item.menu = menu()
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        if popover.isShown && pinned {
            close()
        } else {
            pinned = true
            popover.behavior = .transient
            if !popover.isShown { show() }
            NSApp.activate()
        }
    }

    func show() {
        guard let button = item.button else { return }
        popover.behavior = pinned ? .transient : .applicationDefined
        monitor.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func close() {
        pinned = false
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        pinned = false
        overPopover = false
    }

    // MARK: The menu

    func menu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: L("查看详情", "View details"), action: #selector(AppActions.openDashboardAction), keyEquivalent: "").target = actions
        m.addItem(withTitle: L("录入官方读数…", "Enter official reading…"), action: #selector(AppActions.enterReading), keyEquivalent: "").target = actions
        m.addItem(.separator())
        let icon = m.addItem(withTitle: L("只显示图标", "Icon only"), action: #selector(AppActions.toggleIconOnly), keyEquivalent: "")
        icon.target = actions
        icon.state = Settings.shared.iconOnly ? .on : .off
        let login = m.addItem(withTitle: L("开机启动", "Open at login"), action: #selector(AppActions.toggleLogin), keyEquivalent: "")
        login.target = actions
        login.state = LoginItem.enabled ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: L("退出 Claude 用量", "Quit Claude Usage"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }
}
