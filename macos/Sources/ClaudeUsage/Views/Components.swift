import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }
}

/// A thin bar filled to `value` of 1, with an optional tick, such as how much of the week has gone.
struct Meter: View {
    var value: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6
    var tick: Double?

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: g.size.width * min(1, max(0, value)))
                if let tick {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.text.opacity(0.5))
                        .frame(width: 2, height: height + 8)
                        .offset(x: g.size.width * min(1, max(0, tick)) - 1)
                }
            }
        }
        .frame(height: height)
    }
}

struct Dot: View {
    var color: Color = Theme.live
    var size: CGFloat = 6
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

/// A segmented control in the design's style: a grey track, the chosen segment raised.
struct Segmented<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    var height: CGFloat = 24

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button { withAnimation(Theme.ease) { selection = value } } label: {
                    Text(label)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? Theme.text : Theme.sub)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .padding(.horizontal, 10)
                        .background(on ? Theme.segOn : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .shadow(color: .black.opacity(on ? 0.1 : 0), radius: 1, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(Pressable())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Presses scale to 0.97 with the design's ease-out.
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.12), value: configuration.isPressed)
    }
}

struct Badge: View {
    var text: String
    var fg: Color
    var bg: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(bg, in: Capsule())
    }
}

extension Usage.Status {
    @MainActor var badge: Badge? {
        switch self {
        case .normal: return Badge(text: L("进度正常", "On track"), fg: Theme.liveText, bg: Theme.okBg)
        case .early: return Badge(text: L("会提前用满", "Runs out early"), fg: Theme.warnText, bg: Theme.warnBg)
        case .almostFull: return Badge(text: L("快满了", "Almost full"), fg: Theme.danger, bg: Theme.danger.opacity(0.12))
        case .full: return Badge(text: L("已用满", "Full"), fg: Theme.danger, bg: Theme.danger.opacity(0.12))
        }
    }
}

struct InfoIcon: View {
    var body: some View {
        Image(systemName: "info.circle").font(.system(size: 11))
    }
}

/// A section label in the design: 13 pt semibold.
struct SectionTitle: View {
    var text: String
    var body: some View { Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text) }
}

extension View {
    func mono() -> some View { monospacedDigit() }
    func sub(_ size: CGFloat = 12) -> some View { font(.system(size: size)).foregroundStyle(Theme.sub) }
}

/// Columns that split the width by weight and share the tallest column's height, such as a 2:1:1 row of cards.
struct WeightedColumns: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 16

    private func widths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let w = (0..<n).map { $0 < weights.count ? weights[$0] : 1 }
        let free = max(total - spacing * CGFloat(n - 1), 0)
        let sum = w.reduce(0, +)
        return w.map { free * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 900
        let ws = widths(total, subviews.count)
        let h = zip(subviews, ws).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(bounds.width, subviews.count)
        var x = bounds.minX
        for (v, w) in zip(subviews, ws) {
            v.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}

extension EnvironmentValues {
    /// The width the dashboard gives a tab, so wide tables can drop secondary columns on a narrow window.
    @Entry var contentWidth: CGFloat = 1100
}
