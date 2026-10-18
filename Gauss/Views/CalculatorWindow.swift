import Cocoa
import GaussEngine

/// The main calculator window controller.
/// Manages the CalcTextView, ResultView, and TotalBar.
final class CalculatorWindowController: NSWindowController {

    private let engine: GaussEngine
    private var calcTextView: CalcTextView!
    private var resultView: ResultView!
    private var lineResults: [GaussEngine.LineResult] = []
    private let syntaxHighlighter = SyntaxHighlighter()
    private let documentController = DocumentController()
    private var isEvaluating = false

    // MARK: - Position Persistence Keys
    private static let frameKey = "GaussWindowFrame"

    init(engine: GaussEngine) {
        self.engine = engine

        // Create the window
        let contentRect = CalculatorWindowController.restoredFrame()
            ?? NSRect(x: 0, y: 0, width: 480, height: 400)

        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "Gauss"
        window.minSize = NSSize(width: 320, height: 200)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("GaussMainWindow")

        // Center if there's no saved frame
        if CalculatorWindowController.restoredFrame() == nil {
            window.center()
        }

        super.init(window: window)

        window.delegate = self
        setupContentView()
        setupTitlebarAccessory()
        loadSavedDocument()

        // Observe settings changes directly
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSettingsChanged),
            name: Settings.didChangeNotification,
            object: nil
        )
    }

    @objc private func onSettingsChanged() {
        applySettings()
    }

    // MARK: - Document Persistence

    private func loadSavedDocument() {
        let saved = documentController.loadCurrent()
        guard !saved.isEmpty else { return }
        calcTextView.string = saved
        handleTextChanged(saved)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resultView.update(with: self.lineResults, textView: self.calcTextView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Frame Persistence

    private static func restoredFrame() -> NSRect? {
        let str = UserDefaults.standard.string(forKey: frameKey)
        return str.flatMap { NSRectFromString($0) != .zero ? NSRectFromString($0) : nil }
    }

    private func saveFrame() {
        if let frame = window?.frame {
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: CalculatorWindowController.frameKey)
        }
    }

    // MARK: - Content View Setup

    private func setupContentView() {
        guard let window = window else { return }

        // Visual effect view for Liquid Glass background
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .sidebar
        visualEffect.state = .active
        window.contentView = visualEffect

        // Main vertical stack: editor area + total bar
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        // Editor area: CalcTextView (left) + ResultView (right) sharing a scroll
        let editorContainer = setupEditorArea()
        mainStack.addArrangedSubview(editorContainer)

        // The editor area should fill available space
        editorContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func setupEditorArea() -> NSView {
        // Container to hold the scroll view
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Create the CalcTextView
        calcTextView = CalcTextView()
        calcTextView.completionProvider = engine.completionProvider
        calcTextView.onTextChanged = { [weak self] text in
            self?.handleTextChanged(text)
        }

        // Scroll view for the text view
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        // Create a split content view that holds both text and results
        let splitView = EditorSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false

        // Set up the text view inside the scroll view
        calcTextView.minSize = NSSize(width: 0, height: 0)
        calcTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        calcTextView.isVerticallyResizable = true
        calcTextView.isHorizontallyResizable = false
        calcTextView.autoresizingMask = [.width]

        scrollView.documentView = calcTextView

        // ResultView as a column to the right of the editor
        resultView = ResultView()
        resultView.translatesAutoresizingMaskIntoConstraints = false
        resultView.attachWidthConstraint()
        resultView.onResultCopied = { [weak self] formatted in
            self?.showCopyToast(formatted)
        }

        container.addSubview(scrollView)
        container.addSubview(resultView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: resultView.leadingAnchor),

            resultView.topAnchor.constraint(equalTo: container.topAnchor),
            resultView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            resultView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])

        // Sync scroll position
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return container
    }

    // MARK: - Toolbar Buttons (+ and ≡ in titlebar area)

    private func setupTitlebarAccessory() {
        guard let window = window else { return }

        // Make titlebar blend with content for seamless look
        window.titlebarAppearsTransparent = true

        // Create buttons in the titlebar using standardWindowButton positioning
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let newButton = NSButton(title: "+", target: self, action: #selector(newSessionClicked))
        newButton.bezelStyle = .recessed
        newButton.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        newButton.isBordered = false
        newButton.contentTintColor = .secondaryLabelColor
        newButton.toolTip = "New Session (⌘N)"

        let menuButton = NSButton(title: "≡", target: self, action: #selector(menuButtonClicked(_:)))
        menuButton.bezelStyle = .recessed
        menuButton.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        menuButton.isBordered = false
        menuButton.contentTintColor = .secondaryLabelColor
        menuButton.toolTip = "More Options"

        buttonStack.addArrangedSubview(newButton)
        buttonStack.addArrangedSubview(menuButton)

        // Add to the titlebar area (above content)
        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.addSubview(buttonStack)
            NSLayoutConstraint.activate([
                buttonStack.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor),
                buttonStack.trailingAnchor.constraint(equalTo: titlebarView.trailingAnchor, constant: -10),
            ])
        }
    }

    @objc private func newSessionClicked() {
        clearDocument()
    }

    @objc private func menuButtonClicked(_ sender: NSButton) {
        let menu = NSMenu()
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.keyEquivalentModifierMask = .command
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Export...", action: #selector(exportDocument), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy All to Clipboard", action: #selector(copyAllToClipboard), keyEquivalent: ""))

        // Show menu below the button (convert to window coords for precise positioning)
        let buttonBottomRight = sender.convert(NSPoint(x: sender.bounds.width, y: sender.bounds.height), to: nil)
        let screenPoint = sender.window?.convertPoint(toScreen: buttonBottomRight) ?? .zero
        menu.popUp(positioning: nil, at: NSPoint(x: screenPoint.x - menu.size.width, y: screenPoint.y), in: nil)
    }

    @objc private func openPreferences() {
        (NSApp.delegate as? AppDelegate)?.showPreferences()
    }

    // MARK: - Export

    @objc private func exportDocument() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Gauss Calculation.txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = buildExportText()
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    @objc private func copyAllToClipboard() {
        let text = buildExportText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopyToast("All calculations copied")
    }

    private func buildExportText() -> String {
        let lines = calcTextView.string.components(separatedBy: "\n")
        var export = ""
        for (i, line) in lines.enumerated() {
            let result = i < lineResults.count ? lineResults[i].formatted : ""
            if result.isEmpty {
                export += line + "\n"
            } else {
                let padding = max(1, 40 - line.count)
                export += line + String(repeating: " ", count: padding) + result + "\n"
            }
        }
        return export
    }

    // MARK: - Text Changed Handler

    private func handleTextChanged(_ text: String) {
        guard !isEvaluating else { return } // prevent reentrancy from syntax highlighting
        isEvaluating = true
        defer { isEvaluating = false }

        documentController.scheduleSave(content: text)
        lineResults = engine.evaluateDocument(text)
        resultView.update(with: lineResults, textView: calcTextView)
        syntaxHighlighter.apply(to: calcTextView.textStorage!, results: lineResults)
    }

    // MARK: - Scroll Sync

    @objc private func scrollViewBoundsChanged(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView else { return }
        resultView.scrollOffset = clipView.bounds.origin
        resultView.needsDisplay = true
    }

    // MARK: - Public API

    /// Apply current Settings to the engine formatter and re-evaluate.
    func applySettings() {
        engine.formatter.maxDecimalPlaces = Settings.shared.precision
        engine.formatter.dateFormatString = Settings.shared.dateFormat

        // Update font
        updateFont()

        // Re-evaluate so results reflect new formatting
        let text = calcTextView.string
        handleTextChanged(text)
    }

    /// Update font size in text view and result view.
    private func updateFont() {
        calcTextView.font = Theme.monoFont
        resultView.needsDisplay = true
    }

    // MARK: - Font Size Shortcuts (⌘+ / ⌘-)

    func increaseFontSize() {
        Settings.shared.fontSize += 1
    }

    func decreaseFontSize() {
        Settings.shared.fontSize -= 1
    }

    func clearDocument() {
        _ = documentController.archiveAndClear()
        calcTextView.string = ""
        lineResults = []
        resultView.update(with: [], textView: calcTextView)
    }

    /// Copy the result of the current line to the clipboard.
    func copyCurrentResult() {
        guard let textView = calcTextView else { return }

        // Determine which line the cursor is on
        let selectedRange = textView.selectedRange()
        let text = textView.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        var lineIndex = 0
        var offset = 0
        while offset < lineRange.location {
            let range = text.lineRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(range)
            lineIndex += 1
        }

        guard lineIndex < lineResults.count else { return }
        let result = lineResults[lineIndex]
        guard !result.formatted.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.formatted, forType: .string)
        showCopyToast(result.formatted)
    }

    private func showCopyToast(_ text: String) {
        guard let window = window, let contentView = window.contentView else { return }
        ToastView.show(in: contentView, message: "Copied: \(text)")
    }

    // MARK: - Keyboard Shortcuts

    override func keyDown(with event: NSEvent) {
        // Shift+Cmd+C to copy current result
        if event.modifierFlags.contains([.shift, .command]),
           event.charactersIgnoringModifiers == "c" {
            copyCurrentResult()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - NSWindowDelegate

extension CalculatorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Hide instead of close (menu bar app behavior)
        window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
        resultView.update(with: lineResults, textView: calcTextView)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide the window instead of closing
        sender.orderOut(nil)
        return false
    }
}

// MARK: - EditorSplitView (utility)

/// A view that holds both the text view area and result area side by side.
private final class EditorSplitView: NSView {
    override var isFlipped: Bool { true }
}
