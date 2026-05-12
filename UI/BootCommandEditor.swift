import SwiftUI
import AppKit

// MARK: - BootCommandEditor
//
// A syntax-highlighting NSTextView editor for Tart boot_command lines.
// Each line is one HCL string entry: "...<key>...".
//
// Token colours:
//   <waitNs> / <waitNNN>            → purple
//   <keyOn> / <keyOff> modifiers    → orange
//   single <key> / <click 'X'>      → blue
//   ${var.X} variable refs          → teal
//   outer " delimiters              → secondary label
//   literal text inside strings     → label

struct BootCommandEditor: NSViewRepresentable {
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

        let tv = BootCommandTextView()
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.isEditable = isEditable
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.allowsUndo = true
        tv.setupGutter()
        tv.owningScrollView = scrollView
        tv.delegate = context.coordinator
        tv.string = text
        context.coordinator.textView = tv
        BootCommandEditor.applyHighlighting(to: tv)

        scrollView.documentView = tv

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
            BootCommandEditor.applyHighlighting(to: tv)
        }
        if let container = tv.textContainer {
            tv.layoutManager?.ensureLayout(for: container)
        }
        tv.needsDisplay = true
    }

    // MARK: - Syntax highlighting

    static func applyHighlighting(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let src = tv.string
        let full = NSRange(src.startIndex..., in: src)

        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        storage.addAttribute(.font,
            value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: full)

        // Outer quotes (the " that wrap each HCL string entry)
        applyPattern(#"^"|"$"#, options: [.anchorsMatchLines],
                     color: .secondaryLabelColor, storage: storage, src: src)

        // Variable refs: ${var.X}
        applyPattern(#"\$\{[^}]+\}"#,
                     color: .systemTeal, storage: storage, src: src)

        // Wait tokens: <wait10s>, <wait5s>, <wait120s>, <wait1s>, <waitNNN>
        applyPattern(#"<wait\d+s?>"#,
                     color: .systemPurple, storage: storage, src: src)

        // Modifier On/Off pairs: <leftShiftOn>, <leftAltOff>, etc.
        applyPattern(#"<[a-zA-Z]+(?:On|Off)>"#,
                     color: .systemOrange, storage: storage, src: src)

        // click with argument: <click '...'>
        applyPattern(#"<click '[^']*'>"#,
                     color: .systemBlue, storage: storage, src: src)

        // Single key tokens: <tab>, <enter>, <spacebar>, <esc>, <up>, <down>, <left>, <right>,
        // <f1>–<f20>, <delete>, <return>, <home>, <end>, <pageUp>, <pageDown>, <bs>
        applyPattern(#"<(?:tab|enter|return|spacebar|esc|escape|up|down|left|right|delete|bs|home|end|pageUp|pageDown|f\d{1,2})>"#,
                     color: .systemBlue, storage: storage, src: src)

        storage.endEditing()
    }

    private static func applyPattern(
        _ pattern: String, options: NSRegularExpression.Options = [],
        color: NSColor, storage: NSTextStorage, src: String
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let nsStr = src as NSString
        regex.enumerateMatches(in: src, range: NSRange(location: 0, length: nsStr.length)) { m, _, _ in
            if let r = m?.range { storage.addAttribute(.foregroundColor, value: color, range: r) }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BootCommandEditor
        weak var textView: NSTextView?

        init(_ parent: BootCommandEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
            BootCommandEditor.applyHighlighting(to: tv)
            tv.setNeedsDisplay(tv.visibleRect)
        }

        @objc func scrolled(_ note: Notification) {
            textView?.setNeedsDisplay(textView?.visibleRect ?? .zero)
        }
    }
}

// MARK: - NSTextView subclass with line-number gutter

private class BootCommandTextView: NSTextView {
    private let gutterWidth: CGFloat = 44
    private let gutterPadding: CGFloat = 6
    private static let focusedBackground = NSColor(red: 49/255, green: 52/255, blue: 69/255, alpha: 1.0)
    weak var owningScrollView: NSScrollView?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result && isEditable {
            backgroundColor = Self.focusedBackground
            owningScrollView?.backgroundColor = Self.focusedBackground
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        backgroundColor = .textBackgroundColor
        owningScrollView?.backgroundColor = .textBackgroundColor
        return result
    }

    func setupGutter() {
        textContainerInset = NSSize(width: 8, height: 10)
        textContainer?.lineFragmentPadding = gutterWidth
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager, let textContainer else { return }

        NSColor.windowBackgroundColor.withAlphaComponent(0.6).setFill()
        NSRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height).fill()

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

// MARK: - BootCommandLinter

/// Validates a list of boot_command lines and returns a list of diagnostics.
struct BootCommandLinter {

    struct Diagnostic: Identifiable {
        let id = UUID()
        let line: Int       // 1-based
        let severity: Severity
        let message: String

        enum Severity { case warning, error }
    }

    /// All known modifier-key stems that come in On/Off pairs.
    private static let modifierStems = [
        "leftShift", "rightShift",
        "leftAlt", "rightAlt",
        "leftCtrl", "rightCtrl",
        "leftSuper", "rightSuper",
        "leftMeta", "rightMeta",
        "capsLock",
    ]

    /// All known single-key tokens (without angle brackets).
    private static let knownSingleKeys: Set<String> = [
        "tab", "enter", "return", "spacebar", "esc", "escape",
        "up", "down", "left", "right",
        "delete", "bs", "home", "end", "pageUp", "pageDown",
        "f1","f2","f3","f4","f5","f6","f7","f8","f9","f10",
        "f11","f12","f13","f14","f15","f16","f17","f18","f19","f20",
    ]

    static func lint(lines: [String]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        for (index, raw) in lines.enumerated() {
            let lineNum = index + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            // Each line should be wrapped in outer double-quotes: "..."
            guard trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 else {
                diagnostics.append(Diagnostic(
                    line: lineNum, severity: .error,
                    message: "Line must be wrapped in double quotes: \"...\""
                ))
                continue   // remaining checks are inside-string checks
            }

            // Strip outer quotes to get the inner content
            let inner = String(trimmed.dropFirst().dropLast())

            // Extract all <...> tokens
            let tokenPattern = try! NSRegularExpression(pattern: #"<([^>]+)>"#)
            let nsInner = inner as NSString
            let matches = tokenPattern.matches(in: inner, range: NSRange(location: 0, length: nsInner.length))

            var modifierStack: [String] = []   // stems currently "open"

            for match in matches {
                guard let tokenRange = Range(match.range(at: 1), in: inner) else { continue }
                let token = String(inner[tokenRange])

                // Wait token: waitNs or waitNNN
                if token.hasPrefix("wait") {
                    let suffix = token.dropFirst(4)  // after "wait"
                    let digits = suffix.hasSuffix("s") ? String(suffix.dropLast()) : String(suffix)
                    if digits.isEmpty || Int(digits) == nil {
                        diagnostics.append(Diagnostic(
                            line: lineNum, severity: .warning,
                            message: "Unrecognised wait token: <\(token)> — expected <waitNs> or <waitNNN>"
                        ))
                    }
                    continue
                }

                // Modifier On token
                if token.hasSuffix("On") {
                    let stem = String(token.dropLast(2))
                    if !modifierStems.contains(stem) {
                        diagnostics.append(Diagnostic(
                            line: lineNum, severity: .warning,
                            message: "Unknown modifier key: <\(token)>"
                        ))
                    } else {
                        modifierStack.append(stem)
                    }
                    continue
                }

                // Modifier Off token
                if token.hasSuffix("Off") {
                    let stem = String(token.dropLast(3))
                    if !modifierStems.contains(stem) {
                        diagnostics.append(Diagnostic(
                            line: lineNum, severity: .warning,
                            message: "Unknown modifier key: <\(token)>"
                        ))
                    } else if let last = modifierStack.last, last == stem {
                        modifierStack.removeLast()
                    } else if modifierStack.contains(stem) {
                        // Out-of-order close — pop up to and including it
                        while let top = modifierStack.last, top != stem {
                            diagnostics.append(Diagnostic(
                                line: lineNum, severity: .warning,
                                message: "Modifier <\(top)On> closed out of order — expected <\(top)Off> before <\(token)>"
                            ))
                            modifierStack.removeLast()
                        }
                        modifierStack.removeLast()
                    } else {
                        diagnostics.append(Diagnostic(
                            line: lineNum, severity: .warning,
                            message: "<\(token)> has no matching <\(stem)On>"
                        ))
                    }
                    continue
                }

                // click token: click 'label'
                if token.hasPrefix("click ") { continue }

                // Single key — must be in known set
                if !knownSingleKeys.contains(token) {
                    diagnostics.append(Diagnostic(
                        line: lineNum, severity: .warning,
                        message: "Unrecognised key token: <\(token)>"
                    ))
                }
            }

            // Any unclosed modifiers at end of line
            for stem in modifierStack {
                diagnostics.append(Diagnostic(
                    line: lineNum, severity: .warning,
                    message: "<\(stem)On> is never closed with <\(stem)Off> on this line"
                ))
            }
        }

        return diagnostics
    }
}
