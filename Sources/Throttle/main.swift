import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var detailPanel: DetailPanelWindow!
    private var pillWindow: FloatingPillWindow!
    private let store = UsageStore()
    private let selection = SelectionModel()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Throttle")
            button.imagePosition = .imageLeading
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        detailPanel = DetailPanelWindow(store: store, selection: selection)

        pillWindow = FloatingPillWindow(store: store, selection: selection)
        pillWindow.onRingTapped = { [weak self] _, view in
            guard let self else { return }
            // Tapping a ring already updated `selection` directly (see
            // FloatingPillWindow's binding) — if the panel is already open
            // that's all that needs to happen, no window repositioning.
            guard !detailPanel.isShown else { return }
            store.refresh()
            detailPanel.show(relativeTo: view.bounds, of: view, preferOnLeft: true)
        }
        if UserDefaults.standard.object(forKey: Self.pillVisibleKey) as? Bool ?? true {
            pillWindow.show()
        }
        NotificationCenter.default.addObserver(forName: .claudeBarTogglePill, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let visible = (note.userInfo?["visible"] as? Bool) ?? true
            UserDefaults.standard.set(visible, forKey: Self.pillVisibleKey)
            if visible { self.pillWindow.show() } else { self.pillWindow.hide() }
        }

        updateStatusTitle()
        cancellable = store.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateStatusTitle()
        }
    }

    private static let pillVisibleKey = "throttle.pillVisible"

    // One session percent per signed-in Claude account, in account order
    // (main · B · C), each tinted by its own status color. Accounts without
    // a token just don't contribute a segment.
    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        let font = NSFont.menuBarFont(ofSize: 0)
        let claudeItems = store.items.filter { $0.tool.isClaudeAccount && $0.available && $0.sessionPercent != nil }
        guard !claudeItems.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        let title = NSMutableAttributedString(string: " ")
        for (index, item) in claudeItems.enumerated() {
            guard let percent = item.sessionPercent else { continue }
            if index > 0 {
                title.append(NSAttributedString(
                    string: "·",
                    attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: font]
                ))
            }
            let clamped = min(999, Int(percent * 100))
            let color = percent > 1.0 ? NSColor.red : NSColor(StatusColor.forPercent(percent))
            title.append(NSAttributedString(
                string: "\(clamped)%",
                attributes: [.foregroundColor: color, .font: font]
            ))
        }
        button.attributedTitle = title
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }
        if detailPanel.isShown {
            detailPanel.hide()
        } else {
            store.refresh()
            detailPanel.show(relativeTo: button.bounds, of: button, preferOnLeft: false)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
