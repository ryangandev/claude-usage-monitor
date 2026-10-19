import SwiftUI

/// This Mac's CPU and memory, and what each running session takes of it.
struct MachineCard: View {
    var r: UsageState.Resources

    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: L("本机占用", "This Mac"))
                Spacer()
                Text(summary).sub(11).mono()
            }
            .padding(.bottom, 6)
            HStack(spacing: 8) {
                Spacer()
                Text("CPU").frame(width: 56, alignment: .trailing)
                Text(L("内存", "Memory")).frame(width: 72, alignment: .trailing)
            }
            .sub(11).padding(.bottom, 2)
            ForEach(r.sessions) { s in
                row(dot: s.cpu >= 1 ? Theme.live : Theme.idle, title: title(s), note: s.session == nil ? nil : s.project, cpu: s.cpu, rss: s.rss, strong: true)
                if !s.agents.isEmpty || s.tools > 0 {
                    child(L("会话本身", "The session itself"), cpu: s.selfCpu, rss: s.selfRss)
                    ForEach(s.agents) { a in
                        child(L("子代理 · ", "Subagent · ") + (a.description ?? L("（无描述）", "(no description)")), cpu: a.cpu, rss: a.rss)
                    }
                    if s.tools > 0 {
                        child(L("命令 · \(s.tools) 个进程", s.tools == 1 ? "Commands · 1 process" : "Commands · \(s.tools) processes"), cpu: s.toolsCpu, rss: s.toolsRss)
                    }
                }
            }
            row(dot: nil, title: L("Claude 应用", "Claude app"), note: L("\(r.app.procs) 个进程", "\(r.app.procs) processes"), cpu: r.app.cpu, rss: r.app.rss, strong: true)
            Text(L("CPU 按单核算，100% 是占满一个核。子代理只有在自己的 worktree 里跑的命令能单独算出来，其余算在会话里。",
                   "CPU is per core: 100% is one full core. A subagent counts on its own only for commands it runs in its worktree; the rest counts under its session."))
                .sub(11).padding(.top, 8)
        }
    }

    private var summary: String {
        var parts = ["CPU " + Fmt.pct(r.cpuPct)]
        if let used = r.memUsed, let total = r.memTotal {
            parts.append(L("内存 ", "Memory ") + String(format: "%.1f / %.0f GB", used / 1_073_741_824, total / 1_073_741_824))
        }
        parts.append(L("\(r.cores) 核", "\(r.cores) cores"))
        return parts.joined(separator: " · ")
    }

    private func title(_ s: UsageState.Resources.SessionProcess) -> String {
        if s.session == nil { return (s.folder ?? "?") + L(" · 未识别的会话", " · unidentified session") }
        return s.title ?? String((s.session ?? "").prefix(8))
    }

    private func row(dot: Color?, title: String, note: String?, cpu: Double, rss: Double, strong: Bool) -> some View {
        HStack(spacing: 8) {
            if let dot { Dot(color: dot) } else { Image(systemName: "app").font(.system(size: 9)).foregroundStyle(Theme.sub).frame(width: 6) }
            Text(title).lineLimit(1).font(.system(size: 12, weight: strong ? .medium : .regular))
            if let note { Text(note).sub(11).lineLimit(1) }
            Spacer(minLength: 8)
            Text(Fmt.cpu(cpu)).font(.system(size: 12, weight: .medium)).mono().frame(width: 56, alignment: .trailing)
            Text(Fmt.bytes(rss)).font(.system(size: 12)).mono().frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    private func child(_ title: String, cpu: Double, rss: Double) -> some View {
        HStack(spacing: 8) {
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            Text(Fmt.cpu(cpu)).mono().frame(width: 56, alignment: .trailing)
            Text(Fmt.bytes(rss)).mono().frame(width: 72, alignment: .trailing)
        }
        .font(.system(size: 11)).foregroundStyle(Theme.sub)
        .padding(.leading, 14).padding(.vertical, 3)
    }
}
