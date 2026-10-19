import SwiftUI

/// The small dashboard that opens from the menu bar.
struct PopoverView: View {
    var monitor: Monitor
    var openDashboard: () -> Void
    var showMenu: (NSView) -> Void
    @State private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            if let u = monitor.usage {
                quota(u)
                Divider().overlay(Theme.line)
                fiveHour(u)
                if !u.running.isEmpty {
                    Divider().overlay(Theme.line)
                    running(u)
                }
                Divider().overlay(Theme.line)
                daily(u)
            } else {
                placeholder
            }
            Divider().overlay(Theme.line)
            footer
        }
        .frame(width: 360)
        .foregroundStyle(Theme.text)
        .id(settings.isChinese)  // redraw every string when the language changes
    }

    private func quota(_ u: Usage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("本周额度", "Weekly quota")).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.sub)
                Spacer()
                if let tier = tierName { Text(tier).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.sub)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.chip, in: RoundedRectangle(cornerRadius: 4)) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.pct(u.weekly)).font(.system(size: 34, weight: .semibold)).mono().kerning(-0.6)
                Text(L("已用，估算", "used, estimated")).sub()
                Spacer()
                u.status.badge
            }
            Meter(value: u.weekly / 100, color: u.status.color, height: 6, tick: u.elapsed)
                .padding(.vertical, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline(u)).font(.system(size: 13, weight: .medium))
                Text(detail(u)).sub().mono()
            }
            HStack(spacing: 6) {
                InfoIcon()
                Text(provenance(u))
            }
            .sub(11)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private func fiveHour(_ u: Usage) -> some View {
        HStack(spacing: 12) {
            Text(L("5 小时窗口", "5-hour window")).sub().lineLimit(1).fixedSize().frame(width: 92, alignment: .leading)
            Meter(value: u.fiveHour / 100, color: u.fiveHourMatters ? Theme.warn : Theme.text.opacity(0.7), height: 4)
            Text(Fmt.pct(u.fiveHour)).font(.system(size: 12, weight: .semibold)).mono().frame(width: 34, alignment: .trailing)
            if let end = u.s.fiveHour.end {
                Text(L("\(Fmt.time(end)) 重置", "resets \(Fmt.time(end))")).sub(11).mono().lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func running(_ u: Usage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("\(u.running.count) 个运行中", "\(u.running.count) running")).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(L("时长 · 已用", "time · used"))
            }
            .sub(11)
            .padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(u.running.prefix(5)) { a in
                HStack(spacing: 8) {
                    Dot()
                    Text(a.description).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(Fmt.duration(a.last.timeIntervalSince(a.first))).sub(11).mono()
                    Text(Fmt.pct(u.pct(a.cost), digits: 1)).font(.system(size: 12, weight: .medium)).mono().frame(width: 42, alignment: .trailing)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8).padding(.vertical, 5)
            }
            if u.running.count > 5 {
                Text(L("还有 \(u.running.count - 5) 个", "\(u.running.count - 5) more")).sub(11).padding(.horizontal, 8).padding(.top, 2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
    }

    private func daily(_ u: Usage) -> some View {
        let days = u.dailyPct
        let top = max(days.map { $0.opus + $0.other }.max() ?? 1, 1)
        return HStack(spacing: 12) {
            Text(L("每天用量", "Daily use")).sub().lineLimit(1).fixedSize().frame(width: 92, alignment: .leading)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    let v = d.opus + d.other
                    RoundedRectangle(cornerRadius: 2)
                        .fill(d.state == "current" ? Theme.accent : (v == 0 ? Theme.track : Theme.idle))
                        .frame(height: v == 0 ? 2 : max(3, 22 * v / top))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 22, alignment: .bottom)
            if let today = days.first(where: { $0.state == "current" }) {
                Text(L("今天 ", "today ") + Fmt.pct(today.opus + today.other, digits: 1)).sub(11).mono()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Dot(color: monitor.link == .live ? Theme.live : Theme.idle)
                Text(liveText).mono()
            }
            .sub(11)
            Spacer()
            MenuAnchor(showMenu: showMenu)
                .frame(width: 28, height: 28)
            Button(action: openDashboard) {
                HStack(spacing: 6) {
                    Text(L("查看详情", "View details"))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(Pressable())
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(monitor.link == .starting ? L("正在读取用量…", "Reading usage…") : L("服务没有响应", "The service is not responding"))
                .font(.system(size: 13, weight: .medium))
            if let p = monitor.problem { Text(p).sub() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var liveText: String {
        switch monitor.link {
        case .live: return L("实时 · ", "Live · ") + Fmt.clock(monitor.lastUpdate ?? Date())
        case .starting: return L("正在启动", "Starting")
        case .unreachable: return L("服务没响应", "Not responding")
        }
    }

    private var tierName: String? {
        guard let t = monitor.state?.tier else { return nil }
        if t.contains("max_20x") { return "Max 20x" }
        if t.contains("max_5x") { return "Max 5x" }
        return nil
    }

    private func headline(_ u: Usage) -> String {
        if u.status == .full, let end = u.s.weekly.end { return L("已用满，\(Fmt.dayTime(end)) 重置", "Full until the \(Fmt.dayTime(end)) reset") }
        if let at = u.runsOutAt { return L("按现在的速度 \(Fmt.dayTime(at)) 用满", "At this pace, full by \(Fmt.dayTime(at))") }
        if let f = u.forecastAtReset { return L("按本周平均，重置时约 \(Fmt.pct(f))", "At the week's average, ~\(Fmt.pct(f)) at reset") }
        return L("本周还没有用量", "No use yet this week")
    }

    private func detail(_ u: Usage) -> String {
        let rate = L("最近 1 小时 ", "last hour ") + String(format: "%.1f%%/h", u.burnPerHour)
        if let at = u.runsOutAt {
            let h = Int(u.weekEnd.timeIntervalSince(at) / 3600)
            return L("比 \(Fmt.dayTime(u.weekEnd)) 重置早 \(h) 小时 · ", "\(h) h before the \(Fmt.dayTime(u.weekEnd)) reset · ") + rate
        }
        return L("\(Fmt.dayTime(u.weekEnd)) 重置 · ", "resets \(Fmt.dayTime(u.weekEnd)) · ") + rate
    }

    private func provenance(_ u: Usage) -> String {
        var parts: [String] = []
        if let o = u.s.weekly.official, let age = u.officialAge {
            parts.append(L("官方读数 \(Fmt.pct(o)) 是 \(Fmt.age(age))前的", "Official reading \(Fmt.pct(o)) is \(Fmt.age(age)) old"))
        } else {
            parts.append(L("本周还没有官方读数", "No official reading this week"))
        }
        if !u.calibrated { parts.append(L("换算系数未校准", "rate not calibrated")) }
        return parts.joined(separator: " · ")
    }
}

/// The gear button; AppKit shows its menu so the menu sits under the button.
struct MenuAnchor: NSViewRepresentable {
    var showMenu: (NSView) -> Void

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!, target: context.coordinator, action: #selector(Coordinator.click(_:)))
        b.isBordered = false
        b.contentTintColor = .secondaryLabelColor
        return b
    }

    func updateNSView(_ b: NSButton, context: Context) { context.coordinator.showMenu = showMenu }
    func makeCoordinator() -> Coordinator { Coordinator(showMenu: showMenu) }

    final class Coordinator: NSObject {
        var showMenu: (NSView) -> Void
        init(showMenu: @escaping (NSView) -> Void) { self.showMenu = showMenu }
        @objc func click(_ sender: NSButton) { showMenu(sender) }
    }
}
