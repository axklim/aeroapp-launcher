import AppKit

/// One line in the results list.
struct OverlayRow: Equatable {
    let app: InstalledApp
    /// Right-aligned hint — the app's hotkey, if it has one.
    let detail: String
}

protocol OverlayDataSource: AnyObject {
    func overlayResults(for query: String) -> [OverlayRow]
    func overlayDidSelect(_ row: OverlayRow)
}

// MARK: - Panel

/// A borderless panel that can take keyboard focus without activating the app,
/// so the app that was frontmost stays frontmost — AeroSpace never sees a focus
/// change it would have to react to.
private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Results list

private final class ResultsView: NSView {
    static let rowHeight: CGFloat = 46
    static let maxVisibleRows = 8
    static let verticalPadding: CGFloat = 6
    static let horizontalInset: CGFloat = 8
    static let iconSize: CGFloat = 32

    var onClick: ((Int) -> Void)?

    private(set) var rows: [OverlayRow] = []
    private(set) var selected = 0
    private var firstVisible = 0
    private var iconCache: [String: NSImage] = [:]

    override var isFlipped: Bool { true }

    var visibleRowCount: Int { min(rows.count, Self.maxVisibleRows) }

    var preferredHeight: CGFloat {
        rows.isEmpty ? 0 : CGFloat(visibleRowCount) * Self.rowHeight + 2 * Self.verticalPadding
    }

    func set(rows: [OverlayRow], selected: Int) {
        self.rows = rows
        self.selected = rows.isEmpty ? 0 : min(max(selected, 0), rows.count - 1)
        firstVisible = 0
        scrollToSelection()
        needsDisplay = true
    }

    func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        let count = rows.count
        selected = ((selected + delta) % count + count) % count
        scrollToSelection()
        needsDisplay = true
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selected = index
        scrollToSelection()
        needsDisplay = true
    }

    private func scrollToSelection() {
        if selected < firstVisible {
            firstVisible = selected
        } else if selected >= firstVisible + Self.maxVisibleRows {
            firstVisible = selected - Self.maxVisibleRows + 1
        }
    }

    private func rowRect(visibleIndex: Int) -> NSRect {
        NSRect(
            x: Self.horizontalInset,
            y: Self.verticalPadding + CGFloat(visibleIndex) * Self.rowHeight,
            width: bounds.width - 2 * Self.horizontalInset,
            height: Self.rowHeight
        )
    }

    private func icon(for app: InstalledApp) -> NSImage {
        if let cached = iconCache[app.url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: Self.iconSize, height: Self.iconSize)
        iconCache[app.url.path] = image
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }
        let end = min(rows.count, firstVisible + Self.maxVisibleRows)

        for index in firstVisible..<end {
            let rect = rowRect(visibleIndex: index - firstVisible)
            let row = rows[index]

            if index == selected {
                // Accent-tinted rather than translucent white: the panel material is
                // light in light mode, where white on white is invisible.
                let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).setFill()
                path.fill()
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            let iconRect = NSRect(
                x: rect.minX + 10,
                y: rect.minY + (rect.height - Self.iconSize) / 2,
                width: Self.iconSize,
                height: Self.iconSize
            )
            // This view is flipped for the layout maths, and NSImage.draw does not
            // honour that by default — without respectFlipped the icons render
            // upside down.
            icon(for: row.app).draw(
                in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )

            let detailFont = NSFont.systemFont(ofSize: 12, weight: .regular)
            let detailWidth = row.detail.isEmpty
                ? 0
                : ceil((row.detail as NSString).size(withAttributes: [.font: detailFont]).width)
            if detailWidth > 0 {
                let height = ceil(detailFont.ascender - detailFont.descender)
                let detailRect = NSRect(
                    x: rect.maxX - 12 - detailWidth,
                    y: rect.minY + (rect.height - height) / 2,
                    width: detailWidth,
                    height: height
                )
                (row.detail as NSString).draw(in: detailRect, withAttributes: [
                    .font: detailFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ])
            }

            let nameFont = NSFont.systemFont(ofSize: 15, weight: .medium)
            let nameHeight = ceil(nameFont.ascender - nameFont.descender)
            let nameX = iconRect.maxX + 12
            let nameRect = NSRect(
                x: nameX,
                y: rect.minY + (rect.height - nameHeight) / 2,
                width: max(0, rect.maxX - 12 - (detailWidth > 0 ? detailWidth + 12 : 0) - nameX),
                height: nameHeight
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (row.app.name as NSString).draw(in: nameRect, withAttributes: [
                .font: nameFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for visibleIndex in 0..<visibleRowCount where rowRect(visibleIndex: visibleIndex).contains(point) {
            onClick?(firstVisible + visibleIndex)
            return
        }
    }
}

// MARK: - Overlay

final class Overlay: NSObject, NSTextFieldDelegate {
    weak var dataSource: OverlayDataSource?

    private static let width: CGFloat = 640
    private static let fieldHeight: CGFloat = 58
    private static let cornerRadius: CGFloat = 14
    private static let horizontalPadding: CGFloat = 20

    private var panel: LauncherPanel?
    private let container = FlippedView()
    private let field = NSTextField()
    private let separator = NSBox()
    private let results = ResultsView()

    /// Kept while the panel is up so a size change grows it downwards, keeping the
    /// search field where it was.
    private var top: CGFloat = 0
    private var left: CGFloat = 0

    private(set) var isVisible = false

    // MARK: Showing and hiding

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = makePanel()

        // Prefer the screen under the pointer: the AeroSpace config moves the mouse
        // to the focused monitor, so this tracks the monitor you are working on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        top = visible.maxY - visible.height * 0.2
        left = visible.midX - Self.width / 2

        field.stringValue = ""
        requery(selecting: 0)

        isVisible = true
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        // End editing so the next show starts with a fresh field editor.
        panel?.makeFirstResponder(nil)
        panel?.orderOut(nil)
    }

    /// Re-runs the current query — for when the app index or config changed
    /// underneath an open panel.
    func refresh() {
        guard isVisible else { return }
        requery(selecting: results.selected)
    }

    // MARK: Panel construction

    /// A rounded-rect stencil stretched from its centre, so one small image
    /// masks the material at any panel size.
    private static func cornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func makePanel() -> LauncherPanel {
        if let panel { return panel }

        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.fieldHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        // The behind-window backdrop is composited by the window server, which
        // honours maskImage but not the layer's corner radius — with only the
        // latter the blur stays square, which is invisible against a dark
        // desktop but shows as bright square corners against a light one.
        effect.maskImage = Self.cornerMask(radius: Self.cornerRadius)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.masksToBounds = true

        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .regular)
        field.textColor = .labelColor
        field.placeholderAttributedString = NSAttributedString(
            string: "Launch app",
            attributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = self

        separator.boxType = .separator

        results.onClick = { [weak self] index in
            self?.results.select(index)
            self?.commit()
        }

        container.addSubview(field)
        container.addSubview(separator)
        container.addSubview(results)
        effect.addSubview(container)
        panel.contentView = effect

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidResignKey), name: NSWindow.didResignKeyNotification, object: panel
        )

        self.panel = panel
        return panel
    }

    @objc private func panelDidResignKey() {
        // Clicking anywhere else dismisses the launcher, like Spotlight.
        hide()
    }

    private func layOut() {
        guard let panel else { return }
        let listHeight = results.preferredHeight
        let height = Self.fieldHeight + (listHeight > 0 ? 1 + listHeight : 0)

        panel.setFrame(NSRect(x: left, y: top - height, width: Self.width, height: height), display: true)
        container.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)

        let fieldLineHeight: CGFloat = 32
        field.frame = NSRect(
            x: Self.horizontalPadding,
            y: (Self.fieldHeight - fieldLineHeight) / 2,
            width: Self.width - 2 * Self.horizontalPadding,
            height: fieldLineHeight
        )
        separator.isHidden = listHeight == 0
        separator.frame = NSRect(x: 0, y: Self.fieldHeight, width: Self.width, height: 1)
        results.frame = NSRect(x: 0, y: Self.fieldHeight + 1, width: Self.width, height: listHeight)

        // The shadow is cached from the previous content shape; without this the
        // panel keeps the outline it had at its last size.
        panel.invalidateShadow()
    }

    // MARK: Querying and committing

    private func requery(selecting index: Int) {
        let rows = dataSource?.overlayResults(for: field.stringValue) ?? []
        results.set(rows: rows, selected: index)
        layOut()
    }

    private func commit() {
        guard results.rows.indices.contains(results.selected) else {
            hide()
            return
        }
        let row = results.rows[results.selected]
        hide()
        dataSource?.overlayDidSelect(row)
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        requery(selecting: 0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)):
            results.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)):
            results.moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            commit()
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
        default:
            return false
        }
        return true
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
