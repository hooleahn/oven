import SwiftUI
import AppKit

// MARK: - HCL syntax-highlighted editor
// Uses NSTextView with a basic token-coloring overlay via textStorage.
// Highlights: keywords, strings, comments, variable references, block openers.

struct HCLEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    let onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.isEditable = isEditable
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.allowsUndo = true
        tv.delegate = context.coordinator
        tv.string = text
        context.coordinator.textView = tv
        HCLEditor.applyHighlighting(to: tv)
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
        }
    }
}
