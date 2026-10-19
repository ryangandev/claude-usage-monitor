import SwiftUI

struct AgentsTab: View {
    var u: Usage
    @State private var filter: Filter = .running
    @Environment(\.contentWidth) private var width

    enum Filter: Hashable { case running, done, all }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stats
            // Side by side on a wide window, stacked on a narrow one.
            if width >= 900 {
                HStack(alignment: .top, spacing: 16) {
                    kinds.frame(width: 300)
                    table(compact: width - 316 < 760)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    kinds
                    table(compact: width < 760)
                }
            }
        }
        .onAppear { if u.running.isEmpty { filter = .all } }
    }

    private var stats: some View {
        let costliest = u.s.agentCounts.byKind.filter { ($0.medianCost ?? 0) > 0 && $0.count >= 2 }.max { ($0.medianCost ?? 0) < ($1.medianCost ?? 0) }
        let byRunning = Dictionary(grouping: u.running, by: \.sessionTitle).max { $0.value.count < $1.value.count }
        let cells: [(String, String, String)] = [
            (L("运行中", "Running"), "\(u.running.count)",
             byRunning.map { L("\($0.value.count) 个在\($0.key)", "\($0.value.count) in \($0.key)") } ?? L("现在没有", "None now")),
            (L("子代理用掉", "Subagents used"), Fmt.pct(u.pct(u.s.week.subagent)),
             L("占本周用量的 \(Fmt.pct(u.subagentShare * 100))", "\(Fmt.pct(u.subagentShare * 100)) of all use this week")),
            (L("最贵的一档", "Most expensive tier"), costliest.map { Fmt.kind(family: $0.family, effort: $0.effort) } ?? "-",
             costliest.map { L("每个中位 \(Fmt.pct(u.pct($0.medianCost ?? 0), digits: 2))", "median \(Fmt.pct(u.pct($0.medianCost ?? 0), digits: 2)) each") } ?? ""),
        ]
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                if i > 0 { Divider().overlay(Theme.line) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.0).sub()
                    Text(c.1).font(.system(size: 24, weight: .semibold)).mono().kerning(-0.4).lineLimit(1)
                    Text(c.2).sub().lineLimit(1)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }

    private var kinds: some View {
        let list = u.s.agentCounts.byKind.sorted { ($0.cost ?? 0) > ($1.cost ?? 0) }
        let top = max(list.first?.cost ?? 1, 0.01)
        return Card(padding: 16) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: L("按模型和 effort", "By model and effort"))
                Spacer()
                Text(L("用掉 · 每个中位", "used · median each")).sub(11)
            }
            .padding(.bottom, 12)
            VStack(spacing: 12) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, k in
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Fmt.kind(family: k.family, effort: k.effort)) + Text(L(" · \(k.count) 个", " · \(k.count)")).foregroundStyle(Theme.sub)
                            Spacer()
                            Text(Fmt.pct(u.pct(k.cost ?? 0), digits: 1)).fontWeight(.semibold).mono()
                            Text((k.medianCost ?? 0) > 0 ? Fmt.pct(u.pct(k.medianCost ?? 0), digits: 2) : "-").sub().mono().frame(width: 48, alignment: .trailing)
                        }
                        .font(.system(size: 12))
                        Meter(value: (k.cost ?? 0) / top, color: k.family == "opus" ? Theme.accent : Theme.accentSoft, height: 4)
                    }
                }
            }
        }
    }

    private var rows: [UsageState.Agent] {
        let all = u.s.agents.sorted { $0.cost > $1.cost }
        switch filter {
        case .running: return all.filter(\.active)
        case .done: return all.filter { !$0.active }
        case .all: return all
        }
    }

    private func table(compact: Bool) -> some View {
        let done = u.s.agents.count - u.running.count
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                Segmented(options: [(Filter.running, L("运行中 \(u.running.count)", "Running \(u.running.count)")),
                                    (.done, L("已完成 \(done)", "Done \(done)")), (.all, L("全部 \(u.s.agents.count)", "All \(u.s.agents.count)"))],
                          selection: $filter)
                    .frame(width: 300)
                Spacer()
                Text(L("按已用额度排序", "Sorted by quota used")).sub(11)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider().overlay(Theme.line)
            AgentRow.header(compact: compact)
            Divider().overlay(Theme.line)
            LazyVStack(spacing: 0) {
                ForEach(rows) { a in
                    AgentRow(a: a, u: u, compact: compact)
                    Divider().overlay(Theme.line2)
                }
            }
            if rows.isEmpty {
                Text(L("这里还没有", "Nothing here yet")).sub().padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(L("上下文按 1M 窗口画。", "Context bars assume a 1M window.")).sub().padding(.horizontal, 18).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }
}

private struct AgentRow: View {
    var a: UsageState.Agent
    var u: Usage
    /// Drops the session column, for a narrow table.
    var compact = false

    @MainActor static func header(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 8, height: 1)
            Text(L("任务", "Task")).frame(maxWidth: .infinity, alignment: .leading)
            if !compact { Text(L("会话", "Session")).frame(width: 140, alignment: .leading) }
            Text(L("模型", "Model")).frame(width: 110, alignment: .leading)
            Text(L("上下文", "Context")).frame(width: 120, alignment: .leading)
            Text(L("时长", "Time")).frame(width: 64, alignment: .trailing)
            Text(L("已用", "Used")).frame(width: 56, alignment: .trailing)
        }
        .sub(11).padding(.horizontal, 18).padding(.vertical, 8)
    }

    var body: some View {
        HStack(spacing: 12) {
            Dot(color: a.active ? Theme.live : Theme.idle, size: 7).frame(width: 8)
            Text(a.label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if !compact { Text(a.sessionTitle).lineLimit(1).foregroundStyle(Theme.sub).frame(width: 140, alignment: .leading) }
            Text(Fmt.kind(family: Fmt.family(ofModel: a.model), effort: a.effort)).foregroundStyle(Theme.sub).lineLimit(1).frame(width: 110, alignment: .leading)
            HStack(spacing: 6) {
                Meter(value: Double(a.context) / 1_000_000, color: a.context > 300_000 ? Theme.warn : Theme.accent, height: 4)
                Text(Fmt.tokens(a.context)).sub(11).mono().frame(width: 38, alignment: .trailing)
            }
            .frame(width: 120)
            Text(Fmt.duration(a.last.timeIntervalSince(a.first))).foregroundStyle(Theme.sub).mono().frame(width: 64, alignment: .trailing)
            Text(Fmt.pct(u.pct(a.cost), digits: 1)).fontWeight(.semibold).mono().frame(width: 56, alignment: .trailing)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18).padding(.vertical, 9)
        .help(Fmt.usd(a.cost, cents: true) + L(" 等价 API 价", " at API prices"))
    }
}
