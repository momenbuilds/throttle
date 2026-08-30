import SwiftUI
import AppKit

/// Each provider's actual mark, loaded from bundled PNGs (Resources/Brand) —
/// sourced from lobehub/lobe-icons (MIT licensed), which ships these exact
/// monochrome marks specifically for representing AI providers in UI like this.
/// Rasterized via QuickLook's SVG renderer rather than loaded as SVG directly:
/// AppKit's own NSImage SVG loader doesn't honor fill-rule="evenodd" correctly
/// and rendered Gemini's self-overlapping path as a near-invisible sliver.
struct BrandMark: View {
    let tool: ToolUsage.Tool
    var size: CGFloat = 18
    var color: Color = .white

    var body: some View {
        Group {
            if let nsImage = Self.image(for: tool) {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback if the bundled asset is somehow missing.
                Image(systemName: "sparkle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
    }

    private static var cache: [ToolUsage.Tool: NSImage] = [:]

    private static func image(for tool: ToolUsage.Tool) -> NSImage? {
        if let cached = cache[tool] { return cached }
        let name: String
        switch tool {
        case .claude: name = "claude"
        case .codex: name = "openai"
        case .gemini: name = "gemini"
        case .zcode: name = "zcode"
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Brand"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        cache[tool] = image
        return image
    }
}
