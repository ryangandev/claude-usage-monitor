import SwiftUI

struct SessionsTab: View {
    var u: Usage
    @State private var settings = Settings.shared
    @Environment(\.contentWidth) private var width

    /// Which columns fit: the subagent share goes first, then the subagent count.
    private var cols: Cols { width >= 960 ? .all : width >= 760 ? .noShare : .narrow }

    var body: some View {
        let byProject = settings.grouping == .project
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Segmented(options: [(SessionGrouping.session, L("按会话", "Session")), (.project, L("按项目", "Project"))],
                          selection: $settings.grouping, height: 26)
                    .frame(width: 200)
                Text(byProject
                     ? L("本周 \(u.projects.count) 个项目，有绿点的最近 10 分钟有动静，排最前。点项目展开看会话，点有子代理的会话看子代理。",
                         "\(u.projects.count) projects this week. A green dot means activity in the last 10 minutes, listed first. Click a project to see its sessions, and a session to see its subagents.")
                     : L("绿点是最近 10 分钟有动静的会话，排最前；其余按用掉的额度排。本周一共 \(u.sessions.count) 个会话，点有子代理的会话展开看子代理。",
                         "A green dot means activity in the last 10 minutes, listed first; the rest by quota used. \(u.sessions.count) sessions this week; click one with subagents to see them."))
                    .sub()
            }
            VStack(spacing: 0) {
                Columns(first: byProject ? L("项目", "Project") : L("会话", "Session"), second: byProject ? L("会话数", "Sessions") : L("项目", "Project"), cols: cols)
                Divider().overlay(Theme.line)
                LazyVStack(spacing: 0) {
                    if byProject { projectRows } else { sessionRows }
                }
                .id(byProject)  // both lists hold rows keyed by session id; without this the lazy stack reuses the other list's rows
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
        }
    }

    /// Bars are drawn against the largest row in view.
    private var top: Double {
        let m = settings.grouping == .project ? u.projects.map(\.total).max() : u.sessions.map(\.total).max()
        return max(m ?? 1, 0.01)
    }

    @ViewBuilder private var sessionRows: some View {
        let bySession = u.agentsBySession
        ForEach(u.sessions) { s in
            let open = s.agents > 0 && settings.expandedSessions.contains(s.id)
            toggle(s, open: open) {
                Row(lead: s.agents > 0 ? .chevron(open) : .none, marks: [.dot(u.isActive(s) ? Theme.live : Theme.idle)],
                    title: s.title, second: s.project, used: u.pct(s.total),
                    width: s.total / top, subShare: s.total > 0 ? s.sub / s.total : 0, agents: s.agents,
                    last: Fmt.ago(s.last, now: u.s.now), lastLive: u.isActive(s), dollars: s.total, cols: cols)
            }
            Divider().overlay(Theme.line2)
            if open { agentRows(s, bySession[s.id] ?? [], indent: 14) }
        }
    }

    @ViewBuilder private var projectRows: some View {
        let bySession = u.agentsBySession
        ForEach(u.projects) { p in
            let open = settings.expandedProjects.contains(p.name)
            let live = p.sessions.contains(where: u.isActive)
            Button {
                withAnimation(Theme.ease) {
                    if open { settings.expandedProjects.remove(p.name) } else { settings.expandedProjects.insert(p.name) }
                }
            } label: {
                Row(lead: .chevron(open), liveMark: live, title: p.name, bold: true, second: L("\(p.sessions.count) 个会话", p.sessions.count == 1 ? "1 session" : "\(p.sessions.count) sessions"),
                    used: u.pct(p.total), width: p.total / top, subShare: p.total > 0 ? p.sub / p.total : 0, agents: p.agents,
                    last: Fmt.ago(p.last, now: u.s.now), lastLive: live, dollars: p.total, cols: cols)
                    .background(open ? Theme.line2 : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(open ? L("已展开", "expanded") : L("已收起", "collapsed"))
            Divider().overlay(Theme.line2)
            if open {
                ForEach(p.sessions) { s in
                    let sOpen = s.agents > 0 && settings.expandedSessions.contains(s.id)
                    toggle(s, open: sOpen) {
                        Row(marks: [s.agents > 0 ? .chevron(sOpen) : .space, .dot(u.isActive(s) ? Theme.live : Theme.idle)],
                            title: s.title, child: true, second: "", used: u.pct(s.total),
                            width: s.total / top, subShare: s.total > 0 ? s.sub / s.total : 0, agents: s.agents,
                            last: Fmt.ago(s.last, now: u.s.now), lastLive: u.isActive(s), dollars: s.total, cols: cols)
                    }
                    Divider().overlay(Theme.line2)
                    if sOpen { agentRows(s, bySession[s.id] ?? [], indent: 36) }
                }
            }
        }
    }

    /// A session with subagents opens and closes on a click; one without is a plain row.
    @ViewBuilder private func toggle(_ s: UsageState.Session, open: Bool, @ViewBuilder row: () -> some View) -> some View {
        if s.agents > 0 {
            Button {
                withAnimation(Theme.ease) {
                    if open { settings.expandedSessions.remove(s.id) } else { settings.expandedSessions.insert(s.id) }
                }
            } label: {
                row().background(open ? Theme.line2 : .clear).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(open ? L("已展开", "expanded") : L("已收起", "collapsed"))
        } else {
            row()
        }
    }

    @ViewBuilder private func agentRows(_ s: UsageState.Session, _ list: [UsageState.Agent], indent: CGFloat) -> some View {
        ForEach(list) { a in
            AgentLine(a: a, u: u, indent: indent, top: top, cols: cols)
            Divider().overlay(Theme.line2)
        }
        // The state lists the costliest subagents only; the rest are on the subagents tab.
        if list.count < s.agents {
            Text(L("还有 \(s.agents - list.count) 个子代理没列出，在子代理页看全部。", "\(s.agents - list.count) more not listed here; the subagents tab has them all."))
                .sub(11).padding(.leading, 44 + indent).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(Theme.line2)
        }
    }
}

private enum Cols: Comparable { case narrow, noShare, all }

private struct Columns: View {
    var first: String
    var second: String
    var cols: Cols
    var body: some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 10, height: 1)
            Text(first).frame(maxWidth: .infinity, alignment: .leading)
            Text(second).frame(width: 140, alignment: .leading)
            Text(L("本周用掉的额度", "Quota used this week")).frame(width: cols == .all ? 200 : 170, alignment: .leading)
            if cols == .all { Text(L("子代理占比", "Subagent share")).frame(width: 150, alignment: .leading) }
            if cols >= .noShare { Text(L("子代理", "Subagents")).frame(width: 70, alignment: .trailing) }
            Text(L("最近", "Last")).frame(width: 100, alignment: .trailing)
        }
        .sub(11).padding(.horizontal, 20).padding(.vertical, 10)
    }
}

enum Mark {
    case none, space, dot(Color), chevron(Bool)

    @ViewBuilder var view: some View {
        switch self {
        case .none: EmptyView()
        case .space: Color.clear.frame(width: 10, height: 1)
        case .dot(let c): Dot(color: c)
        case .chevron(let open):
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.sub)
                .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 10)
        }
    }
}

private struct Row: View {
    /// What sits in the column left of the title: a project's or a session's chevron.
    var lead: Mark = .none
    /// What comes right before the title.
    var marks: [Mark] = []
    var liveMark = false
    var title: String
    var bold = false
    var child = false
    var second: String
    var used: Double
    var width: Double
    var subShare: Double
    var agents: Int
    var last: String
    var lastLive: Bool
    var dollars: Double
    var cols: Cols

    var body: some View {
        HStack(spacing: 14) {
            ZStack { Color.clear.frame(width: 10, height: 1); lead.view }
            HStack(spacing: 8) {
                ForEach(Array(marks.enumerated()), id: \.offset) { $0.element.view }
                Text(title).fontWeight(bold ? .semibold : child ? .regular : .medium).lineLimit(1)
                if liveMark { Dot() }
            }
            .padding(.leading, child ? 4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(second).sub().lineLimit(1).frame(width: 140, alignment: .leading)
            HStack(spacing: 8) {
                Meter(value: width, color: child ? Theme.accent.opacity(0.6) : Theme.accent, height: child ? 4 : 6)
                Text(Fmt.pct(used, digits: 1)).fontWeight(child ? .regular : .semibold).foregroundStyle(child ? Theme.sub : Theme.text).mono()
                    .frame(width: 48, alignment: .trailing)
            }
            .frame(width: cols == .all ? 200 : 170)
            if cols == .all {
                HStack(spacing: 8) {
                    Meter(value: subShare, color: Theme.accentSoft, height: child ? 4 : 6)
                    Text(Fmt.pct(subShare * 100)).sub().mono().frame(width: 36, alignment: .trailing)
                }
                .frame(width: 150)
            }
            if cols >= .noShare {
                Text(agents > 0 ? "\(agents)" : "-").foregroundStyle(Theme.sub).mono().frame(width: 70, alignment: .trailing)
            }
            Text(last).font(.system(size: 12)).foregroundStyle(lastLive ? Theme.liveText : Theme.sub).mono().frame(width: 100, alignment: .trailing)
        }
        .font(.system(size: child ? 12 : 13))
        .padding(.horizontal, 20).padding(.vertical, child ? 8 : 11)
        .help(Fmt.usd(dollars, cents: true) + L(" 等价 API 价", " at API prices"))
    }
}

/// One subagent under its open session, in the session table's columns.
private struct AgentLine: View {
    var a: UsageState.Agent
    var u: Usage
    var indent: CGFloat
    var top: Double
    var cols: Cols

    var body: some View {
        let took = Fmt.duration(a.last.timeIntervalSince(a.first))
        HStack(spacing: 14) {
            Color.clear.frame(width: 10, height: 1)
            HStack(spacing: 8) {
                Dot(color: a.active ? Theme.live : Theme.idle)
                Text(a.label).lineLimit(1)
            }
            .padding(.leading, indent)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.kind(family: Fmt.family(ofModel: a.model), effort: a.effort)).sub().lineLimit(1).frame(width: 140, alignment: .leading)
            HStack(spacing: 8) {
                Meter(value: a.cost / top, color: Theme.accentSoft, height: 4)
                Text(Fmt.pct(u.pct(a.cost), digits: 1)).foregroundStyle(Theme.sub).mono().frame(width: 48, alignment: .trailing)
            }
            .frame(width: cols == .all ? 200 : 170)
            if cols == .all {
                Text(a.active ? L("运行中 · 已跑 \(took)", "Running · \(took) so far") : L("已完成 · 用时 \(took)", "Done · took \(took)"))
                    .foregroundStyle(a.active ? Theme.liveText : Theme.sub).lineLimit(1).frame(width: 150, alignment: .leading)
            }
            if cols >= .noShare {
                Text(Fmt.tokens(a.context)).foregroundStyle(Theme.sub).mono().frame(width: 70, alignment: .trailing)
                    .help(L("当前上下文", "Current context"))
            }
            Text(Fmt.ago(a.last, now: u.s.now)).foregroundStyle(a.active ? Theme.liveText : Theme.sub).mono().frame(width: 100, alignment: .trailing)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.line2.opacity(0.5))
        .help(Fmt.usd(a.cost, cents: true) + L(" 等价 API 价", " at API prices"))
    }
}
