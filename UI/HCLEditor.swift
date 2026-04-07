import SwiftUI
import AppKit

// MARK: - Line number ruler view

private class LineNumberRulerView: NSRulerView {
    private let padding: CGFloat = 6
    private let minWidth: CGFloat = 40

    weak var textView: NSTextView? {
        didSet {
            NotificationCenter.default.removeObserver(self)
            if let tv = textView {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(invalidate),
                    name: NSText.didChangeNotification,
                    object: tv
                )
                // Redraw whenever the user scrolls.
                if let clipView = tv.enclosingScrollView?.contentView {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(invalidate),
                        name: NSView.boundsDidChangeNotification,
                        object: clipView
                    )
                    clipView.postsBoundsChangedNotifications = true
                }
            }
        }
    }

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = scrollView.documentView
    }

    required init(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func invalidate(_ note: Notification) { needsDisplay = true }

    override var requiredThickness: CGFloat { ruleThickness }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard
            let tv = textView,
            let layoutManager = tv.layoutManager,
            let textContainer = tv.textContainer
        else { return }

        let defaults: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        let string = tv.string as NSString
        let visibleRect = tv.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Count newlines before the visible range to get the starting line number.
        let textBeforeVisible = string.substring(to: visibleCharRange.location)
        var lineNumber = textBeforeVisible.components(separatedBy: "\n").count

        // Convert the text view's origin into the ruler's coordinate space.
        // This maps document-space Y values into ruler-space Y values correctly
        // regardless of scroll position.
        let tvOriginInRuler = convert(tv.textContainerOrigin, from: tv)

        var glyphIndex = visibleGlyphRange.location
        let glyphEnd = NSMaxRange(visibleGlyphRange)

        var maxLabelWidth: CGFloat = 0

        while glyphIndex < glyphEnd {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineCharRange = string.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineCharRange, actualCharacterRange: nil)

            // Walk each line-fragment rect (handles wrapped lines).
            var fragmentGlyphIndex = lineGlyphRange.location
            var isFirstFragment = true
            while fragmentGlyphIndex < NSMaxRange(lineGlyphRange) {
                var effectiveRange = NSRange(location: 0, length: 0)
                let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: fragmentGlyphIndex, effectiveRange: &effectiveRange, withoutAdditionalLayout: true)

                let y = tvOriginInRuler.y + NSMinY(fragmentRect)

                if isFirstFragment {
                    let label = "\(lineNumber)" as NSString
                    let size = label.size(withAttributes: defaults)
                    let x = ruleThickness - size.width - padding
                    let drawRect = NSRect(x: x, y: y + (NSHeight(fragmentRect) - size.height) / 2, width: size.width, height: size.height)
                    label.draw(in: drawRect, withAttributes: defaults)
                    maxLabelWidth = max(maxLabelWidth, size.width)
                    isFirstFragment = false
                }

                fragmentGlyphIndex = NSMaxRange(effectiveRange)
            }

            glyphIndex = NSMaxRange(lineGlyphRange)
            lineNumber += 1
        }

        // Handle empty last line (extra line fragment).
        if layoutManager.extraLineFragmentTextContainer != nil {
            let fragmentRect = layoutManager.extraLineFragmentRect
            let y = tvOriginInRuler.y + NSMinY(fragmentRect)
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: defaults)
            let x = ruleThickness - size.width - padding
            let drawRect = NSRect(x: x, y: y + (NSHeight(fragmentRect) - size.height) / 2, width: size.width, height: size.height)
            label.draw(in: drawRect, withAttributes: defaults)
            maxLabelWidth = max(maxLabelWidth, size.width)
        }

        
        // Adjust ruler width dynamically.
        let required = max(minWidth, maxLabelWidth + padding * 2)
        if abs(ruleThickness - required) > 1 {
            ruleThickness = required
            enclosingScrollView?.tile()
        }
    }
}

// MARK: - Scroll view that confines the ruler to the content area

private class RulerScrollView: NSScrollView {
    override func tile() {
        super.tile()
        // After tiling, the ruler runs the full height of the scroll view frame,
        // which bleeds into sibling SwiftUI views above. Constrain it to sit
        // exactly alongside the content view.
        guard let ruler = verticalRulerView else { return }
        let cv = contentView
        var rf = ruler.frame
        let cvf = cv.frame
        rf.origin.y = cvf.origin.y
        rf.size.height = cvf.size.height
        ruler.frame = rf
    }
}

// MARK: - HCL syntax-highlighted editor
// Uses NSTextView with a basic token-coloring overlay via textStorage.
// Highlights: keywords, strings, comments, variable references, block openers.

struct HCLEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    let onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = RulerScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        let tv = NSTextView()
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        scrollView.documentView = tv
        tv.isEditable = isEditable
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.allowsUndo = true
        tv.delegate = context.coordinator
        tv.string = text
        context.coordinator.textView = tv
        HCLEditor.applyHighlighting(to: tv)

        // Attach line number ruler.
        let ruler = LineNumberRulerView(scrollView: scrollView)
        ruler.textView = tv
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        tv.isEditable = isEditable
        if tv.string != text {
            let sel = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = sel
            HCLEditor.applyHighlighting(to: tv)
            scrollView.verticalRulerView?.needsDisplay = true
        }
    }

    // MARK: - Token colouring

    static func applyHighlighting(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let src = tv.string
        let full = NSRange(src.startIndex..., in: src)

        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        storage.addAttribute(.font,
            value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: full)

        // Comments: # … EOL
        applyPattern("(?m)#.*$", color: .systemGreen, storage: storage, src: src)
        // Strings: "…"
        applyPattern("\"(?:[^\"\\\\]|\\\\.)*\"", color: .systemOrange, storage: storage, src: src)
        // Keywords
        let keywords = ["packer", "source", "build", "provisioner", "variable", "locals",
                        "required_plugins", "post-processor", "dynamic", "content", "for_each",
                        "labels", "default", "description", "type", "version"]
        for kw in keywords {
            applyPattern("\\b\(kw)\\b", color: .systemPurple, storage: storage, src: src)
        }
        // Variable refs: var.X, local.X
        applyPattern("\\b(var|local)\\.[a-zA-Z_][a-zA-Z0-9_]*",
                     color: .systemBlue, storage: storage, src: src)
        // HCL block openers
        applyPattern("^[a-zA-Z_][a-zA-Z0-9_-]*(?:\\s+\"[^\"]*\")*\\s*\\{",
                     color: .systemTeal, storage: storage, src: src)
    }

    private static func applyPattern(
        _ pattern: String, color: NSColor, storage: NSTextStorage, src: String
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsStr = src as NSString
        regex.enumerateMatches(in: src, range: NSRange(location: 0, length: nsStr.length)) { m, _, _ in
            if let r = m?.range { storage.addAttribute(.foregroundColor, value: color, range: r) }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HCLEditor
        weak var textView: NSTextView?

        init(_ parent: HCLEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
            HCLEditor.applyHighlighting(to: tv)
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}
