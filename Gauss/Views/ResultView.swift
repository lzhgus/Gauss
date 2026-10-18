import Cocoa
import GaussEngine

/// Displays calculation results aligned to the right side, matching text view line positions.
final class ResultView: NSView {

    /// Called when a result is copied (provides the formatted string).
    var onResultCopied: ((String) -> Void)?

    /// Current scroll offset from the text scroll view.
    var scrollOffset: NSPoint = .zero

    private var lineResults: [GaussEngine.LineResult] = []
    private var lineMetrics: [(y: CGFloat, height: CGFloat)] = []
    private var textContainerInset: NSSize = NSSize(width: 8, height: 8)
    private var widthConstraint: NSLayoutConstraint?

    // Tracking area for hover
    private var trackingArea: NSTrackingArea?
    private var hoveredLine: Int? = nil

    override var isFlipped: Bool { true }

    // MARK: - Update

    func attachWidthConstraint() {
        let constraint = widthAnchor.constraint(equalToConstant: Self.minWidth)
        constraint.isActive = true
        widthConstraint = constraint
    }

    func update(with results: [GaussEngine.LineResult], textView: CalcTextView) {
        lineResults = results
        // Resize first and re-layout, so the editor re-wraps before we read its line metrics.
        let available = superview?.bounds.width ?? 0
        widthConstraint?.constant = Self.width(for: results, available: available)
        superview?.layoutSubtreeIfNeeded()
        lineMetrics = textView.lineMetrics()
        textContainerInset = textView.textContainerInset
        needsDisplay = true
        updateTrackingArea()
        announceResultsIfNeeded(results)
    }

    private static let minWidth: CGFloat = 48
    private static let maxWidth: CGFloat = 280
    private static let horizontalPadding: CGFloat = 16
    /// Results never take more than this share of the window; longer values truncate with "…".
    private static let maxShareOfWindow: CGFloat = 0.45

    private static func width(for results: [GaussEngine.LineResult], available: CGFloat) -> CGFloat {
        let font = Theme.monoFont
        var widest: CGFloat = 0
        for result in results where !result.formatted.isEmpty {
            let w = NSAttributedString(
                string: result.formatted,
                attributes: [.font: font]
            ).size().width
            if w > widest { widest = w }
        }
        let cap = available > 0 ? min(maxWidth, available * maxShareOfWindow) : maxWidth
        return min(cap, max(minWidth, ceil(widest) + horizontalPadding))
    }

    // MARK: - Accessibility

    private var previousResults: [GaussEngine.LineResult] = []

    private func announceResultsIfNeeded(_ results: [GaussEngine.LineResult]) {
        // Announce newly computed results to VoiceOver
        for (index, result) in results.enumerated() {
            guard !result.formatted.isEmpty else { continue }
            let prev = index < previousResults.count ? previousResults[index].formatted : ""
            if result.formatted != prev {
                NSAccessibility.post(
                    element: self,
                    notification: .valueChanged
                )
                break
            }
        }
        previousResults = results
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityLabel() -> String? {
        let nonEmpty = lineResults.enumerated().compactMap { index, r -> String? in
            guard !r.formatted.isEmpty else { return nil }
            return "Line \(index + 1): \(r.formatted)"
        }
        return nonEmpty.isEmpty ? "No results" : nonEmpty.joined(separator: ", ")
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .list }

    override func setAccessibilityIdentifier(_ accessibilityIdentifier: String?) {
        super.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    // Called after super.init in the view hierarchy — set identifier here via override init
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityIdentifier("resultView")
        setAccessibilityLabel("Calculation Results")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityIdentifier("resultView")
        setAccessibilityLabel("Calculation Results")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        Theme.separator.setStroke()
        let divider = NSBezierPath()
        divider.lineWidth = 1
        divider.move(to: NSPoint(x: 0.5, y: 0))
        divider.line(to: NSPoint(x: 0.5, y: bounds.height))
        divider.stroke()

        let font = Theme.monoFont
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        for (index, result) in lineResults.enumerated() {
            guard !result.formatted.isEmpty,
                  index < lineMetrics.count else { continue }

            let metric = lineMetrics[index]
            let y = metric.y + textContainerInset.height - scrollOffset.y

            // Skip lines outside visible area
            guard y + metric.height > 0, y < bounds.height else { continue }

            let color = resultColor(for: result.value)
            let isHovered = hoveredLine == index

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: isHovered ? color.withAlphaComponent(0.7) : color,
                .paragraphStyle: paragraphStyle,
            ]

            let drawRect = NSRect(
                x: 0,
                y: y,
                width: bounds.width,
                height: metric.height
            )

            // Truncate long results with ellipsis (but full value is kept for copy)
            let maxWidth = bounds.width - 8
            var displayText = result.formatted
            let fullAttrStr = NSAttributedString(string: displayText, attributes: attrs)
            if fullAttrStr.size().width > maxWidth {
                // Truncate and add ellipsis
                while displayText.count > 3 {
                    displayText = String(displayText.dropLast())
                    let testStr = NSAttributedString(string: displayText + "…", attributes: attrs)
                    if testStr.size().width <= maxWidth {
                        displayText += "…"
                        break
                    }
                }
            }

            let attrStr = NSAttributedString(string: displayText, attributes: attrs)
            attrStr.draw(in: drawRect)
        }
    }

    // MARK: - Result Color Mapping

    private func resultColor(for value: Value) -> NSColor {
        switch value {
        case .number, .currency, .percentage:
            return Theme.resultNumber
        case .unit, .duration:
            return Theme.resultUnit
        case .date, .dateDifference:
            return Theme.resultDate
        case .color, .string:
            return Theme.resultDev
        case .undefined, .infinity, .circular:
            return Theme.textSecondary
        }
    }

    // MARK: - Click to Copy

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let lineIndex = lineAt(point: point) {
            guard lineIndex < lineResults.count else { return }
            let result = lineResults[lineIndex]
            guard !result.formatted.isEmpty else { return }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.formatted, forType: .string)
            onResultCopied?(result.formatted)
        }
    }

    // MARK: - Hover Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newHovered = lineAt(point: point)

        // Only show pointer if the line has a result
        if let idx = newHovered, idx < lineResults.count, !lineResults[idx].formatted.isEmpty {
            NSCursor.pointingHand.set()
            if hoveredLine != idx {
                hoveredLine = idx
                needsDisplay = true
            }
        } else {
            NSCursor.arrow.set()
            if hoveredLine != nil {
                hoveredLine = nil
                needsDisplay = true
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        if hoveredLine != nil {
            hoveredLine = nil
            needsDisplay = true
        }
    }

    // MARK: - Hit Testing

    private func lineAt(point: NSPoint) -> Int? {
        for (index, metric) in lineMetrics.enumerated() {
            let y = metric.y + textContainerInset.height - scrollOffset.y
            if point.y >= y && point.y < y + metric.height {
                return index
            }
        }
        return nil
    }
}
