import AppKit

final class TerminalVerticalTabBar: NSVisualEffectView {
    enum Position {
        case left
        case right
    }

    static let width: CGFloat = 180
    static let rowHeight: CGFloat = 32

    private weak var hostWindow: TerminalWindow?
    let position: Position
    private let stackView = NSStackView()
    private let scrollView = NSScrollView()
    private let separator = NSBox()
    private let newTabButton = NSButton()
    private let dropIndicator = NSView()
    private var dropIndicatorTopConstraint: NSLayoutConstraint?

    var preferredWidth: CGFloat { Self.width }

    init(hostWindow: TerminalWindow, position: Position) {
        self.hostWindow = hostWindow
        self.position = position
        super.init(frame: .zero)

        setup()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let hostWindow else { return }
        let windows = hostWindow.tabGroup?.windows ?? [hostWindow]
        let selectedWindow = hostWindow.tabGroup?.selectedWindow ?? hostWindow

        for (index, window) in windows.enumerated() {
            let item = TerminalVerticalTabButton(
                title: tabTitle(for: window, index: index),
                isSelected: window === selectedWindow,
                targetWindow: window,
                hostWindow: hostWindow,
                tabBar: self
            )
            stackView.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        isHidden = false
    }

    fileprivate func dropIndex(for event: NSEvent) -> Int? {
        guard let documentView = scrollView.documentView else { return nil }
        return dropIndex(
            forDocumentLocation: documentView.convert(event.locationInWindow, from: nil),
            in: documentView
        )
    }

    private func dropIndex(forDocumentLocation location: NSPoint, in documentView: NSView) -> Int {
        for (index, view) in stackView.arrangedSubviews.enumerated() {
            let frame = stackView.convert(view.frame, to: documentView)
            if location.y < frame.midY {
                return index
            }
        }

        return stackView.arrangedSubviews.count
    }

    fileprivate func showDropIndicator(for event: NSEvent) {
        guard let documentView = scrollView.documentView else { return }
        let location = documentView.convert(event.locationInWindow, from: nil)
        let dropIndex = dropIndex(forDocumentLocation: location, in: documentView)

        let documentY: CGFloat
        if stackView.arrangedSubviews.isEmpty {
            documentY = stackView.convert(stackView.bounds, to: documentView).minY
        } else if dropIndex >= stackView.arrangedSubviews.count {
            documentY = stackView.convert(stackView.arrangedSubviews.last!.frame, to: documentView).maxY + stackView.spacing / 2
        } else {
            documentY = stackView.convert(stackView.arrangedSubviews[dropIndex].frame, to: documentView).minY - stackView.spacing / 2
        }

        let indicatorY = convert(documentView.convert(NSPoint(x: 0, y: documentY), to: nil), from: nil).y
        dropIndicatorTopConstraint?.constant = bounds.maxY - indicatorY
        dropIndicator.isHidden = false
    }

    fileprivate func hideDropIndicator() {
        dropIndicator.isHidden = true
    }

    fileprivate func moveTab(_ window: NSWindow, toDropIndex dropIndex: Int) {
        guard let hostWindow,
              let tabGroup = hostWindow.tabGroup
        else { return }

        let windows = tabGroup.windows
        guard windows.count > 1,
              let fromIndex = windows.firstIndex(where: { $0 === window })
        else { return }

        var insertionIndex = min(max(dropIndex, 0), windows.count)
        if insertionIndex > fromIndex {
            insertionIndex -= 1
        }
        guard insertionIndex != fromIndex else { return }

        var remainingWindows = windows
        remainingWindows.remove(at: fromIndex)
        guard !remainingWindows.isEmpty else { return }

        insertionIndex = min(max(insertionIndex, 0), remainingWindows.count)
        let referenceWindow: NSWindow
        let ordering: NSWindow.OrderingMode
        if insertionIndex == 0 {
            referenceWindow = remainingWindows[0]
            ordering = .below
        } else {
            referenceWindow = remainingWindows[insertionIndex - 1]
            ordering = .above
        }

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        defer { NSAnimationContext.endGrouping() }

        tabGroup.removeWindow(window)
        referenceWindow.addTabbedWindowSafely(window, ordered: ordering)
        window.makeKeyAndOrderFront(nil)
        (window.windowController as? TerminalController)?.relabelTabs()
    }

    private func setup() {
        material = .sidebar
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)
        scrollView.documentView = documentView

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.bezelStyle = .rounded
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.imagePosition = .imageOnly
        newTabButton.toolTip = "New Tab"
        newTabButton.target = self
        newTabButton.action = #selector(newTab)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        contentView.addSubview(scrollView)
        contentView.addSubview(newTabButton)
        contentView.addSubview(separator)
        addSubview(dropIndicator)
        dropIndicator.translatesAutoresizingMaskIntoConstraints = false
        dropIndicator.wantsLayer = true
        dropIndicator.layer?.cornerRadius = 1
        dropIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dropIndicator.isHidden = true

        dropIndicatorTopConstraint = dropIndicator.topAnchor.constraint(equalTo: topAnchor)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),

            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: newTabButton.topAnchor, constant: -6),

            newTabButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            newTabButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            newTabButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            newTabButton.heightAnchor.constraint(equalToConstant: 28),

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),

            dropIndicatorTopConstraint!,
            dropIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dropIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dropIndicator.heightAnchor.constraint(equalToConstant: 2),
        ])

        switch position {
        case .left:
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: contentView.topAnchor),
                separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),
            ])
        case .right:
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: contentView.topAnchor),
                separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),
            ])
        }
    }

    private func tabTitle(for window: NSWindow, index: Int) -> String {
        let rawTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTitle.isEmpty {
            return "Tab \(index + 1)"
        }

        return "\(index + 1)  \(rawTitle)"
    }

    @objc private func newTab() {
        guard let hostWindow,
              let controller = hostWindow.windowController as? TerminalController,
              let surface = controller.focusedSurface?.surface
        else { return }

        controller.ghostty.newTab(surface: surface)
    }
}

private final class TerminalVerticalTabButton: NSView {
    private weak var targetWindow: NSWindow?
    private weak var hostWindow: TerminalWindow?
    private weak var tabBar: TerminalVerticalTabBar?
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let selectedIndicator = NSView()
    private var isSelected: Bool
    private var isHovering = false {
        didSet { updateAppearance() }
    }

    init(
        title: String,
        isSelected: Bool,
        targetWindow: NSWindow,
        hostWindow: TerminalWindow,
        tabBar: TerminalVerticalTabBar
    ) {
        self.targetWindow = targetWindow
        self.hostWindow = hostWindow
        self.tabBar = tabBar
        self.isSelected = isSelected

        super.init(frame: .zero)

        setup(title: title)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.mouseDown(with: event)
            return
        }

        let startLocation = event.locationInWindow
        var didDrag = false

        while let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch nextEvent.type {
            case .leftMouseDragged:
                let deltaX = nextEvent.locationInWindow.x - startLocation.x
                let deltaY = nextEvent.locationInWindow.y - startLocation.y
                if hypot(deltaX, deltaY) > 4 {
                    didDrag = true
                    alphaValue = 0.75
                    tabBar?.showDropIndicator(for: nextEvent)
                }

            case .leftMouseUp:
                alphaValue = 1
                tabBar?.hideDropIndicator()
                if didDrag,
                   let targetWindow,
                   let dropIndex = tabBar?.dropIndex(for: nextEvent) {
                    tabBar?.moveTab(targetWindow, toDropIndex: dropIndex)
                } else {
                    selectTab()
                }
                return

            default:
                break
            }
        }

        alphaValue = 1
        tabBar?.hideDropIndicator()
        selectTab()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard hostWindow != nil else {
            super.rightMouseDown(with: event)
            return
        }

        selectTab()
        NSMenu.popUpContextMenu(tabContextMenu, with: event, for: self)
    }

    private var tabContextMenu: NSMenu {
        let menu = NSMenu()

        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "")
        closeItem.target = self
        closeItem.setImageIfDesired(systemSymbolName: "xmark")
        menu.addItem(closeItem)

        let renameItem = NSMenuItem(title: "Rename Tab...", action: #selector(renameTab), keyEquivalent: "")
        renameItem.target = self
        renameItem.setImageIfDesired(systemSymbolName: "pencil.line")
        menu.addItem(renameItem)

        return menu
    }

    private func setup(title: String) {
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false

        selectedIndicator.translatesAutoresizingMaskIntoConstraints = false
        selectedIndicator.wantsLayer = true
        selectedIndicator.layer?.cornerRadius = 1.5
        selectedIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        addSubview(selectedIndicator)

        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
        closeButton.imagePosition = .imageOnly
        closeButton.toolTip = "Close Tab"
        closeButton.target = self
        closeButton.action = #selector(closeTab)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: TerminalVerticalTabBar.rowHeight),

            selectedIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            selectedIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectedIndicator.widthAnchor.constraint(equalToConstant: 3),
            selectedIndicator.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        } else if isHovering {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        selectedIndicator.isHidden = !isSelected
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        closeButton.contentTintColor = isSelected ? .labelColor : .tertiaryLabelColor
        closeButton.alphaValue = isSelected || isHovering ? 1 : 0
    }

    private func selectTab() {
        guard let targetWindow else { return }
        targetWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func closeTab() {
        guard let controller = targetWindow?.windowController as? TerminalController else { return }
        targetWindow?.makeKeyAndOrderFront(nil)
        controller.closeTab(nil)
    }

    @objc private func renameTab() {
        guard let controller = targetWindow?.windowController as? BaseTerminalController else { return }
        controller.promptTabTitle()
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
