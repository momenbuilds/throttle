import Foundation

/// Shared between the floating pill and the detail panel so tapping a ring
/// on the pill instantly updates the already-open panel's tab — a plain
/// state change, no window repositioning — instead of each owning its own
/// selection and going out of sync.
final class SelectionModel: ObservableObject {
    @Published var selected: ToolUsage.Tool = .claude

    /// The selection clamped to tools that can actually be shown — if the
    /// selected tool isn't visible, fall back to the first one that is.
    static func clamp(_ selected: ToolUsage.Tool, to tools: [ToolUsage.Tool]) -> ToolUsage.Tool {
        tools.contains(selected) ? selected : (tools.first ?? selected)
    }
}
