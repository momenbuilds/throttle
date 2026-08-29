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
