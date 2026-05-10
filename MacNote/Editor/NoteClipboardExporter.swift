import AppKit
import UniformTypeIdentifiers

struct NoteClipboardExporter {
    static let manifestPasteboardType = NSPasteboard.PasteboardType("com.macnote.note+json")

    let notesDirectory: URL

    init(notesDirectory: URL = NoteStore.defaultNotesDirectory) {
        self.notesDirectory = notesDirectory
    }

    func copy(markdown: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let attributed = Self.richText(from: markdown, notesDirectory: notesDirectory)
        pasteboard.writeObjects([attributed])

        pasteboard.setString(markdown, forType: .string)
        pasteboard.setString(Self.htmlString(from: markdown, notesDirectory: notesDirectory), forType: .html)

        let fullRange = NSRange(location: 0, length: attributed.length)
        if let rtfd = attributed.rtfd(from: fullRange, documentAttributes: [:]) {
            pasteboard.setData(rtfd, forType: .rtfd)
        }
        if let rtf = attributed.rtf(from: fullRange, documentAttributes: [:]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let manifest = Self.manifestData(from: markdown, notesDirectory: notesDirectory) {
            pasteboard.setData(manifest, forType: Self.manifestPasteboardType)
        }
    }

    static func htmlString(from markdown: String, notesDirectory: URL) -> String {
        let body = renderSpans(from: markdown, notesDirectory: notesDirectory) { span in
            switch span {
            case .text(let text):
                return escapeHTML(text).replacingOccurrences(of: "\n", with: "<br>")
            case .image(let image):
                guard let dataURL = image.dataURL else {
                    return escapeHTML(image.source)
                }
                return "<img src=\"\(dataURL)\" alt=\"\(escapeHTMLAttribute(image.alt))\">"
            }
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"></head><body style="font-family: -apple-system, sans-serif; white-space: normal;">\(body)</body></html>
        """
    }

    static func richText(from markdown: String, notesDirectory: URL) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        renderSpans(from: markdown, notesDirectory: notesDirectory) { span in
            switch span {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: attrs))
            case .image(let image):
                guard let data = image.data else {
                    result.append(NSAttributedString(string: image.source, attributes: attrs))
                    break
                }
                let attachment = NSTextAttachment(data: data, ofType: image.utiIdentifier)
                if let nsImage = NSImage(data: data), nsImage.size.width > 0, nsImage.size.height > 0 {
                    let maxWidth: CGFloat = 720
                    let scale = min(1, maxWidth / nsImage.size.width)
                    attachment.bounds = CGRect(
                        x: 0,
                        y: 0,
                        width: (nsImage.size.width * scale).rounded(),
                        height: (nsImage.size.height * scale).rounded()
                    )
                }
                result.append(NSAttributedString(attachment: attachment))
            }
            return ""
        }
        return result
    }

    static func manifestData(from markdown: String, notesDirectory: URL) -> Data? {
        var images: [[String: String]] = []
        _ = renderSpans(from: markdown, notesDirectory: notesDirectory) { span in
            guard case .image(let image) = span, let data = image.data else { return "" }
            images.append([
                "source": image.source,
                "filename": image.filename,
                "alt": image.alt,
                "mimeType": image.mimeType,
                "base64": data.base64EncodedString()
            ])
            return ""
        }
        let payload: [String: Any] = [
            "markdown": markdown,
            "images": images
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    @discardableResult
    private static func renderSpans(
        from markdown: String,
        notesDirectory: URL,
        render: (Span) -> String
    ) -> String {
        let nsMarkdown = markdown as NSString
        let fullRange = NSRange(location: 0, length: nsMarkdown.length)
        let matches = imageSpanRegex.matches(in: markdown, range: fullRange)
        var cursor = 0
        var output = ""

        for match in matches {
            if match.range.location > cursor {
                let range = NSRange(location: cursor, length: match.range.location - cursor)
                output += render(.text(nsMarkdown.substring(with: range)))
            }

            let source = nsMarkdown.substring(with: match.range)
            let alt = match.range(at: 1).location == NSNotFound ? "" : nsMarkdown.substring(with: match.range(at: 1))
            let filename = match.range(at: 2).location == NSNotFound ? "" : nsMarkdown.substring(with: match.range(at: 2))
            output += render(.image(ImageSpan(source: source, alt: alt, filename: filename, notesDirectory: notesDirectory)))
            cursor = match.range.location + match.range.length
        }

        if cursor < nsMarkdown.length {
            let range = NSRange(location: cursor, length: nsMarkdown.length - cursor)
            output += render(.text(nsMarkdown.substring(with: range)))
        }
        return output
    }

    private enum Span {
        case text(String)
        case image(ImageSpan)
    }

    private struct ImageSpan {
        let source: String
        let alt: String
        let filename: String
        let notesDirectory: URL

        var url: URL {
            notesDirectory.appendingPathComponent(filename)
        }

        var data: Data? {
            try? Data(contentsOf: url)
        }

        var utiIdentifier: String {
            UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.png.identifier
        }

        var mimeType: String {
            UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        }

        var dataURL: String? {
            guard let data else { return nil }
            return "data:\(mimeType);base64,\(data.base64EncodedString())"
        }
    }

    private static let imageSpanRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]*)\)"#)
    }()

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeHTMLAttribute(_ string: String) -> String {
        escapeHTML(string)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
