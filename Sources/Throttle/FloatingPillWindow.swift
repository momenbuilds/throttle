import AppKit
import SwiftUI
import Combine

/// Which screen edge the floating pill parks on. `.top` parks it as a
/// horizontal strip just under the menu bar, centered on the notch.
enum PillEdge: String, CaseIterable, Identifiable {
    case right, left, top
    var id: String { rawValue }
    var label: String {
        switch self {
        case .right: return "Right edge"
        case .left: return "Left edge"
        case .top: return "Under notch"
        }
    }
}

/// Borderless always-on-top panel showing the same ring strip as the detail
/// panel, so usage is visible at a glance without clicking anything.
///
/// Two placements, two profiles:
/// - Side edges (right default, left optional): vertical strip. In expanded
///   profile it is fully shown and draggable (position persists). In peek
///   profile only a sliver stays on screen and the whole pill slides out on
///   hover, tucking back a moment after the pointer leaves.
/// - Top edge: horizontal strip under the menu bar by the notch — the space
///   most apps never use. Anchored, no dragging.
/// The pill's panel. Overrides constrainFrameRect because peek profile
/// deliberately parks the pill partly off-screen or behind the menu bar —
/// AppKit's default constraint would push it fully visible, defeating the tuck.
final class EdgePanel: NSPanel {
    override func constrainFrameRect(_ frame: NSRect, to screen: NSScreen?) -> NSRect {
        frame
    }
}

final class FloatingPillWindow: NSResponder {
    private let panel: NSPanel
    private var hosting: NSHostingController<FloatingPillView>!
    private let store: UsageStore
    private let selection: SelectionModel
    private var didSizeAndPosition = false
    private var cancellables: Set<AnyCancellable> = []
    private var collapseWork: DispatchWorkItem?
    private var trackingArea: NSTrackingArea?
    var onRingTapped: ((ToolUsage.Tool, NSView) -> Void)?

    private static let originKey = "throttle.pillOrigin"
    /// How much of the pill stays visible in peek profile.
    private static let peekSliver: CGFloat = 16
    private static let gap: CGFloat = 6

    init(store: UsageStore, selection: SelectionModel) {
        self.store = store
        self.selection = selection

        panel = EdgePanel(
            contentRect: NSRect(x: 0, y: 0, width: 60, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // AppKit's window-level shadow follows the rectangular window frame,
        // not our clipped rounded shape — it drew a faint square edge behind
        // the pill. SwiftUI's own .shadow() on the content respects the real
        // alpha-masked shape instead, so the window shadow is off entirely.
        panel.hasShadow = false
        // .statusBar sits above regular floating overlays (other menu-bar-style
        // widgets, revealed system menu bar) so this pill doesn't get covered.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        super.init()

        installContent()
        observeSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not designed in a nib") }

    private var edge: PillEdge { store.pillEdge }
    private var isPeek: Bool { store.pillPeek }
    private var isDraggable: Bool { !isPeek && edge != .top }

    private func installContent() {
        let binding = Binding<ToolUsage.Tool>(
            get: { [weak selection] in selection?.selected ?? .claude },
            set: { [weak self, weak selection] newValue in
                selection?.selected = newValue
                if let self, let view = self.panel.contentView {
                    self.onRingTapped?(newValue, view)
                }
            }
        )

        let content = FloatingPillView(store: store, selected: binding, horizontal: edge == .top, onSelectRing: {})
        if hosting == nil {
            hosting = NSHostingController(rootView: content)
            hosting.sizingOptions = [.preferredContentSize]
            // NSHostingView paints its own opaque background layer independent of
            // whatever SwiftUI draws — clipShape only affects SwiftUI's content, not
            // this layer, so without this the window bounds show through as a
            // square behind the rounded card.
            hosting.view.wantsLayer = true
            hosting.view.layer?.backgroundColor = .clear
            panel.contentViewController = hosting
        } else {
            hosting.rootView = content
        }
        panel.isMovableByWindowBackground = isDraggable
    }

    private func observeSettings() {
        store.$pillEdge
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconfigure() }
            .store(in: &cancellables)
        store.$pillPeek
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconfigure() }
            .store(in: &cancellables)
    }

    /// Settings changed: rebuild content (axis may flip), forget the old
    /// geometry, and re-place the panel for the new configuration.
    private func reconfigure() {
        guard panel.isVisible else { installContent(); didSizeAndPosition = false; return }
        installContent()
        didSizeAndPosition = false
        var size = hosting.view.fittingSize
        if size.width < 1 || size.height < 1 { size = NSSize(width: 60, height: 200) }
        panel.setContentSize(size)
        slide(to: restOrigin(for: size, in: screenFrame), animated: true)
        installTracking()
    }

    /// SwiftUI can't report a real fittingSize until the view has actually been
    /// laid out inside a shown window, so size/position (falling back to a
    /// sane default) only after the first `show()`, not at construction time —
    /// reading fittingSize too early silently produces a zero-size, invisible window.
    private func sizeAndPositionIfNeeded() {
        guard !didSizeAndPosition else { return }
        var size = hosting.view.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: 60, height: 200)
        }
        panel.setContentSize(size)
        didSizeAndPosition = true
        panel.setFrameOrigin(restOrigin(for: size, in: screenFrame))
        panel.alphaValue = 1
        installTracking()
    }

    private var screenFrame: NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Where the pill sits when the pointer isn't on it: tucked to its peek
    /// sliver, or fully placed (saved drag position for the draggable side
    /// profile, anchored otherwise).
    private func restOrigin(for size: NSSize, in frame: NSRect) -> NSPoint {
        if isPeek || edge == .top {
            switch edge {
            case .right:
                return NSPoint(x: frame.maxX - Self.peekSliver, y: frame.midY - size.height / 2)
            case .left:
                return NSPoint(x: frame.minX - size.width + Self.peekSliver, y: frame.midY - size.height / 2)
            case .top:
                return NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - Self.peekSliver)
            }
        }
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let point = NSPointFromString(saved) ?? NSPoint.zero
            // Clamp into the visible frame — a saved position from before the
            // pill grew (or a screen change) used to park it half off-screen.
            let x = min(max(point.x, frame.minX), frame.maxX - size.width)
            let y = min(max(point.y, frame.minY), frame.maxY - size.height)
            return NSPoint(x: x, y: y)
        }
        switch edge {
        case .right: return NSPoint(x: frame.maxX - size.width - Self.gap, y: frame.midY - size.height / 2)
        case .left: return NSPoint(x: frame.minX + Self.gap, y: frame.midY - size.height / 2)
        case .top: return NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - Self.gap)
        }
    }

    /// Where the pill slides to on hover: fully out.
    private func expandedOrigin(for size: NSSize, in frame: NSRect) -> NSPoint {
        switch edge {
        case .right: return NSPoint(x: frame.maxX - size.width - Self.gap, y: frame.midY - size.height / 2)
        case .left: return NSPoint(x: frame.minX + Self.gap, y: frame.midY - size.height / 2)
        case .top: return NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - Self.gap)
        }
    }

    private func slide(to origin: NSPoint, animated: Bool) {
        var frame = panel.frame
        frame.origin = origin
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: hover (peek profile)

    private func installTracking() {
        if let trackingArea { hosting.view.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: hosting.view.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        hosting.view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        collapseWork?.cancel()
        guard isPeek || edge == .top, panel.isVisible else { return }
        slide(to: expandedOrigin(for: panel.frame.size, in: screenFrame), animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isPeek || edge == .top, panel.isVisible else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.slide(to: self.restOrigin(for: self.panel.frame.size, in: self.screenFrame), animated: true)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    // MARK: visibility

    func show() {
        if !didSizeAndPosition { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        sizeAndPositionIfNeeded()
        observeMoves()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    private func observeMoves() {
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self else { return }
            // Only the draggable side-edge profile has a meaningful position;
            // peek/top are anchored.
            if self.isDraggable {
                UserDefaults.standard.set(NSStringFromPoint(self.panel.frame.origin), forKey: Self.originKey)
            }
        }
    }
}
