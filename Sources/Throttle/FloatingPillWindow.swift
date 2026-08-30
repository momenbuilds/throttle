import AppKit
import SwiftUI
import Combine

/// Which screen edge the floating pill parks on. `.top` parks it as a
/// horizontal strip centered under the notch; `.notchLeft` parks it in the
/// menu bar's free space to the left of the notch, with a gap off its flank.
enum PillEdge: String, CaseIterable, Identifiable {
    case right, left, top, notchLeft = "notchLeft"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .top: return "Under"
        case .notchLeft: return "Beside"
        }
    }
    /// Top placements anchor under the menu bar and slide on hover even when
    /// the peek profile itself is off.
    var isTopEdge: Bool { self == .top || self == .notchLeft }
}

/// Borderless always-on-top panel showing the same ring strip as the detail
/// panel, so usage is visible at a glance without clicking anything.
///
/// Two placements, two profiles:
/// - Side edges (right default, left optional): vertical strip. In expanded
///   profile it is fully shown and draggable (position persists). In peek
///   profile only a sliver stays on screen and the whole pill slides out on
///   hover, tucking back a moment after the pointer leaves.
/// - Under notch (.top): horizontal pill below the menu bar, peeking as a
///   sliver and sliding down on hover. Anchored, no dragging.
/// - Beside notch (.notchLeft): a menu-bar-height inline strip in the dead
///   space left of the notch — glyph + percent pairs, always visible.
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
    private lazy var inlineHosting: NSHostingController<InlineStripView> = {
        let controller = NSHostingController(rootView: InlineStripView(store: store, selected: Binding(get: { [weak selection] in selection?.selected ?? .claude }, set: { [weak selection] in selection?.selected = $0 })))
        controller.sizingOptions = [.preferredContentSize]
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = .clear
        return controller
    }()
    private let store: UsageStore
    private let selection: SelectionModel
    private var didSizeAndPosition = false
    private var cancellables: Set<AnyCancellable> = []
    private var collapseWork: DispatchWorkItem?
    private var trackingArea: NSTrackingArea?
    /// Hover card (beside-notch mode): appears under the strip on mouse-over.
    private var hoverPanel: NSPanel?
    private var hoverHosting: NSHostingController<HoverDetailView>?
    private var hoverTrackingArea: NSTrackingArea?
    private var hideHoverWork: DispatchWorkItem?
    var onRingTapped: ((ToolUsage.Tool, NSView) -> Void)?

    private static let originKey = "throttle.pillOrigin"
    /// How much of the pill stays visible in peek profile.
    private static let peekSliver: CGFloat = 16
    private static let gap: CGFloat = 6
    /// Breathing room between the pill and the notch itself.
    private static let notchGap: CGFloat = 30
    /// Menu bar band height (also the inline strip's window height).
    private static let menuBarHeight: CGFloat = 32

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
    private var isDraggable: Bool { !isPeek && !edge.isTopEdge }

    /// The under-notch peek pill tucks behind the menu bar, and the menu bar
    /// only covers windows below its own level — so that mode sits at
    /// .floating. The beside-notch strip deliberately draws over the menu
    /// bar's dead space, so it (like the side pills) sits at .statusBar.
    private func applyLevel() {
        panel.level = edge == .top ? .floating : .statusBar
    }

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

        // NSHostingView paints its own opaque background layer independent of
        // whatever SwiftUI draws — clipShape only affects SwiftUI's content, not
        // this layer, so without this the window bounds show through as a
        // square behind the rounded card.
        if edge == .notchLeft {
            inlineHosting.rootView = InlineStripView(store: store, selected: binding)
            panel.contentViewController = inlineHosting
        } else {
            let usageRailEdge: PillEdge? = edge == .top || isPeek ? edge : nil
            let content = FloatingPillView(
                store: store,
                selected: binding,
                horizontal: edge == .top,
                usageRailEdge: usageRailEdge,
                onSelectRing: {}
            )
            if hosting == nil {
                hosting = NSHostingController(rootView: content)
                hosting.sizingOptions = [.preferredContentSize]
                hosting.view.wantsLayer = true
                hosting.view.layer?.backgroundColor = .clear
            } else {
                hosting.rootView = content
            }
            panel.contentViewController = hosting
        }
        panel.isMovableByWindowBackground = isDraggable
        applyLevel()
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
        store.$items
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // @Published emits before SwiftUI lays out the new percent
                // strings. Re-measure on the next run-loop turn so a wider
                // value cannot grow toward the notch and consume its gap.
                DispatchQueue.main.async { self?.reanchorInlineStrip() }
            }
            .store(in: &cancellables)
    }

    private func reanchorInlineStrip() {
        guard edge == .notchLeft, panel.isVisible, let contentView = panel.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let size = contentView.fittingSize
        guard size.width >= 1, size.height >= 1 else { return }
        panel.setContentSize(size)
        panel.setFrameOrigin(restOrigin(for: size, in: screenFrame))
        installTracking()
    }

    /// Settings changed: rebuild content (axis may flip), forget the old
    /// geometry, and re-place the panel for the new configuration.
    private func reconfigure() {
        guard panel.isVisible else { installContent(); didSizeAndPosition = false; return }
        installContent()
        didSizeAndPosition = false
        var size = panel.contentView?.fittingSize ?? NSSize.zero
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
        // The active controller differs by mode (pill vs inline strip), so
        // measure whatever view is actually installed.
        var size = panel.contentView?.fittingSize ?? NSSize.zero
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

    private var screenTop: CGFloat {
        NSScreen.main?.frame.maxY ?? 900
    }

    /// Where the pill sits when the pointer isn't on it: tucked to its peek
    /// sliver, or fully placed (saved drag position for the draggable side
    /// profile, anchored otherwise).
    private func restOrigin(for size: NSSize, in frame: NSRect) -> NSPoint {
        if edge == .notchLeft {
            // The inline strip lives inside the menu bar band itself: its
            // right edge stops `notchGap` short of the notch, vertically
            // centered in the bar. There is no tucked state.
            // Center whatever height the strip reports inside the 32pt band.
            return NSPoint(x: notchLeftX(for: size, in: frame), y: screenTop - (Self.menuBarHeight + size.height) / 2)
        }
        if isPeek || edge == .top {
            switch edge {
            case .right:
                return NSPoint(x: frame.maxX - Self.peekSliver, y: frame.midY - size.height / 2)
            case .left:
                return NSPoint(x: frame.minX - size.width + Self.peekSliver, y: frame.midY - size.height / 2)
            case .top:
                return NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - Self.peekSliver)
            case .notchLeft:
                return NSPoint(x: notchLeftX(for: size, in: frame), y: frame.maxY - Self.peekSliver)
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
        case .notchLeft: return NSPoint(x: notchLeftX(for: size, in: frame), y: frame.maxY - size.height - Self.gap)
        }
    }

    /// Where the pill slides to on hover: fully out.
    private func expandedOrigin(for size: NSSize, in frame: NSRect) -> NSPoint {
        switch edge {
        case .right: return NSPoint(x: frame.maxX - size.width - Self.gap, y: frame.midY - size.height / 2)
        case .left: return NSPoint(x: frame.minX + Self.gap, y: frame.midY - size.height / 2)
        case .top: return NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - Self.gap)
        case .notchLeft: return NSPoint(x: notchLeftX(for: size, in: frame), y: frame.maxY - size.height - Self.gap)
        }
    }

    /// The pill's left x when parked left of the notch: its right edge stops
    /// `notchGap` short of the notch's flank (auxiliaryTopLeftArea is the
    /// menu-bar region flanking the notch). Screens without a notch fall
    /// back to the top-right corner.
    private func notchLeftX(for size: NSSize, in frame: NSRect) -> CGFloat {
        if let flank = NSScreen.main?.auxiliaryTopLeftArea {
            return flank.maxX - size.width - Self.notchGap
        }
        return frame.maxX - size.width - Self.gap
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
        guard let contentView = panel.contentView else { return }
        if let trackingArea { contentView.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        collapseWork?.cancel()
        guard panel.isVisible else { return }
        if edge == .notchLeft {
            hideHoverWork?.cancel()
            showHoverCard()
            return
        }
        guard edge == .top || (isPeek && !edge.isTopEdge) else { return }
        slide(to: expandedOrigin(for: panel.frame.size, in: screenFrame), animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard panel.isVisible else { return }
        if edge == .notchLeft {
            // Hide only once the pointer has left both the strip and the
            // card itself — moving from one to the other keeps it alive.
            let work = DispatchWorkItem { [weak self] in self?.hideHoverCard() }
            hideHoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            return
        }
        guard edge == .top || (isPeek && !edge.isTopEdge) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.slide(to: self.restOrigin(for: self.panel.frame.size, in: self.screenFrame), animated: true)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    // MARK: hover card (beside-notch)

    private func showHoverCard() {
        if let cardPanel = hoverPanel, cardPanel.isVisible { return }
        let hosting: NSHostingController<HoverDetailView>
        if let hoverHosting {
            hosting = hoverHosting
        } else {
            hosting = NSHostingController(rootView: HoverDetailView(store: store))
            hosting.sizingOptions = [.preferredContentSize]
            hosting.view.wantsLayer = true
            hosting.view.layer?.backgroundColor = .clear
            hoverHosting = hosting
        }

        let cardPanel: NSPanel
        if let hoverPanel {
            cardPanel = hoverPanel
        } else {
            cardPanel = EdgePanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            cardPanel.isOpaque = false
            cardPanel.backgroundColor = .clear
            cardPanel.hasShadow = false
            cardPanel.level = .floating
            cardPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            cardPanel.hidesOnDeactivate = false
            cardPanel.contentViewController = hosting
            hoverPanel = cardPanel
        }

        var size = hosting.view.fittingSize
        if size.width < 1 || size.height < 1 { size = NSSize(width: 320, height: 160) }
        cardPanel.setContentSize(size)
        // Align the card's left edge with the strip, hanging just below the
        // menu bar band; slide up a touch on fade-in so it reads as growing
        // out of the bar.
        let strip = panel.frame
        let x = max(strip.minX, screenFrame.minX + 4)
        let y = screenTop - Self.menuBarHeight - size.height - 8
        let finalFrame = NSRect(x: x, y: y, width: size.width, height: size.height)
        cardPanel.setFrame(finalFrame.offsetBy(dx: 0, dy: 10), display: false)
        cardPanel.alphaValue = 0
        cardPanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            cardPanel.animator().setFrame(finalFrame, display: true)
            cardPanel.animator().alphaValue = 1
        }

        // Keep the card alive while the pointer is inside it.
        if hoverTrackingArea == nil, let content = cardPanel.contentView {
            let area = NSTrackingArea(
                rect: content.bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil
            )
            content.addTrackingArea(area)
            hoverTrackingArea = area
        }
    }

    private func hideHoverCard() {
        guard let cardPanel = hoverPanel, cardPanel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            cardPanel.animator().alphaValue = 0
        }, completionHandler: {
            cardPanel.orderOut(nil)
        })
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
        hideHoverCard()
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
