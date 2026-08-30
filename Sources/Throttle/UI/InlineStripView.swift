import SwiftUI

/// Menu-bar-height strip used when the pill is parked beside the notch:
/// one compact "glyph + percent" pair per visible tool, always visible,
/// reading like a permanent fixture of the menu bar rather than a widget.
/// The percent text carries the status color so urgency reads without rings.
struct InlineStripView: View {
    @ObservedObject var store: UsageStore
    @Binding var selected: ToolUsage.Tool

    var body: some View {
        HStack(spacing: 14) {
            ForEach(store.visibleTools, id: \.self) { tool in
                let item = store.items.first { $0.tool == tool }
                Button {
                    selected = tool
                } label: {
                    HStack(spacing: 4) {
                        BrandMark(tool: tool, size: 15)
                        Text(percentText(item))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(percentColor(item))
                            .monospacedDigit()
                    }
                    .opacity(SelectionModel.clamp(selected, to: store.visibleTools) == tool ? 1 : 0.8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10)))
    }

    private func percentText(_ item: ToolUsage?) -> String {
        guard let item, item.available, let p = item.headlinePercent else { return "—" }
        if p >= 10 { return "\(Int(p))x" }
        return "\(Int(p * 100))%"
    }

    private func percentColor(_ item: ToolUsage?) -> Color {
        guard let item, item.available, let p = item.headlinePercent else {
            return .white.opacity(0.35)
        }
        return p > 1.0 ? .red : StatusColor.forPercent(p)
    }
}
