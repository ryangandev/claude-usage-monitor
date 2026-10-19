import SwiftUI

/// The full window: a sidebar of tabs with a settings button, and the chosen tab.
struct DashboardView: View {
    var monitor: Monitor
    var actions: AppActions
    @State private var settings = Settings.shared
    @State private var width: CGFloat = 1100
    @State private var loginOn = LoginItem.enabled
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.line)
            VStack(spacing: 0) {
                topBar
                Divider().overlay(Theme.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(settings.tab)).font(.system(size: 22, weight: .semibold)).kerning(-0.2)
                            Text(lede(settings.tab)).sub(13)
                        }
                        if let u = monitor.usage {
                            switch settings.tab {
                            case .overview: OverviewTab(u: u)
                            case .agents: AgentsTab(u: u)
                            case .sessions: SessionsTab(u: u)
                            case .weeks: WeeksTab(u: u)
                            }
                        } else {
                            Text(monitor.problem ?? L("正在读取用量…", "Reading usage…")).sub(13)
                        }
                    }
                    .padding(.horizontal, 32).padding(.vertical, 24)
                    .frame(maxWidth: 1240, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .environment(\.contentWidth, min(width, 1240) - 64)
                }
                .id(settings.tab)  // each tab opens at its top
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            }
            .background(Theme.main)
        }
        .foregroundStyle(Theme.text)
        .ignoresSafeArea()
        // Login items can also change in System Settings, so read it again whenever the app comes forward.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginOn = LoginItem.enabled }
        .id(settings.isChinese)
        .sheet(isPresented: $showSettings) { SettingsSheet(loginOn: $loginOn).id(settings.isChinese) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: StatusController.ring(fraction: (monitor.usage?.weekly ?? 0) / 100, color: NSColor(monitor.usage?.status.color ?? Theme.accent)))
                Text(L("Claude 用量", "Claude Usage")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let t = monitor.state?.tier, t.contains("max_") {
                    Text(t.contains("20x") ? "Max 20x" : "Max 5x").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.sub)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(Theme.chip, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8).padding(.top, 48).padding(.bottom, 14)

            ForEach(Tab.allCases, id: \.self) { tab in
                let on = settings.tab == tab
                Button { settings.tab = tab } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(tab)).font(.system(size: 12)).frame(width: 16)
                        Text(title(tab))
                        Spacer()
                        if let c = count(tab) { Text(c).font(.system(size: 12)).foregroundStyle(Theme.liveText).mono() }
                    }
                    .font(.system(size: 13, weight: on ? .medium : .regular))
                    .foregroundStyle(on ? Theme.text : Theme.sub)
                    .padding(.horizontal, 8).frame(height: 30)
                    .background(on ? Theme.navOn : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(Pressable())
                .accessibilityAddTraits(on ? .isSelected : [])
            }

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 14))
                    .foregroundStyle(showSettings ? Theme.text : Theme.sub)
                    .frame(width: 30, height: 30)
                    .background(showSettings ? Theme.navOn : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(Pressable())
            .keyboardShortcut(",", modifiers: .command)
            .help(L("设置 (⌘,)", "Settings (⌘,)"))
            .accessibilityLabel(L("设置", "Settings"))
            .padding(.leading, 2)
        }
        .padding(.horizontal, 10).padding(.bottom, 14)
        .frame(width: 228)
        .background(VisualEffect())
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text(L("本周", "This week")).sub(13)
            Text("›").sub(13)
            Text(title(settings.tab)).font(.system(size: 13, weight: .medium))
            Spacer()
            if let u = monitor.usage, !u.calibrated {
                Button(action: actions.enterReading) {
                    HStack(spacing: 6) {
                        InfoIcon()
                        Text(L("换算系数未校准 · ", "Rate not calibrated · ")).foregroundStyle(Theme.sub)
                            + Text(L("录入官方读数", "Enter official reading")).foregroundStyle(Theme.accent)
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.sub)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Theme.chip, in: Capsule())
                }
                .buttonStyle(Pressable())
            }
            HStack(spacing: 6) {
                Dot(color: monitor.link == .live ? Theme.live : Theme.idle)
                Text(monitor.link == .live ? L("实时 · ", "Live · ") + Fmt.time(monitor.lastUpdate ?? Date()) : L("服务没响应", "Not responding")).mono()
            }
            .sub()
        }
        .padding(.horizontal, 28).frame(height: 52)
    }

    private func title(_ t: Tab) -> String {
        switch t {
        case .overview: return L("概览", "Overview")
        case .agents: return L("子代理", "Subagents")
        case .sessions: return L("会话", "Sessions")
        case .weeks: return L("往周", "Past weeks")
        }
    }

    private func lede(_ t: Tab) -> String {
        switch t {
        case .overview: return L("会不会在重置前用满，还能跑多久，现在是谁在烧。", "Will it run out before the reset, how long is left, and what is burning now.")
        case .agents: return L("正在跑的子代理，和各档模型每个大概要用掉多少额度。", "Running subagents, and roughly how much quota each model and effort costs.")
        case .sessions: return L("正在用的会话排最前，其余按本周用掉的额度排。", "Active sessions first, the rest by quota used this week.")
        case .weeks: return L("每周三 08:00 重置，跟前几周比一比。", "Resets every Wednesday 8:00 AM. Compare with earlier weeks.")
        }
    }

    private func icon(_ t: Tab) -> String {
        switch t {
        case .overview: return "square.grid.2x2"
        case .agents: return "cpu"
        case .sessions: return "text.alignleft"
        case .weeks: return "calendar"
        }
    }

    private func count(_ t: Tab) -> String? {
        guard let u = monitor.usage else { return nil }
        switch t {
        case .agents: return u.running.isEmpty ? nil : L("\(u.running.count) 运行中", "\(u.running.count) running")
        case .sessions:
            let n = u.sessions.filter(u.isActive).count
            return n == 0 ? nil : L("\(n) 活跃", "\(n) active")
        default: return nil
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Open at login, appearance and language, one row each, in a sheet on the dashboard window.
struct SettingsSheet: View {
    @Binding var loginOn: Bool
    @State private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("设置", "Settings")).font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 6)
            VStack(spacing: 0) {
                row("power", Theme.live, L("开机启动", "Open at login")) {
                    Toggle("", isOn: Binding(get: { loginOn }, set: { LoginItem.set($0); loginOn = LoginItem.enabled }))
                        .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
                }
                Divider().overlay(Theme.line)
                row("circle.lefthalf.filled", Theme.accent, L("外观", "Appearance")) {
                    Picker("", selection: $settings.appearance) {
                        Text(L("跟随系统", "Match system")).tag(Appearance.system)
                        Text(L("浅色", "Light")).tag(Appearance.light)
                        Text(L("深色", "Dark")).tag(Appearance.dark)
                    }
                    .labelsHidden().frame(width: 140)
                }
                Divider().overlay(Theme.line)
                row("globe", Color(light: 0x3B82C4, dark: 0x4A90D2), L("语言", "Language")) {
                    Picker("", selection: $settings.language) {
                        Text(L("跟随系统", "Match system")).tag(Language.system)
                        Text("中文").tag(Language.zh)
                        Text("English").tag(Language.en)
                    }
                    .labelsHidden().frame(width: 140)
                }
            }
            .padding(.horizontal, 12).padding(.top, 6)
            HStack(spacing: 12) {
                Text(L("“跟随系统”随 macOS 的设置变化。", "Match system follows your macOS settings.")).sub()
                Spacer()
                Button(L("完成", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 18)
        }
        .frame(width: 460)
        .foregroundStyle(Theme.text)
    }

    private func row(_ icon: String, _ tile: Color, _ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(tile, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            Text(title).font(.system(size: 13))
            Spacer()
            control()
        }
        .padding(8).frame(minHeight: 52)
    }
}
