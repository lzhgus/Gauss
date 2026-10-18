import Cocoa
import GaussEngine

/// Custom text view for the calculator input area.
/// Monospace font, transparent background, notifies delegate on text changes.
/// Features inline ghost-text completion (like zsh-autosuggestions).
final class CalcTextView: NSTextView {

    /// Called whenever the text content changes.
    var onTextChanged: ((String) -> Void)?

    /// Completion provider from GaussEngine (set by CalculatorWindowController).
    var completionProvider: CompletionProvider?

    // MARK: - Ghost Completion State

    /// The current ghost suggestion (nil if none).
    private var ghostSuggestion: String?
    /// The range of the partial word being completed.
    private var ghostWordRange: NSRange?
    /// The overlay layer for drawing ghost text.
    private var ghostLayer: CATextLayer?
    /// Whether we're currently accepting a ghost (to avoid re-triggering).
    private var isAcceptingGhost = false

    // MARK: - Init

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        font = Theme.monoFont
        textColor = Theme.textPrimary
        backgroundColor = .clear
        drawsBackground = false
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        allowsUndo = true
        usesFindBar = true

        // Enable layer-backing for ghost text overlay
        wantsLayer = true

        // Insets for comfortable reading
        textContainerInset = NSSize(width: 8, height: 8)

        // Make the text container track the width
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        // Accessibility
        setAccessibilityLabel("Calculator Input")
        setAccessibilityIdentifier("calcTextView")
    }

    // MARK: - Text Change Notification

    override func didChangeText() {
        super.didChangeText()
        onTextChanged?(string)

        if !isAcceptingGhost {
            updateGhostSuggestion()
        }
    }

    // MARK: - Ghost Text Logic

    private func updateGhostSuggestion() {
        // Clear existing ghost
        clearGhost()

        guard let provider = completionProvider else { return }

        // Get the partial word at cursor
        let cursorPos = selectedRange().location
        guard cursorPos > 0 else { return }

        let text = string as NSString
        let totalLength = text.length
        guard cursorPos <= totalLength else { return }

        // Don't suggest if cursor is not at end of a word (e.g., cursor in middle of text)
        if cursorPos < totalLength {
            let nextChar = Character(UnicodeScalar(text.character(at: cursorPos))!)
            if nextChar.isLetter || nextChar.isNumber { return }
        }

        // Find the start of the current word
        var wordStart = cursorPos
        while wordStart > 0 {
            let charIndex = wordStart - 1
            // Stop at line boundaries
            if text.character(at: charIndex) == 0x0A { break }
            let ch = Character(UnicodeScalar(text.character(at: charIndex))!)
            if ch.isLetter || ch.isNumber { wordStart -= 1 } else { break }
        }

        let partialRange = NSRange(location: wordStart, length: cursorPos - wordStart)
        let partial = text.substring(with: partialRange)
        guard partial.count >= 2 else { return }

        // Get the best completion
        let suggestions = provider.completions(for: partial, limit: 1)
        guard let best = suggestions.first else { return }

        // The ghost shows only the remaining characters
        let remaining = String(best.dropFirst(partial.count))
        guard !remaining.isEmpty else { return }

        ghostSuggestion = remaining
        ghostWordRange = partialRange
        showGhostText(remaining, atCursorPosition: cursorPos)
    }

    private func showGhostText(_ text: String, atCursorPosition pos: Int) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        // Get the rect for the cursor position
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: pos)
        layoutManager.lineFragmentRect(forGlyphAt: min(glyphIndex, layoutManager.numberOfGlyphs > 0 ? layoutManager.numberOfGlyphs - 1 : 0), effectiveRange: nil)

        let location = layoutManager.location(forGlyphAt: min(glyphIndex, max(0, layoutManager.numberOfGlyphs - 1)))
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: min(glyphIndex, max(0, layoutManager.numberOfGlyphs - 1)), effectiveRange: nil)

        let cursorX = lineRect.origin.x + location.x + textContainerInset.width + textContainer.lineFragmentPadding + 6 // gap between cursor and ghost
        let cursorY = lineRect.origin.y + textContainerInset.height

        // Create ghost text layer
        let layer = CATextLayer()
        layer.string = text
        layer.font = Theme.monoFont
        layer.fontSize = Theme.monoFont.pointSize
        layer.foregroundColor = NSColor.tertiaryLabelColor.cgColor
        layer.contentsScale = window?.backingScaleFactor ?? 2.0
        layer.allowsFontSubpixelQuantization = true

        // Size the layer to fit the text
        let attrStr = NSAttributedString(string: text, attributes: [.font: Theme.monoFont])
        let textSize = attrStr.size()
        layer.frame = CGRect(
            x: cursorX,
            y: cursorY,
            width: textSize.width + 4,
            height: lineRect.height
        )

        // Align text vertically within the layer
        layer.alignmentMode = .left

        self.layer?.addSublayer(layer)
        ghostLayer = layer
    }

    private func clearGhost() {
        ghostLayer?.removeFromSuperlayer()
        ghostLayer = nil
        ghostSuggestion = nil
        ghostWordRange = nil
    }

    /// Accept the current ghost suggestion by pressing Tab.
    private func acceptGhost() {
        guard let suggestion = ghostSuggestion else { return }
        let cursorPos = selectedRange().location

        isAcceptingGhost = true
        defer { isAcceptingGhost = false }

        // Insert the ghost text at cursor
        let insertRange = NSRange(location: cursorPos, length: 0)
        if shouldChangeText(in: insertRange, replacementString: suggestion) {
            textStorage?.replaceCharacters(in: insertRange, with: suggestion)
            didChangeText()
            setSelectedRange(NSRange(location: cursorPos + suggestion.count, length: 0))
        }

        clearGhost()
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        // Tab accepts ghost suggestion
        if event.keyCode == 48 /* Tab */ && ghostSuggestion != nil {
            acceptGhost()
            return
        }

        // Escape clears ghost
        if event.keyCode == 53 /* Escape */ && ghostSuggestion != nil {
            clearGhost()
            return
        }

        // Right arrow at end of line accepts ghost
        if event.keyCode == 124 /* Right Arrow */ && ghostSuggestion != nil {
            let cursorPos = selectedRange().location
            let text = string as NSString
            // Only accept if cursor is at the end of the current word
            if cursorPos >= text.length || text.character(at: cursorPos) == 0x0A {
                acceptGhost()
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Disable Native Completions

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        // Disable native popup completions — we use ghost text instead
        return nil
    }

    // MARK: - Line Metrics

    /// Returns the y-offset and height for each visual line in the text view,
    /// relative to the text container origin.
    func lineMetrics() -> [(y: CGFloat, height: CGFloat)] {
        guard let layoutManager = layoutManager,
              textContainer != nil else { return [] }

        let text = string as NSString
        var metrics: [(y: CGFloat, height: CGFloat)] = []
        var charIndex = 0
        let totalLength = text.length

        while charIndex <= totalLength {
            if charIndex == totalLength {
                if totalLength > 0 && text.character(at: totalLength - 1) == 0x0A {
                    let lastMetric = metrics.last
                    let y = (lastMetric?.y ?? 0) + (lastMetric?.height ?? 0)
                    let lineHeight = Theme.monoFont.ascender - Theme.monoFont.descender + Theme.monoFont.leading
                    metrics.append((y: y, height: lineHeight))
                }
                break
            }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            var effectiveRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveRange
            )

            metrics.append((y: lineRect.origin.y, height: lineRect.height))

            let charRange = layoutManager.characterRange(
                forGlyphRange: effectiveRange,
                actualGlyphRange: nil
            )
            let nextCharIndex = NSMaxRange(charRange)
            if nextCharIndex <= charIndex {
                charIndex += 1
            } else {
                charIndex = nextCharIndex
            }
        }

        return metrics
    }

    // MARK: - Keyboard Shortcut Forwarding

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let wc = window?.windowController as? CalculatorWindowController

        // Shift+Cmd+C: copy current result
        if event.modifierFlags.contains([.shift, .command]),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            wc?.copyCurrentResult()
            return true
        }

        // Cmd+C / X / V / Z: no Edit menu in this LSUIElement app
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift),
           let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "c":
                copy(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "v":
                paste(nil)
                return true
            case "z":
                undoManager?.undo()
                return true
            default:
                break
            }
        }

        if event.modifierFlags.contains([.shift, .command]),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            undoManager?.redo()
            return true
        }

        // Cmd+= or Cmd++: increase font size
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+" {
            wc?.increaseFontSize()
            return true
        }

        // Cmd+-: decrease font size
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "-" {
            wc?.decreaseFontSize()
            return true
        }

        // Cmd+0: reset font size to default (13)
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "0" {
            Settings.shared.fontSize = 13
            return true
        }

        // Cmd+A: select all (let NSTextView handle it natively)
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "a" {
            selectAll(nil)
            return true
        }

        // Cmd+Q: quit app
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
            return true
        }

        // Cmd+N: new calculation
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "n" {
            wc?.clearDocument()
            return true
        }

        // Cmd+,: preferences
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "," {
            (NSApp.delegate as? AppDelegate)?.showPreferences()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
