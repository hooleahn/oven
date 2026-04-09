import SwiftUI
import AppKit

// MARK: - NSTextView subclass that draws its own line numbers in the left margin

private class LineNumberTextView: NSTextView {
    private let gutterWidth: CGFloat = 44
    private let gutterPadding: CGFloat = 6

    // Called once after init to apply the left inset that makes room for numbers.
    func setupGutter() {
        textContainerInset = NSSize(width: 8, height: 10)
        textContainer?.lineFragmentPadding = gutterWidth
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard
            let layoutManager = layoutManager,
            let textContainer = textContainer
        else { return }

        // Gutter background.
        NSColor.windowBackgroundColor.withAlphaComponent(0.6).setFill()
        NSRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height).fill()

        // Right separator line.
        NSColor.separatorColor.setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: gutterWidth - 0.5, y: rect.minY))
        sep.line(to: NSPoint(x: gutterWidth - 0.5, y: rect.maxY))
        sep.lineWidth = 1
        sep.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        let src = string as NSString
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let textBeforeVisible = src.substring(to: visibleCharRange.location)
        var lineNumber = textBeforeVisible.components(separatedBy: "\n").count

        var glyphIndex = visibleGlyphRange.location
        let glyphEnd = NSMaxRange(visibleGlyphRange)

        while glyphIndex < glyphEnd {
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineCharRange = src.lineRange(for: NSRange(location: charIndex, length: 0))
            let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: lineCharRange, actualCharacterRange: nil)

            // Only label the first fragment of each logical line.
            var effectiveRange = NSRange(location: 0, length: 0)
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: lineGlyphRange.location,
                effectiveRange: &effectiveRange,
                withoutAdditionalLayout: true
            )

            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attrs)
            let x = gutterWidth - gutterPadding - size.width
            let y = textContainerOrigin.y + NSMinY(fragmentRect) + (NSHeight(fragmentRect) - size.height) / 2
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

            glyphIndex = NSMaxRange(lineGlyphRange)
            lineNumber += 1
        }

        // Empty trailing line.
        if layoutManager.extraLineFragmentTextContainer != nil {
            let fragmentRect = layoutManager.extraLineFragmentRect
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attrs)
            let x = gutterWidth - gutterPadding - size.width
            let y = textContainerOrigin.y + NSMinY(fragmentRect) + (NSHeight(fragmentRect) - size.height) / 2
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
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
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tv = LineNumberTextView()
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.isEditable = isEditable
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.allowsUndo = true
        tv.setupGutter()
        tv.delegate = context.coordinator
        tv.string = text
        context.coordinator.textView = tv
        HCLEditor.applyHighlighting(to: tv)

        scrollView.documentView = tv

        // Redraw line numbers on scroll.
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrolled),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

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
            tv.setNeedsDisplay(tv.visibleRect)
        }

        @objc func scrolled(_ note: Notification) {
            textView?.setNeedsDisplay(textView?.visibleRect ?? .zero)
        }
    }
}
