import Charts
import SwiftUI

struct OverviewTab: View {
    var u: Usage
    @State private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WeightedColumns(weights: [2, 1, 1]) {
                quotaCard
                timeLeftCard
                fiveHourCard
            }
            chartCard
            HStack(alignment: .top, spacing: 16) {
                burningAgents
                burningSessions
            }
            if let r = u.s.resources { MachineCard(r: r) }
        }
    }

    // MARK: Cards

    private var quotaCard: some View {
        Card(padding: 20) {
            HStack {
                Text(L("每周额度", "Weekly quota")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.sub)
                Spacer()
                u.status.badge
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Fmt.pct(u.weekly)).font(.system(size: 44, weight: .semibold)).mono().kerning(-1.2)
                Text(headline).font(.system(size: 15, weight: .medium)).lineLimit(2)
            }
            .padding(.top, 12)
            Meter(value: u.weekly / 100, color: u.status.color, height: 8, tick: u.elapsed).padding(.vertical, 14)
            HStack {
                Text(provenance)
                Spacer()
                Text(L("时间已过 \(Fmt.pct(u.elapsed * 100)) · \(Fmt.dayTime(u.weekEnd)) 重置",
                       "\(Fmt.pct(u.elapsed * 100)) of the week gone · resets \(Fmt.dayTime(u.weekEnd))")).mono()
            }
            .sub()
        }
    }

    private var headline: String {
        if u.status == .full { return L("已用满", "Full") }
        if let at = u.runsOutAt { return L("按现在的速度 \(Fmt.dayTime(at)) 用满", "At this pace, full by \(Fmt.dayTime(at))") }
        if let f = u.forecastAtReset { return L("按本周平均，重置时约 \(Fmt.pct(f))", "~\(Fmt.pct(f)) at reset at the week's average") }
        return ""
    }

    private var provenance: String {
        if let o = u.s.weekly.official, let age = u.officialAge {
            return L("估算：官方 \(Fmt.pct(o))（\(Fmt.age(age))前）加上之后的用量", "Estimate: official \(Fmt.pct(o)) (\(Fmt.age(age)) ago) plus use since")
        }
        return L("估算：本周还没有官方读数", "Estimate: no official reading this week")
    }

    private var timeLeftCard: some View {
        Card(padding: 20) {
            Text(L("还能跑多久", "Time left")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.sub)
            Group {
                if let h = u.hoursLeft {
                    Text(h >= 48 ? L("约 \(Int(h / 24)) 天", "~\(Int(h / 24)) days") : L("约 \(Int(h.rounded())) 小时", "~\(Int(h.rounded())) hours"))
                } else {
                    Text(L("现在没在用", "Not in use"))
                }
            }
            .font(.system(size: 30, weight: .semibold)).mono().kerning(-0.6)
            .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 10)
            Text(L("按最近 1 小时 \(String(format: "%.1f", u.burnPerHour))%/h，剩 \(Fmt.pct(100 - u.weekly))",
                   "\(String(format: "%.1f", u.burnPerHour))%/h over the last hour, \(Fmt.pct(100 - u.weekly)) left"))
                .sub().mono().padding(.top, 10)
            Spacer(minLength: 10)
            if let n = u.moreOfReference, let k = u.referenceKind {
                Text(L("约等于 \(n) 个 \(Fmt.kind(family: k.family, effort: k.effort)) 子代理",
                       "About \(n) \(Fmt.kind(family: k.family, effort: k.effort)) subagents")).sub().mono()
            }
        }
    }

    private var fiveHourCard: some View {
        Card(padding: 20) {
            Text(L("5 小时窗口", "5-hour window")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.sub)
            Text(Fmt.pct(u.fiveHour)).font(.system(size: 30, weight: .semibold)).mono().kerning(-0.6).padding(.top, 10)
            Meter(value: u.fiveHour / 100, color: u.fiveHourMatters ? Theme.warn : Theme.accent, height: 4).padding(.top, 12)
            Spacer(minLength: 10)
            Group {
                if let end = u.s.fiveHour.end {
                    Text(L("\(Fmt.time(end)) 重置", "resets \(Fmt.time(end))")
                         + (u.fiveHourMatters ? "" : L(" · 现在不是瓶颈", " · not the limit now")))
                } else {
                    Text(L("没有打开的窗口", "No open window"))
                }
            }
            .sub()
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        Card(padding: 18) {
            // One row when it fits; on a narrow window the legend drops below the title.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    chartTitleText
                    HStack(spacing: 16) { legend }
                    Spacer(minLength: 16)
                    chartPicker
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        chartTitleText
                        Spacer(minLength: 16)
                        chartPicker
                    }
                    HStack(spacing: 16) { legend }
                }
            }
            Group {
                switch settings.chart {
                case .cumulative: cumulative
                case .daily: daily
                case .hourly: hourly
                }
            }
            .frame(height: 230)
            .padding(.top, 14)
        }
    }

    private var chartTitleText: some View {
        Text(chartTitle).font(.system(size: 14, weight: .semibold)).fixedSize()
    }

    private var chartPicker: some View {
        Segmented(options: [(ChartView.cumulative, L("累计", "Cumulative")), (.daily, L("每天", "Daily")), (.hourly, L("48 小时", "48 hours"))],
                  selection: $settings.chart)
            .fixedSize()
    }

    private var chartTitle: String {
        switch settings.chart {
        case .cumulative: return L("本周累计", "This week, cumulative")
        case .daily: return L("每天用量", "Daily use")
        case .hourly: return L("最近 48 小时", "Last 48 hours")
        }
    }

    @ViewBuilder private var legend: some View {
        switch settings.chart {
        case .cumulative:
            LegendLine(color: Theme.accent, label: L("实际", "Actual"))
            LegendLine(color: Theme.warn, label: L("按最近 1 小时", "At last hour's pace"), dash: [6, 4])
            LegendLine(color: Theme.sub, label: L("按本周平均", "At the week's average"), dash: [1, 4])
            LegendLine(color: Theme.budget, label: L("时间进度", "Time"), dash: [4, 4], width: 1)
        case .daily, .hourly:
            LegendSwatch(color: Theme.accent, label: "Opus")
            LegendSwatch(color: Theme.accentSoft, label: L("Sonnet 和其他", "Sonnet and other"))
            if settings.chart == .daily { LegendLine(color: Theme.budget, label: L("日预算", "Daily budget"), dash: [4, 4], width: 1) }
        }
    }

    private var cumulative: some View {
        let curve = u.s.weekCurve ?? []
        let now = u.s.now
        let fastEnd: (Date, Double)? = {
            guard u.burnPerHour > 0 else { return nil }
            if let at = u.runsOutAt { return (at, 100) }
            return (u.weekEnd, min(100, u.weekly + u.burnPerHour * u.weekEnd.timeIntervalSince(now) / 3600))
        }()
        return Chart {
            LineMark(x: .value("t", u.weekStart), y: .value("pct", 0), series: .value("s", "time"))
                .foregroundStyle(Theme.budget).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            LineMark(x: .value("t", u.weekEnd), y: .value("pct", 100), series: .value("s", "time"))
                .foregroundStyle(Theme.budget).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            if let f = u.forecastAtReset {
                LineMark(x: .value("t", now), y: .value("pct", u.weekly), series: .value("s", "avg"))
                    .foregroundStyle(Theme.sub).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4]))
                LineMark(x: .value("t", u.weekEnd), y: .value("pct", min(f, 100)), series: .value("s", "avg"))
                    .foregroundStyle(Theme.sub).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4]))
            }
            if let (t, v) = fastEnd {
                LineMark(x: .value("t", now), y: .value("pct", u.weekly), series: .value("s", "fast"))
                    .foregroundStyle(Theme.warn).lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                LineMark(x: .value("t", t), y: .value("pct", v), series: .value("s", "fast"))
                    .foregroundStyle(Theme.warn).lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                if u.runsOutAt != nil {
                    PointMark(x: .value("t", t), y: .value("pct", v)).foregroundStyle(Theme.warn).symbolSize(60)
                        .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                            Text(L("\(Fmt.dayTime(t)) 用满", "Full \(Fmt.dayTime(t))")).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.warnText).mono()
                        }
                }
            }
            ForEach(Array(curve.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("t", p.t), y: .value("pct", p.pct), series: .value("s", "actual"))
                    .foregroundStyle(Theme.accent.opacity(0.08))
                LineMark(x: .value("t", p.t), y: .value("pct", p.pct), series: .value("s", "actual"))
                    .foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            PointMark(x: .value("t", now), y: .value("pct", u.weekly)).foregroundStyle(Theme.accent).symbolSize(70)
                .annotation(position: .bottom, spacing: 6) {
                    Text(L("现在 ", "Now ") + Fmt.pct(u.weekly)).font(.system(size: 12, weight: .semibold)).mono()
                }
        }
        .chartXScale(domain: u.weekStart...u.weekEnd)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 11)).foregroundStyle(Theme.sub) }
            }
        }
        .chartXAxis {
            AxisMarks(values: (0..<7).map { u.weekStart.addingTimeInterval(Double($0) * 86400 + 43200) }) { v in
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        Text(Fmt.weekday(d)).font(.system(size: 12, weight: Calendar.current.isDate(d, inSameDayAs: u.s.now) ? .semibold : .regular))
                            .foregroundStyle(Theme.sub)
                    }
                }
            }
        }
    }

    private var daily: some View {
        let budget = 100.0 / 7
        let days = u.dailyPct
        // Categorical x: each day is a named slot, which is what gives bars a width.
        let label = { (i: Int) in days[i].state == "current" ? L("今天", "Today") : Fmt.weekday(days[i].start) + " " + Fmt.monthDay(days[i].start) }
        return Chart {
            ForEach(days.indices, id: \.self) { i in
                let d = days[i]
                BarMark(x: .value("day", label(i)), y: .value("pct", d.opus), width: .ratio(0.55)).foregroundStyle(Theme.accent)
                BarMark(x: .value("day", label(i)), y: .value("pct", d.other), width: .ratio(0.55)).foregroundStyle(Theme.accentSoft)
                    .annotation(position: .top, spacing: 4) {
                        if d.opus + d.other > 0 { Text(Fmt.pct(d.opus + d.other, digits: 1)).font(.system(size: 11)).foregroundStyle(Theme.sub).mono() }
                    }
            }
            RuleMark(y: .value("budget", budget)).foregroundStyle(Theme.budget).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 11)).foregroundStyle(Theme.sub) }
            }
        }
    }

    private var hourly: some View {
        Chart {
            ForEach(Array(u.s.hours.enumerated()), id: \.offset) { _, h in
                BarMark(x: .value("hour", h.hour, unit: .hour), y: .value("pct", u.pct(h.opus))).foregroundStyle(Theme.accent)
                BarMark(x: .value("hour", h.hour, unit: .hour), y: .value("pct", u.pct(h.total - h.opus))).foregroundStyle(Theme.accentSoft)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { v in
                AxisGridLine().foregroundStyle(Theme.line2)
                AxisValueLabel { if let d = v.as(Date.self) { Text(Fmt.dayTime(d)).font(.system(size: 11)).foregroundStyle(Theme.sub) } }
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text(String(format: "%.1f%%", v.as(Double.self) ?? 0)).font(.system(size: 11)).foregroundStyle(Theme.sub) }
            }
        }
    }

    // MARK: Burning now

    private var burningAgents: some View {
        Card(padding: 14) {
            HStack {
                SectionTitle(text: L("现在在烧 · 子代理", "Burning now · subagents"))
                Spacer()
                Text(L("时长 · 已用额度", "time · quota used")).sub(11)
            }
            .padding(.bottom, 6)
            if u.running.isEmpty {
                Text(L("没有正在跑的子代理", "No subagent is running")).sub().padding(.vertical, 6)
            }
            ForEach(u.running.prefix(4)) { a in
                HStack(spacing: 8) {
                    Dot()
                    Text(a.label).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.duration(a.last.timeIntervalSince(a.first))).sub(11).mono()
                    Text(Fmt.pct(u.pct(a.cost), digits: 1)).font(.system(size: 12, weight: .medium)).mono().frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 12)).padding(.vertical, 6)
            }
        }
    }

    private var burningSessions: some View {
        let active = u.sessions.filter(u.isActive).prefix(4)
        return Card(padding: 14) {
            HStack {
                SectionTitle(text: L("现在在烧 · 会话", "Burning now · sessions"))
                Spacer()
                Text(L("运行中的子代理 · 本周已用", "running · used this week")).sub(11)
            }
            .padding(.bottom, 6)
            if active.isEmpty {
                Text(L("最近 10 分钟没有会话在用", "No session in the last 10 minutes")).sub().padding(.vertical, 6)
            }
            ForEach(Array(active)) { s in
                HStack(spacing: 8) {
                    Dot()
                    Text(s.title).lineLimit(1)
                    Spacer(minLength: 8)
                    Text((s.running ?? 0) > 0 ? L("\(s.running ?? 0) 个", "\(s.running ?? 0)") : L("主会话", "main")).sub(11).mono()
                    Text(Fmt.pct(u.pct(s.total), digits: 1)).font(.system(size: 12, weight: .medium)).mono().frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 12)).padding(.vertical, 6)
            }
        }
    }
}

struct LegendLine: View {
    var color: Color
    var label: String
    var dash: [CGFloat] = []
    var width: CGFloat = 2
    var body: some View {
        HStack(spacing: 6) {
            Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 14, y: 1)) }
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
                .frame(width: 14, height: 2)
            Text(label).sub().fixedSize()
        }
    }
}

struct LegendSwatch: View {
    var color: Color
    var label: String
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).sub()
        }
    }
}
