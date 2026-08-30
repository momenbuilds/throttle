import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
                Toggle("Notify at 90% used", isOn: $store.notificationsEnabled)
                Toggle("Show Fable 5 usage", isOn: $store.showFableUsage)
            }
            .toggleStyle(.switch)
            .tint(.green)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 8) {
                Text("Tools")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Tools are shown automatically while they're installed on this Mac. Turn one on to show it even when it isn't detected — Gemini has no local usage source today.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(ToolUsage.Tool.allCases, id: \.self) { tool in
                    let detected = ToolPresence.isPresent(tool)
                    Toggle(isOn: Binding(
                        get: { detected || store.activatedTools.contains(tool) },
                        set: { store.setToolActivated(tool, $0) }
                    )) {
                        HStack(spacing: 6) {
                            BrandMark(tool: tool, size: 14, color: .white.opacity(0.85))
                            Text(tool.rawValue)
                            if detected {
                                Text("detected")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    .disabled(detected)
                    .help(detected ? "Installed on this Mac — always shown" : "Not detected locally")
                }
            }
            .toggleStyle(.switch)
            .tint(.green)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 8) {
                Text("Floating pill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Picker("Position", selection: $store.pillEdge) {
                    ForEach(PillEdge.allCases) { edge in
                        Text(edge.label).tag(edge)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle("Low profile — peek until hover", isOn: $store.pillPeek)
                Text("Under notch parks the pill horizontally just below the menu bar. Low profile keeps a sliver visible and slides the pill out when the pointer reaches it.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            .tint(.green)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 10) {
                Text("Calibrate Claude budget")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Claude usage shows live numbers from your Anthropic account whenever you're signed in via `claude login`. This budget only matters as a fallback if that sign-in isn't available — it estimates a dollar cost from local token counts instead.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                limitField(label: "Fallback session budget (5h, $)", value: $store.sessionBudget)
                limitField(label: "Fallback weekly budget ($)", value: $store.weeklyBudget)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07)))
    }

    private func limitField(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.6))
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }
}
