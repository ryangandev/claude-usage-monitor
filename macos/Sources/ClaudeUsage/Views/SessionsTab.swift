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
                     ? L("本周 \(u.projects.count) 个项目，有绿点的最近 10 分钟有动静，排最前。点项目展开看会话。",
                         "\(u.projects.count) projects this week. A green dot means activity in the last 10 minutes, listed first. Click a project to see its sessions.")
                     : L("绿点是最近 10 分钟有动静的会话，排最前；其余按用掉的额度排。本周一共 \(u.sessions.count) 个会话。",
                         "A green dot means activity in the last 10 minutes, listed first; the rest by quota used. \(u.sessions.count) sessions this week."))
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
        ForEach(u.sessions) { s in
            Row(dot: u.isActive(s) ? Theme.live : Theme.idle, title: s.title, second: s.project, used: u.pct(s.total),
                width: s.total / top, subShare: s.total > 0 ? s.sub / s.total : 0, agents: s.agents,
                last: Fmt.ago(s.last, now: u.s.now), lastLive: u.isActive(s), dollars: s.total, cols: cols)
            Divider().overlay(Theme.line2)
        }
    }

    @ViewBuilder private var projectRows: some View {
        ForEach(u.projects) { p in
            let open = settings.expandedProjects.contains(p.name)
            let live = p.sessions.contains(where: u.isActive)
            Button {
                withAnimation(Theme.ease) {
                    if open { settings.expandedProjects.remove(p.name) } else { settings.expandedProjects.insert(p.name) }
                }
            } label: {
                Row(chevron: open, liveMark: live, title: p.name, bold: true, second: L("\(p.sessions.count) 个会话", "\(p.sessions.count) sessions"),
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
                    Row(dot: u.isActive(s) ? Theme.live : Theme.idle, title: s.title, child: true, second: "", used: u.pct(s.total),
                        width: s.total / top, subShare: s.total > 0 ? s.sub / s.total : 0, agents: s.agents,
                        last: Fmt.ago(s.last, now: u.s.now), lastLive: u.isActive(s), dollars: s.total, cols: cols)
                    Divider().overlay(Theme.line2)
                }
            }
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

private struct Row: View {
    var dot: Color? = nil
    var chevron: Bool? = nil
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
            Group {
                if let chevron {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.sub)
                        .rotationEffect(.degrees(chevron ? 90 : 0))
                } else if let dot, !child {
                    Dot(color: dot, size: 7)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: 10)
            HStack(spacing: 8) {
                if child, let dot { Dot(color: dot) }
                Text(title).fontWeight(bold || !child ? (bold ? .semibold : .medium) : .regular).lineLimit(1)
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
