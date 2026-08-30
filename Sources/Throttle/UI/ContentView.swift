import SwiftUI

extension Notification.Name {
    static let claudeBarTogglePill = Notification.Name("claudeBarTogglePill")
}

private let panelBackground = Color(red: 0.055, green: 0.055, blue: 0.06)
private let panelCornerRadius: CGFloat = 22

struct ContentView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var selection: SelectionModel
    @State private var showSettings = false
    @State private var pillVisible = UserDefaults.standard.object(forKey: "throttle.pillVisible") as? Bool ?? true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Throttle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))

                Button {
                    pillVisible.toggle()
                    NotificationCenter.default.post(name: .claudeBarTogglePill, object: nil, userInfo: ["visible": pillVisible])
                } label: {
                    Image(systemName: pillVisible ? "pin.fill" : "pin.slash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help(pillVisible ? "Hide floating widget" : "Show floating widget")

                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if showSettings {
                SettingsView(store: store)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                detailCard
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }

            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: panelCornerRadius).fill(panelBackground))
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 6)
    }

    private var currentItem: ToolUsage? {
        store.items.first { $0.tool == selection.selected }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(ToolUsage.Tool.allCases, id: \.self) { tool in
                    let item = store.items.first { $0.tool == tool }
                    Button {
                        selection.selected = tool
                    } label: {
                        HStack(spacing: 6) {
                            BrandMark(tool: tool, size: 20)
                            Text(tool.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .fixedSize()
                        }
                        .foregroundStyle(selection.selected == tool ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(selection.selected == tool ? Color.white.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        if let p = item?.sessionPercent, item?.available == true {
                            Circle()
                                .fill(p > 1.0 ? .red : StatusColor.forPercent(p))
                                .frame(width: 6, height: 6)
                                .offset(x: -2, y: 2)
                        }
                    }
                }
            }

            if let item = currentItem, item.available {
                BarRow(title: "Current session", percent: item.sessionPercent, resetsLabel: item.sessionResetsLabel)
                BarRow(title: item.tool == .claude ? "All models" : "Weekly limit", percent: item.weeklyPercent, resetsLabel: item.weeklyResetsLabel)
                if store.showFableUsage, let fable = item.fableWeeklyPercent {
                    BarRow(title: item.fableWeeklyLabel ?? "Fable 5", percent: fable, resetsLabel: item.fableWeeklyResetsLabel)
                }
                if let note = item.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(currentItem?.note ?? "Not available")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07)))
    }
}

/// Compact ring strip used by the floating pill only — the popover uses tabs
/// instead so the same rings aren't shown twice at once.
struct RingStripView: View {
    @ObservedObject var store: UsageStore
    @Binding var selected: ToolUsage.Tool
    var ringSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 16) {
            ForEach(ToolUsage.Tool.allCases, id: \.self) { tool in
                let item = store.items.first { $0.tool == tool }
                Button {
                    selected = tool
                } label: {
                    VStack(spacing: 4) {
                        RingView(percent: item?.sessionPercent, tool: tool, size: ringSize)
                            .opacity(selected == tool ? 1 : 0.6)
                        if item?.available == true, let p = item?.sessionPercent {
                            Text(compactPercent(p))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(p > 1.0 ? .red : .white.opacity(0.85))
                        } else {
                            Text("—")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private func compactPercent(_ p: Double) -> String {
        if p >= 10 { return "\(Int(p))x" }
        return "\(Int(p * 100))%"
    }
}

