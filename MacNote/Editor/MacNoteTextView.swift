import AppKit
import os

// MARK: - ImageAttachment

/// NSTextAttachment subclass that remembers its markdown source so `markdownContent`
/// can reconstruct the raw `![alt](filename)` string for saving.
final class ImageAttachment: NSTextAttachment {
    let markdownSource: String
    let filename: String

    init(image: NSImage, filename: String, markdownSource: String) {
        self.filename = filename
        self.markdownSource = markdownSource
        super.init(data: nil, ofType: nil)
        self.image = image
        // Non-zero initial bounds so TextKit renders the attachment before the
        // first layout pass calls attachmentBounds(for:...).
        let size = image.size
        if size.width > 0, size.height > 0 {
            bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        }
    }

    required init?(coder: NSCoder) { nil }

    /// Called by the layout engine on every layout pass.
    /// Scales the rendered rect to fill the available line width so the image
    /// fits the text container — no pixels are modified, only the display size.
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        guard let img = image, img.size.width > 0, img.size.height > 0 else { return bounds }
        let available = lineFrag.size.width
        guard available > 0 else { return bounds }
        let scale = available / img.size.width
        return CGRect(x: 0, y: 0,
                      width: (img.size.width * scale).rounded(),
                      height: (img.size.height * scale).rounded())
    }
}

// MARK: - MacNoteTextView

final class MacNoteTextView: NSTextView {

    // MARK: - Dependencies (set by coordinator / parent)

    var highlighterController: HighlighterController?
    var imageRenderer: ImageRenderer?
    var notesDirectory: URL = NoteStore.defaultNotesDirectory
    var currentNoteID: UUID?

    // MARK: - Private

    /// Captures: group 1 = alt text, group 2 = filename
    private static let imageSpanRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]*)\)"#)
    }()

    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let defaultAttrs: [NSAttributedString.Key: Any] = [.font: monoFont]

    // MARK: - Setup

    override func awakeFromNib() {
        super.awakeFromNib()
        commonSetup()
    }

    func commonSetup() {
        isRichText = true
        allowsUndo = true
        usesFindPanel = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        font = Self.monoFont
        typingAttributes = Self.defaultAttrs
        textContainerInset = NSSize(width: 16, height: 16)
    }

    // MARK: - Markdown load / extract

    /// Replace the text storage with the rendered form of `content`.
    /// `![alt](filename)` spans become `ImageAttachment` objects; plain text keeps its font.
    /// The delegate is suppressed so no spurious `textDidChange` fires during load.
    func loadMarkdown(_ content: String) {
        guard let ts = textStorage else { return }

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let matches = Self.imageSpanRegex.matches(in: content, range: fullRange)

        let result = NSMutableAttributedString()
        var cursor = 0

        for match in matches {
            // Text before this image span
            if match.range.location > cursor {
                let pre = NSRange(location: cursor, length: match.range.location - cursor)
                result.append(NSAttributedString(string: nsContent.substring(with: pre),
                                                 attributes: Self.defaultAttrs))
            }

            let matchStr = nsContent.substring(with: match.range)
            let filenameRange = match.range(at: 2)

            if filenameRange.location != NSNotFound, filenameRange.length > 0 {
                let filename = nsContent.substring(with: filenameRange)
                let imageURL = notesDirectory.appendingPathComponent(filename)
                let nsImage = NSImage(contentsOf: imageURL) ?? placeholderImage()
                let attachment = ImageAttachment(image: nsImage, filename: filename,
                                                 markdownSource: matchStr)
                result.append(NSAttributedString(attachment: attachment))
            } else {
                // Empty filename — keep as plain text
                result.append(NSAttributedString(string: matchStr, attributes: Self.defaultAttrs))
            }

            cursor = match.range.location + match.range.length
        }

        // Text after the last image span
        if cursor < nsContent.length {
            let tail = NSRange(location: cursor, length: nsContent.length - cursor)
            result.append(NSAttributedString(string: nsContent.substring(with: tail),
                                             attributes: Self.defaultAttrs))
        }

        let savedDelegate = delegate
        delegate = nil
        defer { delegate = savedDelegate }

        ts.beginEditing()
        ts.setAttributedString(result)
        ts.endEditing()

        typingAttributes = Self.defaultAttrs
    }

    /// Reconstruct the markdown string from the text storage.
    /// `ImageAttachment` runs emit their stored `markdownSource`; everything else emits the raw string.
    var markdownContent: String {
        guard let ts = textStorage else { return string }
        var result = ""
        ts.enumerateAttributes(in: NSRange(location: 0, length: ts.length), options: []) { attrs, range, _ in
            if let att = attrs[.attachment] as? ImageAttachment {
                result += att.markdownSource
            } else {
                result += (ts.string as NSString).substring(with: range)
            }
        }
        return result
    }

    // MARK: - Paste override

    override func paste(_ sender: Any?) {
        Logger.paste.debug("paste(_:) invoked")
        let pasteboard = NSPasteboard.general

        if let image = NSImage(pasteboard: pasteboard) {
            insertInlineImage(image, filename: nil)
            return
        }

        if let str = pasteboard.string(forType: .string) {
            insertText(str, replacementRange: selectedRange())
        }
    }

    // MARK: - Drag-and-drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.tiff.rawValue,
                                                      NSPasteboard.PasteboardType.png.rawValue,
                                                      "public.file-url"]) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Logger.paste.debug("performDragOperation(_:) invoked")
        let pb = sender.draggingPasteboard

        if let image = NSImage(pasteboard: pb) {
            var suggestedName: String? = nil
            if let urlString = pb.string(forType: .init("public.file-url")),
               let url = URL(string: urlString) {
                suggestedName = url.lastPathComponent
            }
            insertInlineImage(image, filename: suggestedName)
            return true
        }

        return super.performDragOperation(sender)
    }

    // MARK: - Smart cursor (skip over image attachments)

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.shift, .command, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123: // left arrow
            if trySkipAttachment(direction: .backward) { return }
        case 124: // right arrow
            if trySkipAttachment(direction: .forward) { return }
        default:
            break
        }

        super.keyDown(with: event)
    }

    // MARK: - Private helpers

    private enum Direction { case forward, backward }

    @discardableResult
    private func trySkipAttachment(direction: Direction) -> Bool {
        guard let ts = textStorage else { return false }
        let caret = selectedRange().location
        var skipped = false

        ts.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ts.length),
                              options: []) { value, range, stop in
            guard value is ImageAttachment else { return }
            switch direction {
            case .forward:
                if range.location == caret {
                    setSelectedRange(NSRange(location: range.location + range.length, length: 0))
                    skipped = true
                    stop.pointee = true
                }
            case .backward:
                if range.location + range.length == caret {
                    setSelectedRange(NSRange(location: range.location, length: 0))
                    skipped = true
                    stop.pointee = true
                }
            }
        }
        return skipped
    }

    /// Convert `image` to PNG, write via `ImageStore`, insert an `ImageAttachment` at the caret.
    private func insertInlineImage(_ image: NSImage, filename: String?) {
        guard let noteID = currentNoteID else {
            Logger.paste.warning("Image paste in draft mode — skipped")
            return
        }
        guard let pngData = image.pngRepresentation() else {
            Logger.paste.error("Could not convert image to PNG")
            return
        }
        let store = ImageStore(notesDirectory: notesDirectory)
        do {
            let name = try store.write(imageData: pngData, ext: "png", for: noteID)
            let markdown = "![](\(name))"
            let attachment = ImageAttachment(image: image, filename: name, markdownSource: markdown)
            let insertAt = selectedRange().location
            textStorage?.insert(NSAttributedString(attachment: attachment), at: insertAt)
            setSelectedRange(NSRange(location: insertAt + 1, length: 0))
            Logger.paste.info("Inserted inline image: \(name)")
        } catch {
            Logger.paste.error("Failed to save image: \(error)")
        }
    }

    private func placeholderImage() -> NSImage {
        NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - NSImage helpers

extension NSImage {
    func pngRepresentation() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
