import SwiftUI

/// Compact per-provider usage card that appears when the pointer rests on the
/// inline strip — no click needed. One row per visible tool with mini bars for
/// each window the provider actually reports (session / weekly). Mouse away
/// and it fades; click the strip for the full persistent panel.
struct HoverDetailView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.visibleTools, id: \.self) { tool in
                let item = store.items.first { $0.tool == tool }
                row(for: tool, item: item)
            }
            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.035, green: 0.035, blue: 0.038).opacity(0.96))
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.09)))
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 6)
    }

    @ViewBuilder
    private func row(for tool: ToolUsage.Tool, item: ToolUsage?) -> some View {
        HStack(spacing: 8) {
            BrandMark(tool: tool, size: 16)
            Text(tool.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            miniBar(label: "5h", percent: item?.sessionPercent)
            miniBar(label: "wk", percent: item?.weeklyPercent)
        }
        .opacity(item?.available == true ? 1 : 0.55)
    }

    private func miniBar(label: String, percent: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 16, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    if let percent {
                        Capsule()
                            .fill(percent > 1.0 ? Color.red : StatusColor.forPercent(percent))
                            .frame(width: max(3, geo.size.width * min(1, percent)))
                    }
                }
            }
            .frame(width: 56, height: 5)
            Text(percentText(percent))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(percent.map { $0 > 1.0 ? Color.red : Color.white.opacity(0.8) } ?? Color.white.opacity(0.3))
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func percentText(_ p: Double?) -> String {
        guard let p else { return "—" }
        if p >= 10 { return "\(Int(p))x" }
        return "\(Int(p * 100))%"
    }
}
