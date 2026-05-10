import AppKit
import os

// TODO: wire Demark SPM dep for HTML → Markdown conversion

/// Handles intelligent paste into MacNoteTextView.
///
/// Priority:
///   1. `public.html`  → Demark (async, HTML → Markdown) → insert
///   2. `public.rtf`   → RTFToMarkdown.convert → insert
///   3. Plain text     → insert as-is
final class PasteHandler {

    private let logger = Logger.paste

    // MARK: - Entry point

    /// Called from `MacNoteTextView.paste(_:)`.
    func handle(pasteboard: NSPasteboard, into textView: NSTextView) {
        // 1. HTML → Markdown via Demark (async)
        if let htmlData = pasteboard.data(forType: .html),
           let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .isoLatin1) {
            logger.debug("Paste: handling HTML (\(htmlData.count) bytes) via Demark")
            convertHTMLAndInsert(html, into: textView)
            return
        }

        // 2. RTF → Markdown via RTFToMarkdown
        if let rtfData = pasteboard.data(forType: .rtf),
           let attrStr = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            logger.debug("Paste: handling RTF")
            let markdown = RTFToMarkdown.convert(attrStr)
            insert(markdown, into: textView)
            return
        }

        // 3. Plain text fallback
        if let text = pasteboard.string(forType: .string) {
            logger.debug("Paste: handling plain text (\(text.count) chars)")
            insert(text, into: textView)
            return
        }

        logger.warning("Paste: no usable content found on pasteboard")
    }

    // MARK: - Private

    /// Async HTML conversion via Demark, then insert on main thread.
    private func convertHTMLAndInsert(_ html: String, into textView: NSTextView) {
        // TODO: wire Demark SPM dep
        // import Demark
        // Task {
        //     let md = await Demark.convert(html)
        //     await MainActor.run { insert(md, into: textView) }
        // }

        // Fallback: strip HTML tags with a simple regex and insert plain text.
        let stripped = stripHTMLTags(html)
        insert(stripped, into: textView)
    }

    /// Insert `text` at the current selection in `textView`, respecting undo.
    private func insert(_ text: String, into textView: NSTextView) {
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        let newLocation = range.location + (text as NSString).length
        textView.setSelectedRange(NSRange(location: newLocation, length: 0))
    }

    /// Naively strip HTML tags using a regular expression.
    /// Demark will handle this properly once wired; this is just the fallback.
    private func stripHTMLTags(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return html
        }
        let range = NSRange(html.startIndex..., in: html)
        let stripped = regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
        // Decode common HTML entities
        return stripped
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
