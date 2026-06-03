import AppKit

final class TerminalVerticalTabBar: NSVisualEffectView {
    enum Position {
        case left
        case right
    }

    static let defaultWidth: CGFloat = 180
    static let minWidth: CGFloat = 120
    static let maxWidth: CGFloat = 320
    static let rowHeight: CGFloat = 32
    private static var sharedWidth: CGFloat = defaultWidth

    private weak var hostWindow: TerminalWindow?
    let position: Position
    private let stackView = NSStackView()
    private let scrollView = NSScrollView()
    private let separator = NSBox()
    private let resizeHandle: TerminalVerticalTabResizeHandle
    private let newTabButton = NSButton()
    private let dropIndicator = NSView()
    private var widthConstraint: NSLayoutConstraint?
    private var dropIndicatorTopConstraint: NSLayoutConstraint?
    private var reloadScheduled = false

    var preferredWidth: CGFloat { widthConstraint?.constant ?? Self.sharedWidth }

    init(hostWindow: TerminalWindow, position: Position) {
        self.hostWindow = hostWindow
        self.position = position
        self.resizeHandle = TerminalVerticalTabResizeHandle(position: position)
        super.init(frame: .zero)

        resizeHandle.tabBar = self
        setup()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        guard let hostWindow else { return }
        let windows = hostWindow.tabGroup?.windows ?? [hostWindow]
        let selectedWindow = hostWindow.tabGroup?.selectedWindow ?? hostWindow

        let existingItems = stackView.arrangedSubviews.compactMap { $0 as? TerminalVerticalTabButton }
        let canReuseItems =
            existingItems.count == stackView.arrangedSubviews.count &&
            existingItems.count == windows.count &&
            zip(existingItems, windows).allSatisfy { pair in
                pair.0.representedWindow === pair.1
            }

        if canReuseItems {
            for (index, item) in existingItems.enumerated() {
                let window = windows[index]
                item.update(
                    title: tabTitle(for: window, index: index),
                    isSelected: window === selectedWindow
                )
            }

            isHidden = false
            return
        }

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

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

    func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            reloadScheduled = false
            reload()
        }
    }

    func reloadTabBarsInGroup() {
        guard let hostWindow else {
            scheduleReload()
            return
        }

        let windows = hostWindow.tabGroup?.windows ?? [hostWindow]
        for window in windows {
            (window.windowController as? TerminalController)?
                .terminalViewContainer?
                .reloadVerticalTabBar()
        }
    }

    func setWidth(_ width: CGFloat) {
        let newWidth = Self.clampedWidth(width)
        guard widthConstraint?.constant != newWidth else { return }

        widthConstraint?.constant = newWidth
        invalidateIntrinsicContentSize()
        superview?.invalidateIntrinsicContentSize()
        superview?.layoutSubtreeIfNeeded()
    }

    fileprivate func resize(by deltaX: CGFloat) {
        guard let widthConstraint else { return }

        let directionMultiplier: CGFloat = position == .left ? 1 : -1
        let proposedWidth = widthConstraint.constant + deltaX * directionMultiplier
        let newWidth = Self.clampedWidth(proposedWidth)
        guard newWidth != widthConstraint.constant else { return }

        Self.sharedWidth = newWidth
        applySharedWidthToTabGroup()
    }

    private static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }

    private func applySharedWidthToTabGroup() {
        guard let hostWindow else {
            setWidth(Self.sharedWidth)
            return
        }

        let windows = hostWindow.tabGroup?.windows ?? [hostWindow]
        for window in windows {
            (window.windowController as? TerminalController)?
                .terminalViewContainer?
                .setVerticalTabBarWidth(Self.sharedWidth)
        }
    }

    fileprivate func dropIndex(for event: NSEvent) -> Int? {
        guard let documentView = scrollView.documentView else { return nil }
        return dropIndex(
            forDocumentLocation: documentView.convert(event.locationInWindow, from: nil),
            in: documentView
        )
    }

    fileprivate func canReorder(at event: NSEvent) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        return bounds.insetBy(dx: -24, dy: -24).contains(location)
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
        guard canReorder(at: event),
              let documentView = scrollView.documentView else {
            hideDropIndicator()
            return
        }

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

    fileprivate func detachTab(_ window: NSWindow, at event: NSEvent) {
        guard let hostWindow,
              let tabGroup = hostWindow.tabGroup,
              tabGroup.windows.count > 1,
              tabGroup.windows.contains(where: { $0 === window })
        else { return }

        let remainingController = tabGroup.windows
            .first(where: { $0 !== window })?
            .windowController as? TerminalController

        let screenPoint = self.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        var frame = window.frame
        let horizontalOffset = min(max(frame.width * 0.25, 80), 220)
        let verticalOffset: CGFloat = 28
        frame.origin.x = screenPoint.x - horizontalOffset
        frame.origin.y = screenPoint.y + verticalOffset - frame.height

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        defer { NSAnimationContext.endGrouping() }

        tabGroup.removeWindow(window)
        window.setFrame(frame, display: true)
        window.constrainToScreen()
        window.makeKeyAndOrderFront(nil)

        remainingController?.relabelTabs()
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
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 8, right: 8)

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
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(newTabButton)
        contentView.addSubview(separator)
        contentView.addSubview(resizeHandle)
        addSubview(dropIndicator)
        dropIndicator.translatesAutoresizingMaskIntoConstraints = false
        dropIndicator.wantsLayer = true
        dropIndicator.layer?.cornerRadius = 1
        dropIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dropIndicator.isHidden = true

        dropIndicatorTopConstraint = dropIndicator.topAnchor.constraint(equalTo: topAnchor)

        let widthConstraint = widthAnchor.constraint(equalToConstant: Self.sharedWidth)
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            widthConstraint,
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

                resizeHandle.topAnchor.constraint(equalTo: contentView.topAnchor),
                resizeHandle.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                resizeHandle.centerXAnchor.constraint(equalTo: separator.centerXAnchor),
                resizeHandle.widthAnchor.constraint(equalToConstant: 7),
            ])
        case .right:
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: contentView.topAnchor),
                separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                separator.widthAnchor.constraint(equalToConstant: 1),

                resizeHandle.topAnchor.constraint(equalTo: contentView.topAnchor),
                resizeHandle.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                resizeHandle.centerXAnchor.constraint(equalTo: separator.centerXAnchor),
                resizeHandle.widthAnchor.constraint(equalToConstant: 7),
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

private final class TerminalVerticalTabButton: NSView, NSTextFieldDelegate {
    private weak var targetWindow: NSWindow?
    private weak var hostWindow: TerminalWindow?
    private weak var tabBar: TerminalVerticalTabBar?
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let selectedIndicator = NSView()
    private var dragPreviewWindow: NSWindow?
    private var titleEditor: NSTextField?
    private var isSelected: Bool
    private var isHovering = false {
        didSet { updateAppearance() }
    }

    var representedWindow: NSWindow? { targetWindow }

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

        if titleEditor != nil {
            finishInlineTitleEdit(commit: true)
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
                    showDragPreviewIfNeeded()
                    updateDragPreviewPosition(for: nextEvent)
                    tabBar?.showDropIndicator(for: nextEvent)
                }

            case .leftMouseUp:
                alphaValue = 1
                closeDragPreview()
                tabBar?.hideDropIndicator()
                if didDrag,
                   let targetWindow,
                   let tabBar {
                    if tabBar.canReorder(at: nextEvent),
                       let dropIndex = tabBar.dropIndex(for: nextEvent) {
                        tabBar.moveTab(targetWindow, toDropIndex: dropIndex)
                    } else {
                        tabBar.detachTab(targetWindow, at: nextEvent)
                    }
                } else {
                    selectTab()
                }
                return

            default:
                break
            }
        }

        alphaValue = 1
        closeDragPreview()
        tabBar?.hideDropIndicator()
        selectTab()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard hostWindow != nil else {
            super.rightMouseDown(with: event)
            return
        }

        if titleEditor != nil {
            finishInlineTitleEdit(commit: true)
        }

        NSMenu.popUpContextMenu(tabContextMenu, with: event, for: self)
    }

    private var tabContextMenu: NSMenu {
        let menu = NSMenu()
        let tabCount = hostWindow?.tabGroup?.windows.count ?? 1

        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "")
        closeItem.target = self
        closeItem.setImageIfDesired(systemSymbolName: "xmark")
        menu.addItem(closeItem)

        let closeOtherItem = NSMenuItem(title: "Close Other Tabs", action: #selector(closeOtherTabs), keyEquivalent: "")
        closeOtherItem.target = self
        closeOtherItem.isEnabled = tabCount > 1
        closeOtherItem.setImageIfDesired(systemSymbolName: "xmark")
        menu.addItem(closeOtherItem)

        let closeRightItem = NSMenuItem(title: "Close Tabs to the Right", action: #selector(closeTabsOnTheRight), keyEquivalent: "")
        closeRightItem.target = self
        closeRightItem.isEnabled = hasTabsToTheRight
        closeRightItem.setImageIfDesired(systemSymbolName: "xmark")
        menu.addItem(closeRightItem)

        let closeAllItem = NSMenuItem(title: "Close All Tabs", action: #selector(closeAllTabs), keyEquivalent: "")
        closeAllItem.target = self
        closeAllItem.setImageIfDesired(systemSymbolName: "xmark")
        menu.addItem(closeAllItem)

        menu.addItem(.separator())

        let renameItem = NSMenuItem(title: "Rename Tab...", action: #selector(renameTab), keyEquivalent: "")
        renameItem.target = self
        renameItem.setImageIfDesired(systemSymbolName: "pencil.line")
        menu.addItem(renameItem)

        return menu
    }

    private var hasTabsToTheRight: Bool {
        guard let hostWindow,
              let targetWindow,
              let windows = hostWindow.tabGroup?.windows,
              let index = windows.firstIndex(where: { $0 === targetWindow })
        else { return false }

        return windows.indices.contains { $0 > index }
    }

    func update(title: String, isSelected: Bool) {
        titleLabel.stringValue = title
        self.isSelected = isSelected
        updateAppearance()
    }

    private func showDragPreviewIfNeeded() {
        guard dragPreviewWindow == nil else { return }

        let preview = TerminalVerticalTabDragPreview(title: titleLabel.stringValue, isSelected: isSelected)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: max(bounds.width, 140),
                height: TerminalVerticalTabBar.rowHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = preview
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = .floating
        window.alphaValue = 0.92
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderFront(nil)
        dragPreviewWindow = window
    }

    private func updateDragPreviewPosition(for event: NSEvent) {
        guard let dragPreviewWindow else { return }

        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        var frame = dragPreviewWindow.frame
        frame.origin.x = screenPoint.x + 12
        frame.origin.y = screenPoint.y - frame.height / 2
        dragPreviewWindow.setFrame(frame, display: true)
    }

    private func closeDragPreview() {
        dragPreviewWindow?.orderOut(nil)
        dragPreviewWindow = nil
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

    @objc private func closeOtherTabs() {
        guard let controller = targetWindow?.windowController as? TerminalController else { return }
        targetWindow?.makeKeyAndOrderFront(nil)
        controller.closeOtherTabs(nil)
    }

    @objc private func closeTabsOnTheRight() {
        guard let controller = targetWindow?.windowController as? TerminalController else { return }
        targetWindow?.makeKeyAndOrderFront(nil)
        controller.closeTabsOnTheRight(nil)
    }

    @objc private func closeAllTabs() {
        guard let controller = targetWindow?.windowController as? TerminalController else { return }
        targetWindow?.makeKeyAndOrderFront(nil)
        controller.closeWindow(nil)
    }

    @objc private func renameTab() {
        beginInlineTitleEdit()
    }

    @discardableResult
    private func beginInlineTitleEdit() -> Bool {
        guard titleEditor == nil,
              let targetWindow,
              let controller = targetWindow.windowController as? BaseTerminalController
        else {
            titleEditor?.currentEditor()?.selectAll(nil)
            return titleEditor != nil
        }

        let editor = NSTextField(frame: .zero)
        editor.delegate = self
        editor.stringValue = controller.titleOverride ?? targetWindow.title
        editor.font = titleLabel.font
        editor.textColor = titleLabel.textColor
        editor.alignment = titleLabel.alignment
        editor.isBordered = false
        editor.isBezeled = false
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.lineBreakMode = .byClipping
        if let editorCell = editor.cell as? NSTextFieldCell {
            editorCell.wraps = false
            editorCell.usesSingleLineMode = true
            editorCell.isScrollable = true
        }

        titleEditor = editor
        titleLabel.isHidden = true
        closeButton.isHidden = true
        addSubview(editor, positioned: .above, relativeTo: titleLabel)
        editor.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            editor.centerYAnchor.constraint(equalTo: centerYAnchor),
            editor.heightAnchor.constraint(equalToConstant: 22),
        ])

        DispatchQueue.main.async { [weak self, weak editor] in
            guard let self,
                  let editor,
                  self.titleEditor === editor
            else { return }

            window?.makeFirstResponder(editor)
            if let fieldEditor = editor.currentEditor() as? NSTextView,
               let editorFont = editor.font {
                fieldEditor.font = editorFont
                var typingAttributes = fieldEditor.typingAttributes
                typingAttributes[.font] = editorFont
                fieldEditor.typingAttributes = typingAttributes
            }
            editor.currentEditor()?.selectAll(nil)
        }

        return true
    }

    private func finishInlineTitleEdit(commit: Bool) {
        guard let editor = titleEditor else { return }

        let editedTitle = editor.stringValue
        let editedWindow = targetWindow
        titleEditor = nil
        editor.delegate = nil

        if let responderWindow = editor.window ?? window {
            if let currentEditor = editor.currentEditor(), responderWindow.firstResponder === currentEditor {
                responderWindow.makeFirstResponder(nil)
            } else if responderWindow.firstResponder === editor {
                responderWindow.makeFirstResponder(nil)
            }
        }

        editor.removeFromSuperview()
        titleLabel.isHidden = false
        closeButton.isHidden = false
        updateAppearance()

        if commit,
           let editedWindow,
           let controller = editedWindow.windowController as? BaseTerminalController {
            controller.titleOverride = editedTitle.isEmpty ? nil : editedTitle
            tabBar?.reloadTabBarsInGroup()
        }

        restoreTerminalFocus()
    }

    private func restoreTerminalFocus() {
        guard let responderWindow = window,
              let controller = responderWindow.windowController as? BaseTerminalController,
              let focusedSurface = controller.focusedSurface
        else { return }

        responderWindow.makeFirstResponder(focusedSurface)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === titleEditor else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishInlineTitleEdit(commit: true)
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishInlineTitleEdit(commit: false)
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let titleEditor,
              let finishedEditor = obj.object as? NSTextField,
              finishedEditor === titleEditor
        else { return }

        finishInlineTitleEdit(commit: true)
    }
}

private final class TerminalVerticalTabDragPreview: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let selectedIndicator = NSView()
    private let isSelected: Bool

    init(title: String, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)
        setup(title: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(title: String) {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = (
            isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.22)
                : NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        ).cgColor

        selectedIndicator.translatesAutoresizingMaskIntoConstraints = false
        selectedIndicator.wantsLayer = true
        selectedIndicator.layer?.cornerRadius = 1.5
        selectedIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        selectedIndicator.isHidden = !isSelected
        addSubview(selectedIndicator)

        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            selectedIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            selectedIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectedIndicator.widthAnchor.constraint(equalToConstant: 3),
            selectedIndicator.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }
}

private final class TerminalVerticalTabResizeHandle: NSView {
    weak var tabBar: TerminalVerticalTabBar?
    private let position: TerminalVerticalTabBar.Position
    private var lastDragLocation: NSPoint?

    init(position: TerminalVerticalTabBar.Position) {
        self.position = position
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        lastDragLocation = event.locationInWindow
        NSCursor.resizeLeftRight.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let lastDragLocation else {
            self.lastDragLocation = event.locationInWindow
            return
        }

        let deltaX = event.locationInWindow.x - lastDragLocation.x
        self.lastDragLocation = event.locationInWindow
        tabBar?.resize(by: deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragLocation = nil
        NSCursor.pop()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
