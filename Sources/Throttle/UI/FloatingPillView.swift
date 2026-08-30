import SwiftUI

/// Compact always-visible pill anchored to the edge of the screen.
/// Vertical on the side edges, horizontal when parked under the notch.
/// Click a ring to open the full panel.
struct FloatingPillView: View {
    @ObservedObject var store: UsageStore
    @Binding var selected: ToolUsage.Tool
    var horizontal: Bool = false
    /// The edge that remains visible while the pill is tucked away. nil for
    /// the fully visible side profile and for the separate beside-notch strip.
    var usageRailEdge: PillEdge?
    var onSelectRing: () -> Void

    var body: some View {
        ZStack(alignment: railAlignment) {
            RingStripView(store: store, selected: $selected, ringSize: horizontal ? 34 : 40, horizontal: horizontal)
                .padding(contentInsets)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 0.035, green: 0.035, blue: 0.038).opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.09))
                )

            if let usageRailEdge {
                UsageRailView(
                    store: store,
                    axis: usageRailEdge == .top ? .horizontal : .vertical
                )
                .padding(railPaddingEdge, 5)
                .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 4)
    }

    private var railAlignment: Alignment {
        switch usageRailEdge {
        case .top: return .bottom
        case .right: return .leading
        case .left: return .trailing
        default: return .center
        }
    }

    private var railPaddingEdge: Edge.Set {
        switch usageRailEdge {
        case .top: return .bottom
        case .right: return .leading
        case .left: return .trailing
        default: return []
        }
    }

    /// Keep all ring and percentage pixels beyond the 16-point tucked strip.
    /// The exposed edge then contains only the usage rail, with a small clear
    /// gutter between it and the detailed content when the pill expands.
    private var contentInsets: EdgeInsets {
        if horizontal {
            return EdgeInsets(
                top: 10,
                leading: 16,
                bottom: usageRailEdge == .top ? 20 : 10,
                trailing: 16
            )
        }
        return EdgeInsets(
            top: 14,
            leading: usageRailEdge == .right ? 20 : 10,
            bottom: 14,
            trailing: usageRailEdge == .left ? 20 : 10
        )
    }
}

/// The glanceable surface exposed while a floating pill is tucked off-screen.
/// Every visible provider receives equal space; fill length carries the amount
/// and color carries urgency, so neither signal has to work alone.
private struct UsageRailView: View {
    @ObservedObject var store: UsageStore
    let axis: Axis

    private let segmentLength: CGFloat = 26
    private let thickness: CGFloat = 6
    /// Mirror RingStripView's provider grid rather than centering a tighter,
    /// unrelated group. This puts every rail directly under/beside its icon
    /// and gives neighboring providers deliberate breathing room.
    private let providerSpacing: CGFloat = 16
    private let horizontalProviderWidth: CGFloat = 34
    private let verticalProviderHeight: CGFloat = 57

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: providerSpacing) {
                    ForEach(store.visibleTools, id: \.self) { tool in
                        segment(for: tool)
                            .frame(width: segmentLength, height: thickness)
                            .frame(width: horizontalProviderWidth)
                    }
                }
            } else {
                VStack(spacing: providerSpacing) {
                    ForEach(store.visibleTools, id: \.self) { tool in
                        segment(for: tool)
                            .frame(width: thickness, height: segmentLength)
                            .frame(height: verticalProviderHeight)
                    }
                }
                // A vertical provider cell includes its percentage below the
                // ring; lift the rail to the ring's optical center.
                .offset(y: -8)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func segment(for tool: ToolUsage.Tool) -> some View {
        let item = store.items.first { $0.tool == tool }
        UsageRailSegment(item: item, tool: tool, axis: axis)
    }
}

private struct UsageRailSegment: View {
    let item: ToolUsage?
    let tool: ToolUsage.Tool
    let axis: Axis

    private var percent: Double? {
        guard item?.available == true else { return nil }
        return item?.headlinePercent
    }

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, percent ?? 0))
            let status = percent.map(StatusColor.forPercent)

            ZStack(alignment: axis == .horizontal ? .leading : .bottom) {
                Capsule()
                    .fill((status ?? Color.white).opacity(percent == nil ? 0.12 : 0.20))

                if let status, fraction > 0 {
                    Capsule()
                        .fill(status)
                        .frame(
                            width: axis == .horizontal ? geometry.size.width * fraction : geometry.size.width,
                            height: axis == .horizontal ? geometry.size.height : geometry.size.height * fraction
                        )
                }
            }
        }
        .accessibilityLabel(tool.rawValue)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let percent else { return "Usage unavailable" }
        return "\(Int((percent * 100).rounded())) percent used"
    }
}
