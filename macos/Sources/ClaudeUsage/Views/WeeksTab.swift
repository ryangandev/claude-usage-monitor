import Charts
import SwiftUI

struct WeeksTab: View {
    var u: Usage

    private struct Bar: Identifiable {
        var id: String
        var label: String
        var kind: String
        var value: Double
    }

    var body: some View {
        let weeks = u.weeksWithUse
        VStack(alignment: .leading, spacing: 16) {
            if !u.calibrated {
                HStack(alignment: .top, spacing: 10) {
                    InfoIcon().padding(.top, 2)
                    Text(L("往周只能用等价 API 价来比。官方峰值和花费对不上的周显示为“-”，等录入几次官方读数校准换算系数后再换成百分比。",
                           "Past weeks can only be compared at API-equivalent prices. Weeks whose official peak does not match their spend show \"-\". They switch to percentages once a few official readings calibrate the rate."))
                        .lineSpacing(3)
                }
                .font(.system(size: 12)).foregroundStyle(Theme.warnText)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warnBg, in: RoundedRectangle(cornerRadius: 10))
            }
            Card(padding: 18) {
                HStack(spacing: 16) {
                    Text(L("每周用量", "Weekly use")).font(.system(size: 14, weight: .semibold))
                    LegendSwatch(color: Theme.accent, label: "Opus")
                    LegendSwatch(color: Theme.accentSoft, label: L("Sonnet 和其他", "Sonnet and other"))
                    LegendSwatch(color: Theme.chip, label: L("本周预测", "This week's forecast"))
                    Spacer()
                    Text(L("单位：等价 API 价", "Unit: API-equivalent price")).sub()
                }
                Chart(bars(weeks)) { b in
                    BarMark(x: .value("week", b.label), y: .value("usd", b.value), width: .ratio(0.4))
                        .foregroundStyle(by: .value("kind", b.kind))
                }
                .chartForegroundStyleScale(["opus": Theme.accent, "other": Theme.accentSoft, "forecast": Theme.chip])
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel { Text(Fmt.usd(v.as(Double.self) ?? 0)).font(.system(size: 11)).foregroundStyle(Theme.sub) }
                    }
                }
                .frame(height: 220).padding(.top, 14)
            }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(L("周", "Week")).frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        Text("Opus")
                        Text(L("Sonnet 和其他", "Sonnet and other"))
                        Text(L("子代理占比", "Subagent share"))
                        Text(L("官方峰值", "Official peak"))
                        Text(L("合计", "Total"))
                    }
                    .frame(width: 120, alignment: .trailing)
                }
                .sub(11).padding(.horizontal, 20).padding(.vertical, 10)
                Divider().overlay(Theme.line)
                ForEach(Array(weeks.reversed().enumerated()), id: \.offset) { _, w in
                    let current = w.start == u.weekStart
                    HStack(spacing: 12) {
                        Text(range(w) + (current ? L(" 本周", " this week") : "")).fontWeight(current ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Group {
                            Text(Fmt.usd(w.opus))
                            Text(Fmt.usd(w.total - w.opus))
                            Text(w.total > 0 ? Fmt.pct(w.subagent / w.total * 100) : "-")
                            Text(peak(w))
                        }
                        .foregroundStyle(Theme.sub).frame(width: 120, alignment: .trailing)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.usd(w.total)).fontWeight(.semibold)
                            if current, let f = u.forecastSpend {
                                Text(L("预测 ", "forecast ") + Fmt.usd(f)).font(.system(size: 11)).foregroundStyle(Theme.sub)
                            }
                        }
                        .frame(width: 120, alignment: .trailing).lineLimit(1)
                    }
                    .font(.system(size: 13)).mono()
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    Divider().overlay(Theme.line2)
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
        }
    }

    private func bars(_ weeks: [UsageState.Week]) -> [Bar] {
        weeks.flatMap { w -> [Bar] in
            let label = range(w)
            var out = [Bar(id: label + "o", label: label, kind: "opus", value: w.opus),
                       Bar(id: label + "s", label: label, kind: "other", value: w.total - w.opus)]
            if w.start == u.weekStart, let f = u.forecastSpend, f > w.total {
                out.append(Bar(id: label + "f", label: label, kind: "forecast", value: f - w.total))
            }
            return out
        }
    }

    private func range(_ w: UsageState.Week) -> String { Fmt.monthDay(w.start) + " - " + Fmt.monthDay(w.end) }

    private func peak(_ w: UsageState.Week) -> String {
        guard let p = w.officialPeak, w.officialPeakTrusted ?? true else { return "-" }
        return Fmt.pct(p)
    }
}
